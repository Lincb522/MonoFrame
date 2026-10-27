#ifndef CFFmpeg_shim_h
#define CFFmpeg_shim_h

#include "libavformat/avformat.h"
#include "libavformat/avio.h"
#include "libavcodec/avcodec.h"
#include "libavcodec/bsf.h"
#include "libavdevice/avdevice.h"
#include "libavutil/avutil.h"
#include "libavutil/opt.h"
#include "libavutil/channel_layout.h"
#include "libavutil/audio_fifo.h"
#include "libavutil/imgutils.h"
#include "libavutil/samplefmt.h"
#include "libavutil/mathematics.h"
#include "libavutil/error.h"
#include "libavutil/hwcontext.h"
#include "libavutil/hwcontext_videotoolbox.h"
#include "libswresample/swresample.h"
#include "libswscale/swscale.h"
#include "libavfilter/avfilter.h"
#include "libavfilter/buffersrc.h"
#include "libavfilter/buffersink.h"

typedef void (*mono_ffmpeg_progress_callback)(double progress, void *opaque);

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
);

#endif /* CFFmpeg_shim_h */
