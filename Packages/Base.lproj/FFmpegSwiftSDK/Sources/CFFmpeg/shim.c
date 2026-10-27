#include "shim.h"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void mono_set_error(char *buffer, int size, const char *operation, int code) {
    if (!buffer || size <= 0) return;
    char detail[AV_ERROR_MAX_STRING_SIZE] = {0};
    if (code < 0) {
        av_strerror(code, detail, sizeof(detail));
        snprintf(buffer, (size_t)size, "%s: %s", operation, detail);
    } else {
        snprintf(buffer, (size_t)size, "%s", operation);
    }
}

static int mono_supported_sample_rate(const AVCodec *codec, int requested) {
    const void *configurations = NULL;
    int configuration_count = 0;
    int result = avcodec_get_supported_config(
        NULL, codec, AV_CODEC_CONFIG_SAMPLE_RATE, 0,
        &configurations, &configuration_count
    );
    if (result < 0 || !configurations || configuration_count <= 0 || requested <= 0) {
        return requested > 0 ? requested : 48000;
    }
    const int *sample_rates = configurations;
    int selected = sample_rates[0];
    int distance = abs(selected - requested);
    for (int index = 0; index < configuration_count; index++) {
        int candidate_distance = abs(sample_rates[index] - requested);
        if (candidate_distance < distance) {
            selected = sample_rates[index];
            distance = candidate_distance;
        }
    }
    return selected;
}

static enum AVSampleFormat mono_sample_format(const AVCodec *codec) {
    const void *configurations = NULL;
    int configuration_count = 0;
    int result = avcodec_get_supported_config(
        NULL, codec, AV_CODEC_CONFIG_SAMPLE_FORMAT, 0,
        &configurations, &configuration_count
    );
    if (result >= 0 && configurations && configuration_count > 0) {
        const enum AVSampleFormat *sample_formats = configurations;
        return sample_formats[0];
    }
    return AV_SAMPLE_FMT_FLTP;
}

static int mono_channel_layout(
    const AVCodec *codec,
    int requested_channels,
    AVChannelLayout *layout
) {
    AVChannelLayout requested = {0};
    av_channel_layout_default(&requested, requested_channels > 0 ? requested_channels : 2);

    const void *configurations = NULL;
    int configuration_count = 0;
    int supported_result = avcodec_get_supported_config(
        NULL, codec, AV_CODEC_CONFIG_CHANNEL_LAYOUT, 0,
        &configurations, &configuration_count
    );
    if (supported_result < 0 || !configurations || configuration_count <= 0) {
        int result = av_channel_layout_copy(layout, &requested);
        av_channel_layout_uninit(&requested);
        return result;
    }

    const AVChannelLayout *channel_layouts = configurations;
    for (int index = 0; index < configuration_count; index++) {
        const AVChannelLayout *candidate = &channel_layouts[index];
        if (av_channel_layout_compare(candidate, &requested) == 0) {
            int result = av_channel_layout_copy(layout, candidate);
            av_channel_layout_uninit(&requested);
            return result;
        }
    }

    /*
     Pick the closest supported layout instead of blindly taking the first
     item.  Encoder lists commonly put mono first, which used to turn a
     multichannel FLAC into mono when the requested layout was unavailable.
     Prefer the largest layout that does not exceed the source, then the
     smallest layout above it.
    */
    int selected_index = 0;
    int selected_channels = channel_layouts[0].nb_channels;
    int requested_count = requested.nb_channels;
    for (int index = 1; index < configuration_count; index++) {
        int candidate_channels = channel_layouts[index].nb_channels;
        int selected_fits = selected_channels <= requested_count;
        int candidate_fits = candidate_channels <= requested_count;
        if ((candidate_fits && !selected_fits) ||
            (candidate_fits && candidate_channels > selected_channels) ||
            (!candidate_fits && !selected_fits && candidate_channels < selected_channels)) {
            selected_index = index;
            selected_channels = candidate_channels;
        }
    }

    int result = av_channel_layout_copy(layout, &channel_layouts[selected_index]);
    av_channel_layout_uninit(&requested);
    return result;
}

