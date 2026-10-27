import CFFmpeg
import Foundation

public struct FFmpegMediaInfo: Equatable, Sendable {
    public let hasVideo: Bool
    public let hasAudio: Bool
    public let duration: TimeInterval
    public let videoCodec: String?
    public let audioCodec: String?
    public let container: String
    public let width: Int?
    public let height: Int?
    public let frameRate: Double?
    public let sampleRate: Int?
    public let channelCount: Int?
}

public enum MediaConversionError: LocalizedError {
    case inputNotFound
    case cannotOpenInput
    case streamInfoUnavailable
    case transcodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .inputNotFound: "输入文件不存在"
        case .cannotOpenInput: "FFmpeg 无法打开输入文件"
        case .streamInfoUnavailable: "FFmpeg 无法读取媒体信息"
        case .transcodeFailed(let message): message
        }
    }
}

public final class FFmpegMediaInspector: @unchecked Sendable {
    public init() {}

    public func inspect(url: URL) async throws -> FFmpegMediaInfo {
        try await Task.detached(priority: .userInitiated) {
            try Self.inspectFile(url: url)
        }.value
    }

    private static func inspectFile(url: URL) throws -> FFmpegMediaInfo {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MediaConversionError.inputNotFound
        }
        var contextPointer: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_open_input(&contextPointer, url.path, nil, nil) >= 0,
              let context = contextPointer else {
            throw MediaConversionError.cannotOpenInput
        }
        defer { avformat_close_input(&contextPointer) }
        guard avformat_find_stream_info(context, nil) >= 0 else {
            throw MediaConversionError.streamInfoUnavailable
        }

        var videoCodec: String?
        var audioCodec: String?
        var width: Int?
        var height: Int?
        var frameRate: Double?
        var sampleRate: Int?
        var channelCount: Int?

        for index in 0..<Int(context.pointee.nb_streams) {
            guard let stream = context.pointee.streams[index],
                  let parameters = stream.pointee.codecpar else { continue }
            if parameters.pointee.codec_type == AVMEDIA_TYPE_VIDEO, videoCodec == nil {
                videoCodec = codecName(parameters.pointee.codec_id)
                width = Int(parameters.pointee.width)
                height = Int(parameters.pointee.height)
                let rate = stream.pointee.avg_frame_rate.den != 0
                    ? stream.pointee.avg_frame_rate
                    : stream.pointee.r_frame_rate
                if rate.den != 0 {
                    frameRate = Double(rate.num) / Double(rate.den)
                }
            } else if parameters.pointee.codec_type == AVMEDIA_TYPE_AUDIO, audioCodec == nil {
                audioCodec = codecName(parameters.pointee.codec_id)
                sampleRate = Int(parameters.pointee.sample_rate)
                channelCount = Int(parameters.pointee.ch_layout.nb_channels)
            }
        }

        let duration: TimeInterval
        if context.pointee.duration != Int64.min, context.pointee.duration > 0 {
            duration = Double(context.pointee.duration) / Double(AV_TIME_BASE)
        } else {
            duration = 0
        }
        let container = context.pointee.iformat.pointee.name
            .map(String.init(cString:)) ?? "unknown"
        return FFmpegMediaInfo(
            hasVideo: videoCodec != nil,
            hasAudio: audioCodec != nil,
            duration: duration,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            container: container,
            width: width,
            height: height,
            frameRate: frameRate,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }

    private static func codecName(_ id: AVCodecID) -> String {
        guard let name = avcodec_get_name(id) else { return "unknown" }
        return String(cString: name)
    }
}

public final class FFmpegAudioTranscoder: @unchecked Sendable {
    public typealias Progress = @Sendable (Double) -> Void

    public init() {}

    public func transcode(
        inputURL: URL,
        outputURL: URL,
        muxerName: String,
        encoderName: String,
        bitRate: Int = 256_000,
        sampleRate: Int = 0,
        channelCount: Int = 0,
        filterDescription: String? = nil,
        progress: Progress? = nil
    ) async throws -> URL {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let progressBox = ProgressBox(progress)
                let opaque = Unmanaged.passRetained(progressBox).toOpaque()
                defer { Unmanaged<ProgressBox>.fromOpaque(opaque).release() }
                var errorBuffer = [CChar](repeating: 0, count: 512)
                let result = errorBuffer.withUnsafeMutableBufferPointer { buffer in
                    inputURL.path.withCString { inputPath in
                        outputURL.path.withCString { outputPath in
                            muxerName.withCString { muxer in
                                encoderName.withCString { encoder in
                                    if let filterDescription {
                                        return filterDescription.withCString { filter in
                                            mono_ffmpeg_transcode_audio(
                                                inputPath,
                                                outputPath,
                                                muxer,
                                                encoder,
                                                Int32(bitRate),
                                                Int32(sampleRate),
                                                Int32(channelCount),
                                                filter,
                                                { value, context in
                                                    guard let context else { return }
                                                    let box = Unmanaged<ProgressBox>
                                                        .fromOpaque(context)
                                                        .takeUnretainedValue()
                                                    box.report(value)
                                                },
                                                opaque,
                                                buffer.baseAddress,
                                                Int32(buffer.count)
                                            )
                                        }
                                    }
                                    return mono_ffmpeg_transcode_audio(
                                        inputPath,
                                        outputPath,
                                        muxer,
                                        encoder,
                                        Int32(bitRate),
                                        Int32(sampleRate),
                                        Int32(channelCount),
                                        nil,
                                        { value, context in
                                            guard let context else { return }
                                            let box = Unmanaged<ProgressBox>
                                                .fromOpaque(context)
                                                .takeUnretainedValue()
                                            box.report(value)
                                        },
                                        opaque,
                                        buffer.baseAddress,
                                        Int32(buffer.count)
                                    )
                                }
                            }
                        }
                    }
                }

                guard result >= 0 else {
                    let message = errorBuffer.withUnsafeBufferPointer { buffer in
                        guard let address = buffer.baseAddress else { return "音频转码失败" }
                        let value = String(cString: address)
                        return value.isEmpty ? "音频转码失败" : value
                    }
                    continuation.resume(
                        throwing: MediaConversionError.transcodeFailed(message)
                    )
                    return
                }
                continuation.resume(returning: outputURL)
            }
        }
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let callback: FFmpegAudioTranscoder.Progress?

    init(_ callback: FFmpegAudioTranscoder.Progress?) {
        self.callback = callback
    }

    func report(_ value: Double) {
        callback?(min(max(value, 0), 1))
    }
}
