import CFFmpeg
import CoreGraphics
import CoreImage
import Foundation

public struct VideoInfo: Equatable, Sendable {
    public let duration: TimeInterval
    public let width: Int
    public let height: Int
    public let frameRate: Double
    public let bitrate: Int64
    public let videoCodec: String
    public let audioCodec: String?
    public let container: String
    public let hasAudio: Bool
    public let isHDR: Bool

    public init(
        duration: TimeInterval,
        width: Int,
        height: Int,
        frameRate: Double,
        bitrate: Int64,
        videoCodec: String,
        audioCodec: String?,
        container: String,
        hasAudio: Bool,
        isHDR: Bool
    ) {
        self.duration = duration
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.bitrate = bitrate
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.container = container
        self.hasAudio = hasAudio
        self.isHDR = isHDR
    }
}

public struct FastVideoExportResult: Equatable, Sendable {
    public let url: URL
    public let requestedStartTime: TimeInterval
    public let actualStartTime: TimeInterval
    public let duration: TimeInterval

    public var isKeyframeAdjusted: Bool {
        abs(requestedStartTime - actualStartTime) > 0.02
    }
}

public enum VideoProcessingError: LocalizedError, Equatable {
    case inputNotFound
    case cannotOpenInput
    case streamInfoUnavailable
    case missingVideo
    case unsupportedOutput
    case cannotOpenOutput
    case incompatibleClips
    case thumbnailUnavailable
    case ffmpeg(code: Int32, operation: String)

    public var errorDescription: String? {
        switch self {
        case .inputNotFound: "输入视频不存在"
        case .cannotOpenInput: "无法打开输入视频"
        case .streamInfoUnavailable: "无法读取媒体信息"
        case .missingVideo: "视频流不存在"
        case .unsupportedOutput: "当前 FFmpeg 构建不支持该输出格式"
        case .cannotOpenOutput: "无法创建输出视频"
        case .incompatibleClips: "片段的编码、分辨率或音频参数不一致"
        case .thumbnailUnavailable: "无法生成视频缩略帧"
        case .ffmpeg(_, let operation): "FFmpeg \(operation)失败"
        }
    }
}

/// File-oriented FFmpeg video tools.
///
/// `fastExport` and `concatenate` remux compressed packets without re-encoding,
/// preserving the original recording quality. A non-zero trim start is aligned
/// to the next video keyframe so the result always begins with a decodable frame.
public final class VideoProcessor: @unchecked Sendable {
    public typealias Progress = @Sendable (Double) -> Void

    private static let noPTS = Int64.min
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])

    public init() {}

    public func inspect(url: URL) throws -> VideoInfo {
        try Self.inspectFile(url: url)
    }

    public func inspect(url: URL) async throws -> VideoInfo {
        try await Task.detached(priority: .userInitiated) {
            try Self.inspectFile(url: url)
        }.value
    }

    public func thumbnails(
        url: URL,
        at times: [TimeInterval],
        maximumSize: CGSize = CGSize(width: 320, height: 320)
    ) async throws -> [CGImage] {
        try await Task.detached(priority: .userInitiated) {
            try times.map {
                try Self.makeThumbnail(url: url, at: max(0, $0), maximumSize: maximumSize)
            }
        }.value
    }

    public func fastExport(
        inputURL: URL,
        outputURL: URL,
        startTime: TimeInterval = 0,
        endTime: TimeInterval? = nil,
        keepAudio: Bool = true,
        progress: Progress? = nil
    ) async throws -> FastVideoExportResult {
        try await Task.detached(priority: .userInitiated) {
            try Self.remux(
                inputURL: inputURL,
                outputURL: outputURL,
                containerName: "mp4",
                startTime: max(0, startTime),
                endTime: endTime,
                keepAudio: keepAudio,
                progress: progress
            )
        }.value
    }

    /// Rewraps the original compressed streams in another FFmpeg container.
    /// No video or audio re-encoding is performed.
    public func remux(
        inputURL: URL,
        outputURL: URL,
        containerName: String,
        keepAudio: Bool = true,
        progress: Progress? = nil
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            _ = try Self.remux(
                inputURL: inputURL,
                outputURL: outputURL,
                containerName: containerName,
                startTime: 0,
                endTime: nil,
                keepAudio: keepAudio,
                progress: progress
            )
            return outputURL
        }.value
    }

    public func concatenate(
        inputURLs: [URL],
        outputURL: URL,
        keepAudio: Bool = true,
        progress: Progress? = nil
    ) async throws -> URL {
        guard inputURLs.count >= 2 else { throw VideoProcessingError.incompatibleClips }
        return try await Task.detached(priority: .userInitiated) {
            try Self.concatenateFiles(
                inputURLs: inputURLs,
                outputURL: outputURL,
                keepAudio: keepAudio,
                progress: progress
            )
            return outputURL
        }.value
    }
}