static int mono_write_encoded_packets(
    AVCodecContext *encoder,
    AVFormatContext *output,
    AVStream *stream,
    AVFrame *frame,
    AVPacket *packet
) {
    int result = avcodec_send_frame(encoder, frame);
    if (result < 0) return result;

    while (1) {
        result = avcodec_receive_packet(encoder, packet);
        if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) return 0;
        if (result < 0) return result;

        av_packet_rescale_ts(packet, encoder->time_base, stream->time_base);
        packet->stream_index = stream->index;
        packet->pos = -1;
        result = av_interleaved_write_frame(output, packet);
        av_packet_unref(packet);
        if (result < 0) return result;
    }
}

static int mono_add_converted_samples(
    SwrContext *resampler,
    AVAudioFifo *fifo,
    AVCodecContext *decoder,
    AVCodecContext *encoder,
    AVFrame *input_frame
) {
    int input_samples = input_frame ? input_frame->nb_samples : 0;
    int64_t delay = swr_get_delay(resampler, decoder->sample_rate);
    int output_capacity = (int)av_rescale_rnd(
        delay + input_samples,
        encoder->sample_rate,
        decoder->sample_rate,
        AV_ROUND_UP
    );
    if (output_capacity <= 0) return 0;

    AVFrame *converted = av_frame_alloc();
    if (!converted) return AVERROR(ENOMEM);
    converted->format = encoder->sample_fmt;
    converted->sample_rate = encoder->sample_rate;
    converted->nb_samples = output_capacity;
    int result = av_channel_layout_copy(&converted->ch_layout, &encoder->ch_layout);
    if (result < 0) {
        av_frame_free(&converted);
        return result;
    }
    result = av_frame_get_buffer(converted, 0);
    if (result < 0) {
        av_frame_free(&converted);
        return result;
    }

    const uint8_t **source = input_frame
        ? (const uint8_t **)input_frame->extended_data
        : NULL;
    int converted_samples = swr_convert(
        resampler,
        converted->extended_data,
        output_capacity,
        source,
        input_samples
    );
    if (converted_samples < 0) {
        av_frame_free(&converted);
        return converted_samples;
    }
    if (converted_samples == 0) {
        av_frame_free(&converted);
        return 0;
    }

    result = av_audio_fifo_realloc(fifo, av_audio_fifo_size(fifo) + converted_samples);
    if (result < 0) {
        av_frame_free(&converted);
        return result;
    }
    result = av_audio_fifo_write(
        fifo,
        (void * const *)converted->extended_data,
        converted_samples
    );
    av_frame_free(&converted);
    return result == converted_samples ? 0 : AVERROR(EIO);
}

static int mono_encode_fifo(
    AVAudioFifo *fifo,
    AVCodecContext *encoder,
    AVFormatContext *output,
    AVStream *stream,
    AVPacket *packet,
    int flush,
    int64_t *next_pts
) {
    int frame_size = encoder->frame_size > 0 ? encoder->frame_size : 1024;
    while (av_audio_fifo_size(fifo) >= frame_size || (flush && av_audio_fifo_size(fifo) > 0)) {
        int available = av_audio_fifo_size(fifo);
        int samples_to_read = FFMIN(available, frame_size);
        int samples_to_encode = encoder->frame_size > 0 ? frame_size : samples_to_read;

        AVFrame *frame = av_frame_alloc();
        if (!frame) return AVERROR(ENOMEM);
        frame->format = encoder->sample_fmt;
        frame->sample_rate = encoder->sample_rate;
        frame->nb_samples = samples_to_encode;
        int result = av_channel_layout_copy(&frame->ch_layout, &encoder->ch_layout);
        if (result < 0) {
            av_frame_free(&frame);
            return result;
        }
        result = av_frame_get_buffer(frame, 0);
        if (result < 0) {
            av_frame_free(&frame);
            return result;
        }

        int read = av_audio_fifo_read(
            fifo,
            (void * const *)frame->extended_data,
            samples_to_read
        );
        if (read < samples_to_read) {
            av_frame_free(&frame);
            return AVERROR(EIO);
        }
        if (samples_to_encode > samples_to_read) {
            av_samples_set_silence(
                frame->extended_data,
                samples_to_read,
                samples_to_encode - samples_to_read,
                encoder->ch_layout.nb_channels,
                encoder->sample_fmt
            );
        }

        frame->pts = *next_pts;
        *next_pts += samples_to_encode;
        result = mono_write_encoded_packets(encoder, output, stream, frame, packet);
        av_frame_free(&frame);
        if (result < 0) return result;
    }
    return 0;
}

