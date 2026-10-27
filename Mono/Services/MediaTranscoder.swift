@preconcurrency import AVFoundation
import FFmpegSwiftSDK
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum MediaTranscodeTarget: String, CaseIterable, Identifiable {
    case h264MP4
    case hevcMP4
    case h264MOV
    case hevcMOV
    case h264M4V
    case proRes422Proxy
    case proRes422LT
    case proRes422
    case proRes422HQ
    case proRes4444
    case motionJPEG
    case animatedGIF
    case matroska
    case mpegTS
    case avi
    case flv
    case webM
    case asf
    case mpegPS
    case vob
    case nut
    case mxf
    case ogv
    case realMedia
    case m4a
    case aac
    case latmAAC
    case mp3
    case flac
    case oggVorbis
    case oggOpus
    case alac
    case wav16
    case wav24
    case wav32
    case wavFloat
    case wavFloat64
    case aiff
    case cafALAC
    case cafPCM24
    case auPCM16
    case auMuLaw
    case auALaw
    case w64PCM24
    case vocPCM16
    case wavPack
    case tta
    case ac3
    case eac3
    case mp2
    case g722
    case g726
    case aptX
    case aptXHD
    case iLBC
    case trueHD
    case mlp
    case dts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .h264MP4: "H.264"
        case .hevcMP4: "HEVC"
        case .h264MOV: "H.264 MOV"
        case .hevcMOV: "HEVC MOV"
        case .h264M4V: "H.264 M4V"
        case .proRes422Proxy: "ProRes 422 Proxy"
        case .proRes422LT: "ProRes 422 LT"
        case .proRes422: "ProRes 422"
        case .proRes422HQ: "ProRes 422 HQ"
        case .proRes4444: "ProRes 4444"
        case .motionJPEG: "Motion JPEG"
        case .animatedGIF: "动态 GIF"
        case .matroska: "MKV"
        case .mpegTS: "MPEG-TS"
        case .avi: "AVI"
        case .flv: "FLV"
        case .webM: "WebM"
        case .asf: "WMV / ASF"
        case .mpegPS: "MPEG-PS"
        case .vob: "VOB"
        case .nut: "NUT"
        case .mxf: "MXF"
        case .ogv: "OGV"
        case .realMedia: "RealMedia"
        case .m4a: "M4A"
        case .aac: "AAC"
        case .latmAAC: "AAC LATM"
        case .mp3: "MP3"
        case .flac: "FLAC"
        case .oggVorbis: "OGG Vorbis"
        case .oggOpus: "OGG Opus"
        case .alac: "ALAC"
        case .wav16: "WAV 16"
        case .wav24: "WAV 24"
        case .wav32: "WAV 32"
        case .wavFloat: "WAV Float"
        case .wavFloat64: "WAV Float 64"
        case .aiff: "AIFF"
        case .cafALAC: "CAF ALAC"
        case .cafPCM24: "CAF PCM 24"
        case .auPCM16: "AU PCM 16"
        case .auMuLaw: "AU μ-law"
        case .auALaw: "AU A-law"
        case .w64PCM24: "Wave64 PCM 24"
        case .vocPCM16: "VOC PCM 16"
        case .wavPack: "WavPack"
        case .tta: "TTA"
        case .ac3: "AC-3"
        case .eac3: "E-AC-3"
        case .mp2: "MP2"
        case .g722: "G.722"
        case .g726: "G.726"
        case .aptX: "aptX"
        case .aptXHD: "aptX HD"
        case .iLBC: "iLBC"
        case .trueHD: "TrueHD"
        case .mlp: "MLP"
        case .dts: "DTS"
        }
    }

    var detail: String {
        switch self {
        case .h264MP4: "MP4  ·  兼容"
        case .hevcMP4: "MP4  ·  高效"
        case .h264MOV, .hevcMOV: "MOV  ·  VT"
        case .h264M4V: "M4V  ·  兼容"
        case .proRes422Proxy: "MOV  ·  代理"
        case .proRes422LT: "MOV  ·  轻量"
        case .proRes422: "MOV  ·  标准"
        case .proRes422HQ: "MOV  ·  高质量"
        case .proRes4444: "MOV  ·  高保真"
        case .motionJPEG: "MOV  ·  帧内"
        case .animatedGIF: "GIF  ·  动画"
        case .matroska, .mpegTS, .avi, .flv, .webM, .asf,
             .mpegPS, .vob, .nut, .mxf, .ogv, .realMedia: "直接封装"
        case .m4a, .aac: "AAC  ·  256K"
        case .latmAAC: "AAC  ·  LATM"
        case .mp3: "LAME  ·  320K"
        case .flac, .alac, .cafALAC, .wavPack, .tta, .trueHD, .mlp: "无损"
        case .oggVorbis: "VORBIS  ·  256K"
        case .oggOpus: "OPUS  ·  192K"
        case .wav16: "PCM  ·  16BIT"
        case .wav24: "PCM  ·  24BIT"
        case .wav32: "PCM  ·  32BIT"
        case .wavFloat: "PCM  ·  FLOAT32"
        case .wavFloat64: "PCM  ·  FLOAT64"
        case .aiff: "PCM  ·  BIG ENDIAN"
        case .cafPCM24, .w64PCM24: "PCM  ·  24BIT"
        case .auPCM16, .vocPCM16: "PCM  ·  16BIT"
        case .auMuLaw: "G.711  ·  μ-LAW"
        case .auALaw: "G.711  ·  A-LAW"
        case .ac3, .eac3: "DOLBY  ·  640K"
        case .mp2: "MPEG AUDIO  ·  320K"
        case .g722: "ADPCM  ·  64K"
        case .g726: "ADPCM  ·  32K"
        case .aptX: "BLUETOOTH  ·  352K"
        case .aptXHD: "BLUETOOTH  ·  576K"
        case .iLBC: "VOICE  ·  15K"
        case .dts: "DTS  ·  768K"
        }
    }

    var section: String {
        if audioConfiguration != nil { return "音频" }
        if remuxContainer != nil { return "封装" }
        return "视频"
    }

    var requiresVideo: Bool { videoCodec != nil || remuxContainer != nil || self == .animatedGIF }

    var pathExtension: String {
        switch self {
        case .h264MP4, .hevcMP4: "mp4"
        case .h264MOV, .hevcMOV, .proRes422Proxy, .proRes422LT,
             .proRes422, .proRes422HQ, .proRes4444, .motionJPEG: "mov"
        case .h264M4V: "m4v"
        case .animatedGIF: "gif"
        case .matroska: "mkv"
        case .mpegTS: "ts"
        case .avi: "avi"
        case .flv: "flv"
        case .webM: "webm"
        case .asf: "wmv"
        case .mpegPS: "mpg"
        case .vob: "vob"
        case .nut: "nut"
        case .mxf: "mxf"
        case .ogv: "ogv"
        case .realMedia: "rm"
        case .m4a, .alac: "m4a"
        case .aac: "aac"
        case .latmAAC: "latm"
        case .mp3: "mp3"
        case .flac: "flac"
        case .oggVorbis, .oggOpus: "ogg"
        case .wav16, .wav24, .wav32, .wavFloat, .wavFloat64: "wav"
        case .aiff: "aiff"
        case .cafALAC, .cafPCM24: "caf"
        case .auPCM16, .auMuLaw, .auALaw: "au"
        case .w64PCM24: "w64"
        case .vocPCM16: "voc"
        case .wavPack: "wv"
        case .tta: "tta"
        case .ac3: "ac3"
        case .eac3: "eac3"
        case .mp2: "mp2"
        case .g722: "g722"
        case .g726: "g726"
        case .aptX: "aptx"
        case .aptXHD: "aptxhd"
        case .iLBC: "lbc"
        case .trueHD: "thd"
        case .mlp: "mlp"
        case .dts: "dts"
        }
    }

    fileprivate var videoCodec: AVVideoCodecType? {
        switch self {
        case .h264MP4, .h264MOV, .h264M4V: .h264
        case .hevcMP4, .hevcMOV: .hevc
        case .proRes422Proxy: .proRes422Proxy
        case .proRes422LT: .proRes422LT
        case .proRes422: .proRes422
        case .proRes422HQ: .proRes422HQ
        case .proRes4444: .proRes4444
        case .motionJPEG: .jpeg
        default: nil
        }
    }

    fileprivate var videoFileType: AVFileType? {
        switch self {
        case .h264MP4, .hevcMP4: .mp4
        case .h264M4V: .m4v
        case .h264MOV, .hevcMOV, .proRes422Proxy, .proRes422LT,
             .proRes422, .proRes422HQ, .proRes4444, .motionJPEG: .mov
        default: nil
        }
    }

    fileprivate var remuxContainer: String? {
        switch self {
        case .matroska: "matroska"
        case .mpegTS: "mpegts"
        case .avi: "avi"
        case .flv: "flv"
        case .webM: "webm"
        case .asf: "asf"
        case .mpegPS: "mpeg"
        case .vob: "vob"
        case .nut: "nut"
        case .mxf: "mxf"
        case .ogv: "ogg"
        case .realMedia: "rm"
        default: nil
        }
    }

    fileprivate var audioConfiguration: FFmpegAudioConfiguration? {
        switch self {
        case .m4a: .init(
            muxer: "ipod", encoders: ["aac"], bitRate: 256_000,
            sampleRate: 48_000, channelCount: 2
        )
        case .aac: .init(
            muxer: "adts", encoders: ["aac"], bitRate: 256_000,
            sampleRate: 48_000, channelCount: 2
        )
        case .latmAAC: .init(
            muxer: "latm", encoders: ["aac"], bitRate: 256_000,
            sampleRate: 48_000, channelCount: 2
        )
        case .mp3: .init(
            muxer: "mp3", encoders: ["libmp3lame", "mp3"], bitRate: 320_000,
            sampleRate: 48_000, channelCount: 2
        )
        case .flac: .init(muxer: "flac", encoders: ["flac"], bitRate: 0)
        case .oggVorbis: .init(
            muxer: "ogg", encoders: ["libvorbis", "vorbis"], bitRate: 256_000,
            sampleRate: 48_000, channelCount: 2
        )
        case .oggOpus: .init(
            muxer: "ogg", encoders: ["libopus", "opus"], bitRate: 192_000,
            sampleRate: 48_000, channelCount: 2
        )
        case .alac: .init(muxer: "ipod", encoders: ["alac"], bitRate: 0)
        case .wav16: .init(muxer: "wav", encoders: ["pcm_s16le"], bitRate: 0)
        case .wav24: .init(muxer: "wav", encoders: ["pcm_s24le"], bitRate: 0)
        case .wav32: .init(muxer: "wav", encoders: ["pcm_s32le"], bitRate: 0)
        case .wavFloat: .init(muxer: "wav", encoders: ["pcm_f32le"], bitRate: 0)
        case .wavFloat64: .init(muxer: "wav", encoders: ["pcm_f64le"], bitRate: 0)
        case .aiff: .init(muxer: "aiff", encoders: ["pcm_s16be"], bitRate: 0)
        case .cafALAC: .init(muxer: "caf", encoders: ["alac"], bitRate: 0)
        case .cafPCM24: .init(muxer: "caf", encoders: ["pcm_s24le"], bitRate: 0)
        case .auPCM16: .init(muxer: "au", encoders: ["pcm_s16be"], bitRate: 0)
        case .auMuLaw: .init(muxer: "au", encoders: ["pcm_mulaw"], bitRate: 64_000)
        case .auALaw: .init(muxer: "au", encoders: ["pcm_alaw"], bitRate: 64_000)
        case .w64PCM24: .init(muxer: "w64", encoders: ["pcm_s24le"], bitRate: 0)
        case .vocPCM16: .init(muxer: "voc", encoders: ["pcm_s16le"], bitRate: 0)
        case .wavPack: .init(muxer: "wv", encoders: ["wavpack"], bitRate: 0)
        case .tta: .init(muxer: "tta", encoders: ["tta"], bitRate: 0)
        case .ac3: .init(muxer: "ac3", encoders: ["ac3", "ac3_fixed"], bitRate: 640_000)
        case .eac3: .init(muxer: "eac3", encoders: ["eac3"], bitRate: 640_000)
        case .mp2: .init(muxer: "mp2", encoders: ["mp2", "mp2fixed"], bitRate: 320_000)
        case .g722: .init(
            muxer: "g722", encoders: ["adpcm_g722"], bitRate: 64_000,
            sampleRate: 16_000, channelCount: 1
        )
        case .g726: .init(
            muxer: "g726", encoders: ["adpcm_g726"], bitRate: 32_000,
            sampleRate: 8_000, channelCount: 1
        )
        case .aptX: .init(
            muxer: "aptx", encoders: ["aptx"], bitRate: 352_800,
            sampleRate: 48_000, channelCount: 2
        )
        case .aptXHD: .init(
            muxer: "aptx_hd", encoders: ["aptx_hd"], bitRate: 576_000,
            sampleRate: 48_000, channelCount: 2
        )
        case .iLBC: .init(muxer: "ilbc", encoders: [], bitRate: 15_200)
        case .trueHD: .init(
            muxer: "truehd", encoders: ["truehd"], bitRate: 0,
            sampleRate: 48_000, channelCount: 2
        )
        case .mlp: .init(
            muxer: "mlp", encoders: ["mlp"], bitRate: 0,
            sampleRate: 48_000, channelCount: 2
        )
        case .dts: .init(
            muxer: "dts", encoders: ["dca"], bitRate: 768_000,
            sampleRate: 48_000, channelCount: 2
        )
        default: nil
        }
    }
}