private extension VideoProcessor {
    struct StreamSignature: Equatable {
        let type: AVMediaType
        let codecID: AVCodecID
        let width: Int32
        let height: Int32
        let sampleRate: Int32
        let channelCount: Int32
    }

    static func inspectFile(url: URL) throws -> VideoInfo {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VideoProcessingError.inputNotFound
        }

        var contextPointer: UnsafeMutablePointer<AVFormatContext>?
        let openResult = avformat_open_input(&contextPointer, url.path, nil, nil)
        guard openResult >= 0, let context = contextPointer else {
            throw VideoProcessingError.cannotOpenInput
        }
        defer { avformat_close_input(&contextPointer) }

        guard avformat_find_stream_info(context, nil) >= 0 else {
            throw VideoProcessingError.streamInfoUnavailable
        }

        var videoParameters: UnsafeMutablePointer<AVCodecParameters>?
        var videoStream: UnsafeMutablePointer<AVStream>?
        var audioCodec: String?

        for index in 0..<Int(context.pointee.nb_streams) {
            guard let stream = context.pointee.streams[index],
                  let parameters = stream.pointee.codecpar else { continue }

            if parameters.pointee.codec_type == AVMEDIA_TYPE_VIDEO, videoParameters == nil {
                videoParameters = parameters
                videoStream = stream
            } else if parameters.pointee.codec_type == AVMEDIA_TYPE_AUDIO, audioCodec == nil {
                audioCodec = codecName(parameters.pointee.codec_id)
            }
        }

        guard let parameters = videoParameters, let stream = videoStream else {
            throw VideoProcessingError.missingVideo
        }

        let duration: TimeInterval
        if context.pointee.duration != noPTS, context.pointee.duration > 0 {
            duration = Double(context.pointee.duration) / Double(AV_TIME_BASE)
        } else if stream.pointee.duration != noPTS, stream.pointee.duration > 0 {
            duration = seconds(stream.pointee.duration, timeBase: stream.pointee.time_base)
        } else {
            duration = 0
        }

        let rate = stream.pointee.avg_frame_rate.den != 0
            ? stream.pointee.avg_frame_rate
            : stream.pointee.r_frame_rate
        let frameRate = rate.den == 0 ? 0 : Double(rate.num) / Double(rate.den)
        let formatName = context.pointee.iformat.pointee.name.map(String.init(cString:)) ?? "unknown"
        let bitrate = parameters.pointee.bit_rate > 0
            ? parameters.pointee.bit_rate
            : context.pointee.bit_rate
        let transfer = parameters.pointee.color_trc
        let hdr = transfer == AVCOL_TRC_SMPTE2084 || transfer == AVCOL_TRC_ARIB_STD_B67