static int mono_create_audio_filter(
    const char *description,
    AVCodecContext *decoder,
    AVFilterGraph **graph_out,
    AVFilterContext **source_out,
    AVFilterContext **sink_out
) {
    if (!description || description[0] == '\0') return 0;
    const AVFilter *source_filter = avfilter_get_by_name("abuffer");
    const AVFilter *sink_filter = avfilter_get_by_name("abuffersink");
    if (!source_filter || !sink_filter) return AVERROR_FILTER_NOT_FOUND;

    AVFilterGraph *graph = avfilter_graph_alloc();
    AVFilterContext *source = NULL;
    AVFilterContext *sink = NULL;
    AVFilterInOut *inputs = NULL;
    AVFilterInOut *outputs = NULL;
    char channel_layout[128] = {0};
    char source_args[512] = {0};
    int result = av_channel_layout_describe(&decoder->ch_layout, channel_layout, sizeof(channel_layout));
    if (result < 0) goto fail;
    const char *sample_format = av_get_sample_fmt_name(decoder->sample_fmt);
    if (!sample_format) {
        result = AVERROR(EINVAL);
        goto fail;
    }
    snprintf(
        source_args,
        sizeof(source_args),
        "time_base=1/%d:sample_rate=%d:sample_fmt=%s:channel_layout=%s",
        decoder->sample_rate,
        decoder->sample_rate,
        sample_format,
        channel_layout
    );
    result = avfilter_graph_create_filter(&source, source_filter, "in", source_args, NULL, graph);
    if (result < 0) goto fail;
    result = avfilter_graph_create_filter(&sink, sink_filter, "out", NULL, NULL, graph);
    if (result < 0) goto fail;

    size_t graph_size = strlen(description) + strlen(sample_format) + strlen(channel_layout) + 160;
    char *full_description = malloc(graph_size);
    if (!full_description) {
        result = AVERROR(ENOMEM);
        goto fail;
    }
    snprintf(
        full_description,
        graph_size,
        "%s,aformat=sample_fmts=%s:sample_rates=%d:channel_layouts=%s",
        description,
        sample_format,
        decoder->sample_rate,
        channel_layout
    );

    inputs = avfilter_inout_alloc();
    outputs = avfilter_inout_alloc();
    if (!inputs || !outputs) {
        free(full_description);
        result = AVERROR(ENOMEM);
        goto fail;
    }
    outputs->name = av_strdup("in");
    outputs->filter_ctx = source;
    outputs->pad_idx = 0;
    outputs->next = NULL;
    inputs->name = av_strdup("out");
    inputs->filter_ctx = sink;
    inputs->pad_idx = 0;
    inputs->next = NULL;

    result = avfilter_graph_parse_ptr(graph, full_description, &inputs, &outputs, NULL);
    free(full_description);
    if (result < 0) goto fail;
    result = avfilter_graph_config(graph, NULL);
    if (result < 0) goto fail;

    avfilter_inout_free(&inputs);
    avfilter_inout_free(&outputs);
    *graph_out = graph;
    *source_out = source;
    *sink_out = sink;
    return 0;

fail:
    avfilter_inout_free(&inputs);
    avfilter_inout_free(&outputs);
    if (graph) avfilter_graph_free(&graph);
    return result;
}