private struct FFmpegAudioConfiguration {
    let muxer: String
    let encoders: [String]
    let bitRate: Int
    var sampleRate: Int = 0
    var channelCount: Int = 0
}

struct MediaProbe: Sendable {
    let hasVideo: Bool
    let hasAudio: Bool
    let duration: TimeInterval
    let videoCodec: String?
    let audioCodec: String?
    let container: String

    static func inspect(_ url: URL) async throws -> MediaProbe {
        let info = try await FFmpegMediaInspector().inspect(url: url)
        return MediaProbe(
            hasVideo: info.hasVideo,
            hasAudio: info.hasAudio,
            duration: info.duration,
            videoCodec: info.videoCodec,
            audioCodec: info.audioCodec,
            container: info.container
        )
    }
}

@MainActor
final class MediaTranscoder: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0

    private let audioTranscoder = FFmpegAudioTranscoder()
    private let videoProcessor = VideoProcessor()
    private let catalog = CodecCapabilities.runtimeCatalog()

    func availableTargets(for probe: MediaProbe) -> [MediaTranscodeTarget] {
        MediaTranscodeTarget.allCases.filter { target in
            if target.requiresVideo, !probe.hasVideo { return false }
            if target.audioConfiguration != nil, !probe.hasAudio { return false }
            if let configuration = target.audioConfiguration {
                return configuration.encoders.contains(where: catalog.encoders.contains)
                    && catalog.muxers.contains(configuration.muxer)
            }
            if let container = target.remuxContainer {
                return catalog.muxers.contains(container)
            }
            return true
        }
    }

    func transcode(inputURL: URL, target: MediaTranscodeTarget) async throws -> URL {
        isRunning = true
        progress = 0
        defer { isRunning = false }

        try SharedStorage.prepare()
        let output = SharedStorage.transcodeDirectory
            .appendingPathComponent("MonoFrame-\(UUID().uuidString).\(target.pathExtension)")
        try? FileManager.default.removeItem(at: output)

        if let configuration = target.audioConfiguration {
            guard let encoder = configuration.encoders.first(where: catalog.encoders.contains) else {
                throw TranscodeError.encoderUnavailable
            }
            let result = try await audioTranscoder.transcode(
                inputURL: inputURL,
                outputURL: output,
                muxerName: configuration.muxer,
                encoderName: encoder,
                bitRate: configuration.bitRate,
                sampleRate: configuration.sampleRate,
                channelCount: configuration.channelCount
            ) { [weak self] value in
                Task { @MainActor [weak self] in self?.progress = value }
            }
            try await validateAudioOutput(result)
            progress = 1
            return result
        }

        if target == .animatedGIF {
            let result = try await transcodeAnimatedGIF(inputURL: inputURL, output: output)
            progress = 1
            return result
        }

        if let container = target.remuxContainer {
            let result = try await videoProcessor.remux(
                inputURL: inputURL,
                outputURL: output,
                containerName: container
            ) { [weak self] value in
                Task { @MainActor [weak self] in self?.progress = value }
            }
            progress = 1
            return result
        }

        let result = try await transcodeVideo(inputURL: inputURL, output: output, target: target)
        progress = 1
        return result
    }

    private func validateAudioOutput(_ url: URL) async throws {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) > 0 else { throw TranscodeError.invalidOutput }
            let info = try await FFmpegMediaInspector().inspect(url: url)
            guard info.hasAudio else { throw TranscodeError.invalidOutput }
        } catch {
            try? FileManager.default.removeItem(at: url)
            if let transcodeError = error as? TranscodeError { throw transcodeError }
            throw TranscodeError.invalidOutput
        }
    }

    private func transcodeAnimatedGIF(inputURL: URL, output: URL) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw TranscodeError.missingVideo
        }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw TranscodeError.readFailed }

        let nominalRate = Double(try await videoTrack.load(.nominalFrameRate))
        let requestedRate = min(15, max(1, nominalRate.isFinite ? nominalRate : 12))
        let frameCount = min(900, max(1, Int((duration * requestedRate).rounded())))
        let frameDelay = max(0.02, duration / Double(frameCount))
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else { throw TranscodeError.cannotConfigure }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ] as CFDictionary)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        let tolerance = CMTime(seconds: frameDelay / 2, preferredTimescale: 60_000)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay,
                kCGImagePropertyGIFUnclampedDelayTime: frameDelay
            ]
        ] as CFDictionary

        for index in 0..<frameCount {
            let seconds = min(duration - 0.001, Double(index) * duration / Double(frameCount))
            let result = try await generator.image(
                at: CMTime(seconds: max(0, seconds), preferredTimescale: 60_000)
            )
            CGImageDestinationAddImage(destination, result.image, frameProperties)
            progress = min(0.99, Double(index + 1) / Double(frameCount))
        }

        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw TranscodeError.writeFailed
        }
        return output
    }


    /// Reuse the existing AVAssetReader/Writer encoder; verify bytes after every bounded attempt.
    func compress(inputURL: URL, maximumBytes: Int64, hevc: Bool = false) async throws -> URL {
        isRunning = true; progress = 0
        defer { isRunning = false }
        let existingBytes = try inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if existingBytes > 0 && Int64(existingBytes) <= maximumBytes { progress = 1; return inputURL }
        let asset = AVURLAsset(url: inputURL)
        let seconds = try await asset.load(.duration).seconds
        guard seconds.isFinite, seconds > 0, maximumBytes > 0 else { throw EditingDeskError.invalidRange }
        let hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
        let audioRate = hasAudio ? 128_000 : 0
        var videoRate = Int(Double(maximumBytes) * 8 * 0.92 / seconds) - audioRate
        guard videoRate >= 100_000 else { throw EditingDeskError.sizeTooSmall }
        try SharedStorage.prepare()
        for _ in 0..<3 {
            try Task.checkCancellation()
            let output = SharedStorage.exportDirectory.appendingPathComponent("Compressed-\(UUID()).mp4")
            do {
                _ = try await transcodeVideo(inputURL: inputURL, output: output,
                    target: hevc ? .hevcMP4 : .h264MP4, videoBitRate: videoRate, audioBitRate: 128_000)
                let bytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                if bytes > 0 && Int64(bytes) <= maximumBytes { return output }
                try FileManager.default.removeItem(at: output)
                guard bytes > 0 else { throw TranscodeError.writeFailed }
                videoRate = Int(Double(videoRate) * Double(maximumBytes) / Double(bytes) * 0.85)
                guard videoRate >= 100_000 else { throw EditingDeskError.sizeTooSmall }
            } catch {
                try? FileManager.default.removeItem(at: output)
                throw error
            }
        }
        throw EditingDeskError.sizeExceeded
    }

    private func transcodeVideo(
        inputURL: URL,
        output: URL,
        target: MediaTranscodeTarget,
        videoBitRate: Int? = nil, audioBitRate: Int = 256_000
    ) async throws -> URL {
        guard let codec = target.videoCodec, let fileType = target.videoFileType else {
            throw TranscodeError.cannotConfigure
        }
        let asset = AVURLAsset(url: inputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let videoTrack = videoTracks.first else { throw TranscodeError.missingVideo }

        let duration = try await asset.load(.duration).seconds
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: fileType)
        let size = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let estimatedRate = try await videoTrack.load(.estimatedDataRate)
        let prefersBGRA = [
            .proRes422Proxy, .proRes422LT, .proRes422,
            .proRes422HQ, .proRes4444, .motionJPEG
        ].contains(target)
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: prefersBGRA
                    ? kCVPixelFormatType_32BGRA
                    : kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
        )

        var videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: max(2, Int(abs(size.width)).roundedToEven),
            AVVideoHeightKey: max(2, Int(abs(size.height)).roundedToEven)
        ]
        if codec == .h264 || codec == .hevc {
            videoSettings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: videoBitRate ?? max(8_000_000, Int(estimatedRate)),
                AVVideoAllowFrameReorderingKey: true
            ]
        } else if codec == .jpeg {
            videoSettings[AVVideoCompressionPropertiesKey] = [AVVideoQualityKey: 0.92]
        }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.transform = transform
        guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else {
            throw TranscodeError.cannotConfigure
        }
        reader.add(videoOutput)
        writer.add(videoInput)

        var pipelines: [(AVAssetReaderOutput, AVAssetWriterInput, Bool)] = [
            (videoOutput, videoInput, true)
        ]
        if let audioTrack = audioTracks.first {
            let audioOutput = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
            let audioInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: audioBitRate
                ]
            )
            guard reader.canAdd(audioOutput), writer.canAdd(audioInput) else {
                throw TranscodeError.cannotConfigure
            }
            reader.add(audioOutput)
            writer.add(audioInput)
            pipelines.append((audioOutput, audioInput, false))
        }

        guard writer.startWriting(), reader.startReading() else {
            throw writer.error ?? reader.error ?? TranscodeError.cannotStart
        }
        writer.startSession(atSourceTime: .zero)

        var tasks: [Task<Void, Error>] = []
        for (index, pipeline) in pipelines.enumerated() {
            let output = pipeline.0
            let input = pipeline.1
            let reportsProgress = pipeline.2
            let queue = DispatchQueue(label: "app.mono.transcode.\(index)")
            let handler: (@Sendable (TimeInterval) -> Void)?
            if reportsProgress {
                handler = { [weak self] timestamp in
                    guard duration > 0 else { return }
                    Task { @MainActor [weak self] in
                        self?.progress = min(0.99, max(0, timestamp / duration))
                    }
                }
            } else {
                handler = nil
            }
            let task = Task<Void, Error> {
                try await Self.pump(output: output, input: input, queue: queue, progress: handler)
            }
            tasks.append(task)
        }
        for task in tasks { try await task.value }

        guard reader.status == .completed else {
            writer.cancelWriting()
            throw reader.error ?? TranscodeError.readFailed
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? TranscodeError.writeFailed }
        return output
    }

    nonisolated private static func pump(
        output: AVAssetReaderOutput,
        input: AVAssetWriterInput,
        queue: DispatchQueue,
        progress: (@Sendable (TimeInterval) -> Void)?
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            var completed = false
            input.requestMediaDataWhenReady(on: queue) {
                guard !completed else { return }
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer() else {
                        completed = true
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    guard input.append(sample) else {
                        completed = true
                        continuation.resume(throwing: TranscodeError.writeFailed)
                        return
                    }
                    let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    if timestamp.isFinite { progress?(timestamp) }
                }
            }
        }
    }
}

private enum TranscodeError: LocalizedError {
    case missingVideo
    case cannotConfigure
    case cannotStart
    case readFailed
    case writeFailed
    case encoderUnavailable
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .missingVideo: "输入文件没有视频轨"
        case .cannotConfigure: "当前设备不支持该转码组合"
        case .cannotStart: "无法开始转码"
        case .readFailed: "媒体读取失败"
        case .writeFailed: "媒体编码失败"
        case .encoderUnavailable: "当前版本未包含所需编码器"
        case .invalidOutput: "输出文件无有效音轨"
        }
    }
}

private extension Int {
    var roundedToEven: Int { isMultiple(of: 2) ? self : self + 1 }
}