        return VideoInfo(
            duration: duration,
            width: Int(parameters.pointee.width),
            height: Int(parameters.pointee.height),
            frameRate: frameRate,
            bitrate: bitrate,
            videoCodec: codecName(parameters.pointee.codec_id),
            audioCodec: audioCodec,
            container: formatName,
            hasAudio: audioCodec != nil,
            isHDR: hdr
        )
    }

    static func makeThumbnail(url: URL, at time: TimeInterval, maximumSize: CGSize) throws -> CGImage {
        var contextPointer: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_open_input(&contextPointer, url.path, nil, nil) >= 0,
              let context = contextPointer else {
            throw VideoProcessingError.cannotOpenInput
        }
        defer { avformat_close_input(&contextPointer) }

        guard avformat_find_stream_info(context, nil) >= 0 else {
            throw VideoProcessingError.streamInfoUnavailable
        }

        var videoIndex: Int32 = -1
        var videoStream: UnsafeMutablePointer<AVStream>?
        for index in 0..<Int(context.pointee.nb_streams) {
            guard let stream = context.pointee.streams[index],
                  let parameters = stream.pointee.codecpar,
                  parameters.pointee.codec_type == AVMEDIA_TYPE_VIDEO else { continue }
            videoIndex = Int32(index)
            videoStream = stream
            break
        }

        guard videoIndex >= 0,
              let stream = videoStream,
              let parameters = stream.pointee.codecpar else {
            throw VideoProcessingError.missingVideo
        }

        let decoder = try VideoDecoder(
            codecParameters: UnsafePointer(parameters),
            codecID: parameters.pointee.codec_id,
            timeBase: stream.pointee.time_base
        )

        let seekTimestamp = Int64(time * Double(stream.pointee.time_base.den) / Double(stream.pointee.time_base.num))
        if time > 0 {
            _ = av_seek_frame(context, videoIndex, seekTimestamp, AVSEEK_FLAG_BACKWARD)
            decoder.flush()
        }

        guard let packet = av_packet_alloc() else {
            throw VideoProcessingError.thumbnailUnavailable
        }
        defer {
            var packetPointer: UnsafeMutablePointer<AVPacket>? = packet
            av_packet_free(&packetPointer)
        }

        var fallbackFrame: VideoFrame?
        while av_read_frame(context, packet) >= 0 {
            defer { av_packet_unref(packet) }
            guard packet.pointee.stream_index == videoIndex else { continue }

            do {
                let frame = try decoder.decode(packet: packet)
                fallbackFrame = frame
                if frame.pts + max(frame.duration, 0.001) >= time {
                    return try render(frame: frame, maximumSize: maximumSize)
                }
            } catch {
                continue
            }
        }

        guard let fallbackFrame else { throw VideoProcessingError.thumbnailUnavailable }
        return try render(frame: fallbackFrame, maximumSize: maximumSize)
    }

    static func render(frame: VideoFrame, maximumSize: CGSize) throws -> CGImage {
        var image = CIImage(cvPixelBuffer: frame.pixelBuffer)
        let width = max(image.extent.width, 1)
        let height = max(image.extent.height, 1)
        let scale = min(
            max(maximumSize.width, 1) / width,
            max(maximumSize.height, 1) / height,
            1
        )
        if scale < 1 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else {
            throw VideoProcessingError.thumbnailUnavailable
        }
        return cgImage
    }

    static func remux(
        inputURL: URL,
        outputURL: URL,
        containerName: String,
        startTime: TimeInterval,
        endTime: TimeInterval?,
        keepAudio: Bool,
        progress: Progress?
    ) throws -> FastVideoExportResult {
        let info = try inspectFile(url: inputURL)
        let requestedEnd = min(max(endTime ?? info.duration, startTime + 0.01), info.duration)
        guard requestedEnd > startTime else { throw VideoProcessingError.missingVideo }

        var inputPointer: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_open_input(&inputPointer, inputURL.path, nil, nil) >= 0,
              let input = inputPointer else {
            throw VideoProcessingError.cannotOpenInput
        }
        defer { avformat_close_input(&inputPointer) }
        guard avformat_find_stream_info(input, nil) >= 0 else {
            throw VideoProcessingError.streamInfoUnavailable
        }

        try prepareOutputURL(outputURL)
        var outputPointer: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_alloc_output_context2(
            &outputPointer,
            nil,
            containerName,
            outputURL.path
        ) >= 0,
              let output = outputPointer else {
            throw VideoProcessingError.unsupportedOutput
        }

        var didOpenOutput = false
        defer {
            if didOpenOutput { avio_closep(&output.pointee.pb) }
            avformat_free_context(output)
        }

        var streamMap: [Int32: Int32] = [:]
        var videoInputIndex: Int32 = -1
        for index in 0..<Int(input.pointee.nb_streams) {
            guard let inputStream = input.pointee.streams[index],
                  let parameters = inputStream.pointee.codecpar else { continue }

            let isVideo = parameters.pointee.codec_type == AVMEDIA_TYPE_VIDEO
            let isAudio = parameters.pointee.codec_type == AVMEDIA_TYPE_AUDIO
            guard isVideo || (keepAudio && isAudio) else { continue }

            guard let outputStream = avformat_new_stream(output, nil) else {
                throw VideoProcessingError.cannotOpenOutput
            }
            let copyResult = avcodec_parameters_copy(outputStream.pointee.codecpar, parameters)
            guard copyResult >= 0 else {
                throw VideoProcessingError.ffmpeg(code: copyResult, operation: "复制流参数")
            }
            outputStream.pointee.codecpar.pointee.codec_tag = outputCodecTag(
                for: parameters.pointee.codec_id,
                containerName: containerName
            )
            outputStream.pointee.time_base = inputStream.pointee.time_base
            av_dict_copy(&outputStream.pointee.metadata, inputStream.pointee.metadata, 0)
            streamMap[Int32(index)] = outputStream.pointee.index
            if isVideo, videoInputIndex < 0 { videoInputIndex = Int32(index) }
        }
        guard videoInputIndex >= 0 else { throw VideoProcessingError.missingVideo }

        if output.pointee.oformat.pointee.flags & AVFMT_NOFILE == 0 {
            let openOutputResult = avio_open(&output.pointee.pb, outputURL.path, AVIO_FLAG_WRITE)
            guard openOutputResult >= 0 else {
                throw VideoProcessingError.ffmpeg(code: openOutputResult, operation: "打开输出")
            }
            didOpenOutput = true
        }

        var headerOptions: OpaquePointer?
        if containerName == "mp4" || containerName == "mov" || containerName == "ipod" {
            av_dict_set(&headerOptions, "movflags", "+faststart", 0)
        }
        let headerResult = avformat_write_header(output, &headerOptions)
        av_dict_free(&headerOptions)
        guard headerResult >= 0 else {
            throw VideoProcessingError.ffmpeg(code: headerResult, operation: "写入封装头")
        }

        if startTime > 0 {
            let seekTarget = Int64(startTime * Double(AV_TIME_BASE))
            _ = avformat_seek_file(input, -1, 0, seekTarget, seekTarget, AVSEEK_FLAG_BACKWARD)
        }

        guard let packet = av_packet_alloc() else {
            throw VideoProcessingError.cannotOpenOutput
        }
        defer {
            var packetPointer: UnsafeMutablePointer<AVPacket>? = packet
            av_packet_free(&packetPointer)
        }

        var effectiveStart: TimeInterval? = startTime == 0 ? 0 : nil
        var wroteVideo = false
        while av_read_frame(input, packet) >= 0 {
            defer { av_packet_unref(packet) }
            let inputIndex = packet.pointee.stream_index
            guard let outputIndex = streamMap[inputIndex],
                  let inputStream = input.pointee.streams[Int(inputIndex)],
                  let outputStream = output.pointee.streams[Int(outputIndex)] else { continue }

            let timestamp = packet.pointee.pts != noPTS ? packet.pointee.pts : packet.pointee.dts
            guard timestamp != noPTS else { continue }
            let packetTime = seconds(timestamp, timeBase: inputStream.pointee.time_base)

            if effectiveStart == nil {
                let isVideoPacket = inputIndex == videoInputIndex
                let isKeyframe = packet.pointee.flags & AV_PKT_FLAG_KEY != 0
                guard isVideoPacket, isKeyframe, packetTime >= startTime else { continue }
                effectiveStart = packetTime
            }
            guard let actualStart = effectiveStart else { continue }
            guard packetTime >= actualStart else { continue }
            if packetTime > requestedEnd {
                if inputIndex == videoInputIndex { break }
                continue
            }

            let offset = Int64(actualStart * Double(inputStream.pointee.time_base.den) / Double(inputStream.pointee.time_base.num))
            if packet.pointee.pts != noPTS { packet.pointee.pts -= offset }
            if packet.pointee.dts != noPTS { packet.pointee.dts -= offset }
            packet.pointee.stream_index = outputIndex
            packet.pointee.pos = -1
            av_packet_rescale_ts(packet, inputStream.pointee.time_base, outputStream.pointee.time_base)

            let writeResult = av_interleaved_write_frame(output, packet)
            guard writeResult >= 0 else {
                throw VideoProcessingError.ffmpeg(code: writeResult, operation: "写入数据包")
            }
            if inputIndex == videoInputIndex { wroteVideo = true }

            let fraction = (packetTime - actualStart) / max(requestedEnd - actualStart, 0.01)
            report(progress, value: fraction)
        }

        guard wroteVideo, let actualStart = effectiveStart else {
            throw VideoProcessingError.missingVideo
        }
        let trailerResult = av_write_trailer(output)
        guard trailerResult >= 0 else {
            throw VideoProcessingError.ffmpeg(code: trailerResult, operation: "完成封装")
        }
        report(progress, value: 1)

        return FastVideoExportResult(
            url: outputURL,
            requestedStartTime: startTime,
            actualStartTime: actualStart,
            duration: max(0, requestedEnd - actualStart)
        )
    }

    static func concatenateFiles(
        inputURLs: [URL],
        outputURL: URL,
        keepAudio: Bool,
        progress: Progress?
    ) throws {
        let infos = try inputURLs.map(inspectFile)
        let totalDuration = max(infos.reduce(0) { $0 + $1.duration }, 0.01)
        try prepareOutputURL(outputURL)

        var outputPointer: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_alloc_output_context2(&outputPointer, nil, "mp4", outputURL.path) >= 0,
              let output = outputPointer else {
            throw VideoProcessingError.unsupportedOutput
        }

        var didOpenOutput = false
        defer {
            if didOpenOutput { avio_closep(&output.pointee.pb) }
            avformat_free_context(output)
        }

        var referenceSignatures: [StreamSignature] = []
        var cumulativeSeconds: TimeInterval = 0
        var headerWritten = false

        for (fileIndex, inputURL) in inputURLs.enumerated() {
            var inputPointer: UnsafeMutablePointer<AVFormatContext>?
            guard avformat_open_input(&inputPointer, inputURL.path, nil, nil) >= 0,
                  let input = inputPointer else {
                throw VideoProcessingError.cannotOpenInput
            }
            defer { avformat_close_input(&inputPointer) }
            guard avformat_find_stream_info(input, nil) >= 0 else {
                throw VideoProcessingError.streamInfoUnavailable
            }

            let selected = selectedStreams(in: input, keepAudio: keepAudio)
            let signatures = selected.map { signature(for: $0.stream) }
            if fileIndex == 0 {
                referenceSignatures = signatures
                for item in selected {
                    guard let outputStream = avformat_new_stream(output, nil),
                          let parameters = item.stream.pointee.codecpar else {
                        throw VideoProcessingError.cannotOpenOutput
                    }
                    let result = avcodec_parameters_copy(outputStream.pointee.codecpar, parameters)
                    guard result >= 0 else {
                        throw VideoProcessingError.ffmpeg(code: result, operation: "复制流参数")
                    }
                    outputStream.pointee.codecpar.pointee.codec_tag = outputCodecTag(
                        for: parameters.pointee.codec_id,
                        containerName: outputURL.pathExtension.lowercased()
                    )
                    outputStream.pointee.time_base = item.stream.pointee.time_base
                }

                if output.pointee.oformat.pointee.flags & AVFMT_NOFILE == 0 {
                    let result = avio_open(&output.pointee.pb, outputURL.path, AVIO_FLAG_WRITE)
                    guard result >= 0 else {
                        throw VideoProcessingError.ffmpeg(code: result, operation: "打开输出")
                    }
                    didOpenOutput = true
                }
                var options: OpaquePointer?
                av_dict_set(&options, "movflags", "+faststart", 0)
                let result = avformat_write_header(output, &options)
                av_dict_free(&options)
                guard result >= 0 else {
                    throw VideoProcessingError.ffmpeg(code: result, operation: "写入封装头")
                }
                headerWritten = true
            } else if signatures != referenceSignatures {
                throw VideoProcessingError.incompatibleClips
            }

            let map = Dictionary(uniqueKeysWithValues: selected.enumerated().map {
                ($0.element.index, Int32($0.offset))
            })
            var firstTimestamp: [Int32: Int64] = [:]
            guard let packet = av_packet_alloc() else {
                throw VideoProcessingError.cannotOpenOutput
            }
            defer {
                var packetPointer: UnsafeMutablePointer<AVPacket>? = packet
                av_packet_free(&packetPointer)
            }

            while av_read_frame(input, packet) >= 0 {
                defer { av_packet_unref(packet) }
                let inputIndex = packet.pointee.stream_index
                guard let outputIndex = map[inputIndex],
                      let inputStream = input.pointee.streams[Int(inputIndex)],
                      let outputStream = output.pointee.streams[Int(outputIndex)] else { continue }

                let timestamp = packet.pointee.dts != noPTS ? packet.pointee.dts : packet.pointee.pts
                guard timestamp != noPTS else { continue }
                let origin = firstTimestamp[inputIndex] ?? timestamp
                firstTimestamp[inputIndex] = origin
                if packet.pointee.pts != noPTS { packet.pointee.pts -= origin }
                if packet.pointee.dts != noPTS { packet.pointee.dts -= origin }
                av_packet_rescale_ts(packet, inputStream.pointee.time_base, outputStream.pointee.time_base)

                let outputOffset = Int64(
                    cumulativeSeconds * Double(outputStream.pointee.time_base.den)
                        / Double(outputStream.pointee.time_base.num)
                )
                if packet.pointee.pts != noPTS { packet.pointee.pts += outputOffset }
                if packet.pointee.dts != noPTS { packet.pointee.dts += outputOffset }
                packet.pointee.stream_index = outputIndex
                packet.pointee.pos = -1

                let result = av_interleaved_write_frame(output, packet)
                guard result >= 0 else {
                    throw VideoProcessingError.ffmpeg(code: result, operation: "拼接数据包")
                }
            }

            cumulativeSeconds += infos[fileIndex].duration
            report(progress, value: cumulativeSeconds / totalDuration)
        }

        guard headerWritten else { throw VideoProcessingError.cannotOpenOutput }
        let trailerResult = av_write_trailer(output)
        guard trailerResult >= 0 else {
            throw VideoProcessingError.ffmpeg(code: trailerResult, operation: "完成拼接")
        }
        report(progress, value: 1)
    }

    static func selectedStreams(
        in context: UnsafeMutablePointer<AVFormatContext>,
        keepAudio: Bool
    ) -> [(index: Int32, stream: UnsafeMutablePointer<AVStream>)] {
        var streams: [(Int32, UnsafeMutablePointer<AVStream>)] = []
        var foundVideo = false
        var foundAudio = false
        for index in 0..<Int(context.pointee.nb_streams) {
            guard let stream = context.pointee.streams[index],
                  let parameters = stream.pointee.codecpar else { continue }
            if parameters.pointee.codec_type == AVMEDIA_TYPE_VIDEO, !foundVideo {
                streams.append((Int32(index), stream))
                foundVideo = true
            } else if parameters.pointee.codec_type == AVMEDIA_TYPE_AUDIO, keepAudio, !foundAudio {
                streams.append((Int32(index), stream))
                foundAudio = true
            }
        }
        return streams
    }

    static func signature(for stream: UnsafeMutablePointer<AVStream>) -> StreamSignature {
        guard let parameters = stream.pointee.codecpar else {
            return StreamSignature(
                type: AVMEDIA_TYPE_UNKNOWN,
                codecID: AV_CODEC_ID_NONE,
                width: 0,
                height: 0,
                sampleRate: 0,
                channelCount: 0
            )
        }
        return StreamSignature(
            type: parameters.pointee.codec_type,
            codecID: parameters.pointee.codec_id,
            width: parameters.pointee.width,
            height: parameters.pointee.height,
            sampleRate: parameters.pointee.sample_rate,
            channelCount: parameters.pointee.ch_layout.nb_channels
        )
    }

    static func outputCodecTag(for codecID: AVCodecID, containerName: String) -> UInt32 {
        let appleMovieContainer = ["mp4", "mov", "ipod", "m4v"]
            .contains(containerName.lowercased())
        guard appleMovieContainer else { return 0 }

        // Apple Photos requires parameter sets outside HEVC samples (`hvc1`).
        // Letting libavformat choose the default changes ReplayKit's `hvc1` to
        // `hev1`, which still plays but is rejected by PhotoKit as resource 3302.
        if codecID == AV_CODEC_ID_HEVC { return 0x31637668 } // hvc1
        return 0
    }

    static func codecName(_ codecID: AVCodecID) -> String {
        guard let pointer = avcodec_get_name(codecID) else { return "unknown" }
        return String(cString: pointer)
    }

    static func seconds(_ timestamp: Int64, timeBase: AVRational) -> TimeInterval {
        guard timeBase.den != 0 else { return 0 }
        return Double(timestamp) * Double(timeBase.num) / Double(timeBase.den)
    }

    static func prepareOutputURL(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func report(_ progress: Progress?, value: Double) {
        guard let progress else { return }
        let clamped = min(max(value, 0), 1)
        DispatchQueue.main.async { progress(clamped) }
    }
}