int mono_ffmpeg_transcode_audio(
    const char *input_path,
    const char *output_path,
    const char *muxer_name,
    const char *encoder_name,
    int bit_rate,
    int sample_rate,
    int channel_count,
    const char *filter_description,
    mono_ffmpeg_progress_callback progress_callback,
    void *progress_opaque,
    char *error_buffer,
    int error_buffer_size
) {
    int result = 0;
    int audio_index = -1;
    int wrote_header = 0;
    int opened_output = 0;
    int64_t next_pts = 0;
    AVFormatContext *input = NULL;
    AVFormatContext *output = NULL;
    AVCodecContext *decoder = NULL;
    AVCodecContext *encoder = NULL;
    SwrContext *resampler = NULL;
    AVAudioFifo *fifo = NULL;
    AVFrame *decoded_frame = NULL;
    AVPacket *input_packet = NULL;
    AVPacket *output_packet = NULL;
    AVStream *input_stream = NULL;
    AVStream *output_stream = NULL;
    AVFilterGraph *filter_graph = NULL;
    AVFilterContext *filter_source = NULL;
    AVFilterContext *filter_sink = NULL;
    AVFrame *filtered_frame = NULL;

    if (error_buffer && error_buffer_size > 0) error_buffer[0] = '\0';
    if (!input_path || !output_path || !muxer_name || !encoder_name) {
        mono_set_error(error_buffer, error_buffer_size, "转码参数无效", 0);
        return AVERROR(EINVAL);
    }

    result = avformat_open_input(&input, input_path, NULL, NULL);
    if (result < 0) {
        mono_set_error(error_buffer, error_buffer_size, "无法打开输入文件", result);
        goto cleanup;
    }
    result = avformat_find_stream_info(input, NULL);
    if (result < 0) {
        mono_set_error(error_buffer, error_buffer_size, "无法读取媒体流", result);
        goto cleanup;
    }

    audio_index = av_find_best_stream(input, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (audio_index < 0) {
        result = audio_index;
        mono_set_error(error_buffer, error_buffer_size, "输入文件没有音轨", result);
        goto cleanup;
    }
    input_stream = input->streams[audio_index];

    const AVCodec *decoder_codec = avcodec_find_decoder(input_stream->codecpar->codec_id);
    if (!decoder_codec) {
        result = AVERROR_DECODER_NOT_FOUND;
        mono_set_error(error_buffer, error_buffer_size, "找不到输入解码器", result);
        goto cleanup;
    }
    decoder = avcodec_alloc_context3(decoder_codec);
    if (!decoder) {
        result = AVERROR(ENOMEM);
        mono_set_error(error_buffer, error_buffer_size, "无法创建解码器", result);
        goto cleanup;
    }
    result = avcodec_parameters_to_context(decoder, input_stream->codecpar);
    if (result < 0 || (result = avcodec_open2(decoder, decoder_codec, NULL)) < 0) {
        mono_set_error(error_buffer, error_buffer_size, "无法打开输入解码器", result);
        goto cleanup;
    }
    if (decoder->ch_layout.nb_channels <= 0) {
        av_channel_layout_default(&decoder->ch_layout, 2);
    }

    result = mono_create_audio_filter(
        filter_description, decoder, &filter_graph, &filter_source, &filter_sink
    );
    if (result < 0) {
        mono_set_error(error_buffer, error_buffer_size, "无法创建音频滤镜链", result);
        goto cleanup;
    }
    if (filter_graph) {
        filtered_frame = av_frame_alloc();
        if (!filtered_frame) {
            result = AVERROR(ENOMEM);
            mono_set_error(error_buffer, error_buffer_size, "无法创建滤镜缓冲区", result);
            goto cleanup;
        }
    }

    const AVCodec *encoder_codec = avcodec_find_encoder_by_name(encoder_name);
    if (!encoder_codec) {
        result = AVERROR_ENCODER_NOT_FOUND;
        mono_set_error(error_buffer, error_buffer_size, "当前 FFmpeg 未包含该编码器", result);
        goto cleanup;
    }
    encoder = avcodec_alloc_context3(encoder_codec);
    if (!encoder) {
        result = AVERROR(ENOMEM);
        mono_set_error(error_buffer, error_buffer_size, "无法创建输出编码器", result);
        goto cleanup;
    }
    encoder->sample_rate = mono_supported_sample_rate(
        encoder_codec,
        sample_rate > 0 ? sample_rate : decoder->sample_rate
    );
    encoder->sample_fmt = mono_sample_format(encoder_codec);
    encoder->time_base = (AVRational){1, encoder->sample_rate};
    /* Lossless and PCM encoders must not receive a made-up lossy bitrate. */
    encoder->bit_rate = bit_rate > 0 ? bit_rate : 0;
    encoder->strict_std_compliance = FF_COMPLIANCE_EXPERIMENTAL;
    result = mono_channel_layout(
        encoder_codec,
        channel_count > 0 ? channel_count : decoder->ch_layout.nb_channels,
        &encoder->ch_layout
    );
    if (result < 0) {
        mono_set_error(error_buffer, error_buffer_size, "不支持所选声道布局", result);
        goto cleanup;
    }

    result = avformat_alloc_output_context2(&output, NULL, muxer_name, output_path);
    if (result < 0 || !output) {
        if (result >= 0) result = AVERROR_MUXER_NOT_FOUND;
        mono_set_error(error_buffer, error_buffer_size, "找不到输出封装器", result);
        goto cleanup;
    }
    if (output->oformat->flags & AVFMT_GLOBALHEADER) {
        encoder->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    }
    result = avcodec_open2(encoder, encoder_codec, NULL);
    if (result < 0) {
        mono_set_error(error_buffer, error_buffer_size, "无法打开输出编码器", result);
        goto cleanup;
    }

    output_stream = avformat_new_stream(output, NULL);
    if (!output_stream) {
        result = AVERROR(ENOMEM);
        mono_set_error(error_buffer, error_buffer_size, "无法创建输出音轨", result);
        goto cleanup;
    }
    output_stream->time_base = encoder->time_base;
    result = avcodec_parameters_from_context(output_stream->codecpar, encoder);
    if (result < 0) {
        mono_set_error(error_buffer, error_buffer_size, "无法写入编码参数", result);
        goto cleanup;
    }

    result = swr_alloc_set_opts2(
        &resampler,
        &encoder->ch_layout,
        encoder->sample_fmt,
        encoder->sample_rate,
        &decoder->ch_layout,
        decoder->sample_fmt,
        decoder->sample_rate,
        0,
        NULL
    );
    if (result < 0 || !resampler || (result = swr_init(resampler)) < 0) {
        mono_set_error(error_buffer, error_buffer_size, "无法创建音频重采样器", result);
        goto cleanup;
    }

    fifo = av_audio_fifo_alloc(encoder->sample_fmt, encoder->ch_layout.nb_channels, 1);
    decoded_frame = av_frame_alloc();
    input_packet = av_packet_alloc();
    output_packet = av_packet_alloc();
    if (!fifo || !decoded_frame || !input_packet || !output_packet) {
        result = AVERROR(ENOMEM);
        mono_set_error(error_buffer, error_buffer_size, "音频缓冲区创建失败", result);
        goto cleanup;
    }

    if (!(output->oformat->flags & AVFMT_NOFILE)) {
        result = avio_open(&output->pb, output_path, AVIO_FLAG_WRITE);
        if (result < 0) {
            mono_set_error(error_buffer, error_buffer_size, "无法创建输出文件", result);
            goto cleanup;
        }
        opened_output = 1;
    }
    AVDictionary *header_options = NULL;
    if (!strcmp(muxer_name, "ipod") || !strcmp(muxer_name, "mov") || !strcmp(muxer_name, "mp4")) {
        av_dict_set(&header_options, "movflags", "+faststart", 0);
    }
    result = avformat_write_header(output, &header_options);
    av_dict_free(&header_options);
    if (result < 0) {
        mono_set_error(error_buffer, error_buffer_size, "无法写入输出文件头", result);
        goto cleanup;
    }
    wrote_header = 1;

    while ((result = av_read_frame(input, input_packet)) >= 0) {
        if (input_packet->stream_index != audio_index) {
            av_packet_unref(input_packet);
            continue;
        }
        result = avcodec_send_packet(decoder, input_packet);
        av_packet_unref(input_packet);
        if (result < 0) {
            mono_set_error(error_buffer, error_buffer_size, "音频解码失败", result);
            goto cleanup;
        }

        while ((result = avcodec_receive_frame(decoder, decoded_frame)) >= 0) {
            int64_t timestamp = decoded_frame->best_effort_timestamp;
            if (filter_graph) {
                decoded_frame->pts = timestamp == AV_NOPTS_VALUE ? AV_NOPTS_VALUE : av_rescale_q(
                    timestamp, input_stream->time_base, (AVRational){1, decoder->sample_rate}
                );
                result = av_buffersrc_add_frame_flags(
                    filter_source, decoded_frame, AV_BUFFERSRC_FLAG_KEEP_REF
                );
                av_frame_unref(decoded_frame);
                if (result < 0) {
                    mono_set_error(error_buffer, error_buffer_size, "音频滤镜输入失败", result);
                    goto cleanup;
                }
                while ((result = av_buffersink_get_frame(filter_sink, filtered_frame)) >= 0) {
                    int conversion_result = mono_add_converted_samples(
                        resampler, fifo, decoder, encoder, filtered_frame
                    );
                    av_frame_unref(filtered_frame);
                    if (conversion_result < 0) {
                        result = conversion_result;
                        mono_set_error(error_buffer, error_buffer_size, "音频重采样失败", result);
                        goto cleanup;
                    }
                }
                if (result != AVERROR(EAGAIN) && result != AVERROR_EOF) {
                    mono_set_error(error_buffer, error_buffer_size, "音频滤镜处理失败", result);
                    goto cleanup;
                }
            } else {
                result = mono_add_converted_samples(resampler, fifo, decoder, encoder, decoded_frame);
                av_frame_unref(decoded_frame);
                if (result < 0) {
                    mono_set_error(error_buffer, error_buffer_size, "音频重采样失败", result);
                    goto cleanup;
                }
            }
            result = mono_encode_fifo(
                fifo, encoder, output, output_stream, output_packet, 0, &next_pts
            );
            if (result < 0) {
                mono_set_error(error_buffer, error_buffer_size, "音频编码失败", result);
                goto cleanup;
            }
            if (progress_callback && input->duration > 0 && timestamp != AV_NOPTS_VALUE) {
                double current = timestamp * av_q2d(input_stream->time_base);
                double duration = (double)input->duration / AV_TIME_BASE;
                progress_callback(FFMIN(0.99, FFMAX(0.0, current / duration)), progress_opaque);
            }
        }
        if (result != AVERROR(EAGAIN) && result != AVERROR_EOF) {
            mono_set_error(error_buffer, error_buffer_size, "音频解码失败", result);
            goto cleanup;
        }
    }
    if (result != AVERROR_EOF) {
        mono_set_error(error_buffer, error_buffer_size, "媒体读取失败", result);
        goto cleanup;
    }

    result = avcodec_send_packet(decoder, NULL);
    if (result >= 0) {
        while ((result = avcodec_receive_frame(decoder, decoded_frame)) >= 0) {
            if (filter_graph) {
                decoded_frame->pts = decoded_frame->best_effort_timestamp == AV_NOPTS_VALUE
                    ? AV_NOPTS_VALUE
                    : av_rescale_q(
                        decoded_frame->best_effort_timestamp,
                        input_stream->time_base,
                        (AVRational){1, decoder->sample_rate}
                    );
                result = av_buffersrc_add_frame_flags(
                    filter_source, decoded_frame, AV_BUFFERSRC_FLAG_KEEP_REF
                );
                av_frame_unref(decoded_frame);
                if (result < 0) {
                    mono_set_error(error_buffer, error_buffer_size, "音频滤镜输入失败", result);
                    goto cleanup;
                }
            } else {
                result = mono_add_converted_samples(resampler, fifo, decoder, encoder, decoded_frame);
                av_frame_unref(decoded_frame);
                if (result < 0) {
                    mono_set_error(error_buffer, error_buffer_size, "音频重采样失败", result);
                    goto cleanup;
                }
            }
        }
    }

    if (filter_graph) {
        result = av_buffersrc_add_frame_flags(filter_source, NULL, 0);
        if (result < 0) {
            mono_set_error(error_buffer, error_buffer_size, "音频滤镜收尾失败", result);
            goto cleanup;
        }
        while ((result = av_buffersink_get_frame(filter_sink, filtered_frame)) >= 0) {
            int conversion_result = mono_add_converted_samples(
                resampler, fifo, decoder, encoder, filtered_frame
            );
            av_frame_unref(filtered_frame);
            if (conversion_result < 0) {
                result = conversion_result;
                mono_set_error(error_buffer, error_buffer_size, "音频重采样失败", result);
                goto cleanup;
            }
        }
        if (result != AVERROR_EOF && result != AVERROR(EAGAIN)) {
            mono_set_error(error_buffer, error_buffer_size, "音频滤镜收尾失败", result);
            goto cleanup;
        }
    }

    while (swr_get_delay(resampler, decoder->sample_rate) > 0) {
        int before = av_audio_fifo_size(fifo);
        result = mono_add_converted_samples(resampler, fifo, decoder, encoder, NULL);
        if (result < 0) {
            mono_set_error(error_buffer, error_buffer_size, "音频重采样收尾失败", result);
            goto cleanup;
        }
        if (av_audio_fifo_size(fifo) == before) break;
    }

    result = mono_encode_fifo(
        fifo, encoder, output, output_stream, output_packet, 1, &next_pts
    );
    if (result < 0) {
        mono_set_error(error_buffer, error_buffer_size, "音频编码收尾失败", result);
        goto cleanup;
    }
    result = mono_write_encoded_packets(encoder, output, output_stream, NULL, output_packet);
    if (result < 0) {
        mono_set_error(error_buffer, error_buffer_size, "音频编码器收尾失败", result);
        goto cleanup;
    }
    result = av_write_trailer(output);
    if (result < 0) {
        mono_set_error(error_buffer, error_buffer_size, "无法完成输出文件", result);
        goto cleanup;
    }
    wrote_header = 0;
    if (progress_callback) progress_callback(1.0, progress_opaque);
    result = 0;

cleanup:
    if (result < 0 && wrote_header && output) av_write_trailer(output);
    if (opened_output && output) avio_closep(&output->pb);
    if (output) avformat_free_context(output);
    if (input) avformat_close_input(&input);
    if (decoder) avcodec_free_context(&decoder);
    if (encoder) avcodec_free_context(&encoder);
    if (resampler) swr_free(&resampler);
    if (fifo) av_audio_fifo_free(fifo);
    if (decoded_frame) av_frame_free(&decoded_frame);
    if (input_packet) av_packet_free(&input_packet);
    if (output_packet) av_packet_free(&output_packet);
    if (filtered_frame) av_frame_free(&filtered_frame);
    if (filter_graph) avfilter_graph_free(&filter_graph);
    if (result < 0) remove(output_path);
    return result;
}
