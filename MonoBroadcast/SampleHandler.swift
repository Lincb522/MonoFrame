import AVFoundation
import CoreGraphics
import ImageIO
import ReplayKit
import VideoToolbox

final class SampleHandler: RPBroadcastSampleHandler {
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var videoAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var pixelTransferSession: VTPixelTransferSession?
    private var usesDirectVideoSamples = false
    private var appAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var finalOutputURL: URL?
    private var firstVideoPTS: CMTime?
    private var sessionStartPTS: CMTime?
    private var lastPresentationTime: CMTime?
    private var nextVideoPTS: CMTime?
    private var configuredFrameRate = 60
    private var sessionStarted = false
    private var lastHeartbeatTime: TimeInterval = 0
    private let openingSkipDuration = CMTime(seconds: 1.5, preferredTimescale: 600)
    private let queue = DispatchQueue(label: "app.mono.broadcast.writer")

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        do {
            guard let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.com.linchengbo.mono.screenaudio"
            ) else { throw NSError(domain: "MonoBroadcast", code: 1) }
            let directory = container.appendingPathComponent("Recordings", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let identifier = UUID().uuidString
            let output = directory.appendingPathComponent(".MonoFrame-\(identifier).partial.mp4")
            let finalOutput = directory.appendingPathComponent("ScreenReady-\(Self.timestamp())-\(identifier).mp4")
            outputURL = output
            finalOutputURL = finalOutput
            firstVideoPTS = nil
            sessionStartPTS = nil
            lastPresentationTime = nil
            nextVideoPTS = nil
            sessionStarted = false
            lastHeartbeatTime = 0
            writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
            clearLastRecordingError()
            updateSharedRecordingState(isActive: true)
        } catch {
            storeRecordingError(error, stage: "broadcastStarted")
            updateSharedRecordingState(isActive: false)
            finishBroadcastWithError(error)
        }
    }

    override func broadcastPaused() {}
    override func broadcastResumed() {}

    override func broadcastFinished() {
        updateSharedRecordingState(isActive: false, completed: true)
        let state = queue.sync {
            let state = (writer, outputURL, finalOutputURL, sessionStarted)
            guard sessionStarted else { return state }
            if let lastPresentationTime {
                writer?.endSession(atSourceTime: lastPresentationTime)
            }
            videoInput?.markAsFinished()
            appAudioInput?.markAsFinished()
            microphoneInput?.markAsFinished()
            return state
        }
        guard let writerToFinish = state.0 else { return }
        guard state.3 else {
            writerToFinish.cancelWriting()
            if let outputURL = state.1 { try? FileManager.default.removeItem(at: outputURL) }
            return
        }
        let semaphore = DispatchSemaphore(value: 0)
        writerToFinish.finishWriting {
            semaphore.signal()
        }
        let result = semaphore.wait(timeout: .now() + 20)
        guard result == .success, writerToFinish.status == .completed,
              let temporaryURL = state.1, let finalURL = state.2 else {
            writerToFinish.cancelWriting()
            if let outputURL = state.1 { try? FileManager.default.removeItem(at: outputURL) }
            return
        }
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        queue.async { [weak self] in
            guard let self, CMSampleBufferDataIsReady(sampleBuffer) else { return }
            do {
                self.updateHeartbeatIfNeeded()
                if self.videoInput == nil, sampleBufferType == .video {
                    try self.configureWriter(with: sampleBuffer)
                }
                if !self.sessionStarted {
                    switch sampleBufferType {
                    case .audioApp where self.appAudioInput == nil:
                        try self.configureAudioInput(with: sampleBuffer, isMicrophone: false)
                    case .audioMic where self.microphoneInput == nil:
                        try self.configureAudioInput(with: sampleBuffer, isMicrophone: true)
                    default:
                        break
                    }
                }
                guard let writer = self.writer else { return }

                if !self.sessionStarted {
                    guard sampleBufferType == .video else { return }
                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    if self.firstVideoPTS == nil {
                        self.firstVideoPTS = presentationTime
                        return
                    }
                    guard let firstVideoPTS = self.firstVideoPTS,
                          CMTimeCompare(
                            CMTimeSubtract(presentationTime, firstVideoPTS),
                            self.openingSkipDuration
                          ) >= 0 else { return }
                    guard writer.startWriting() else {
                        throw writer.error ?? NSError(domain: "MonoBroadcast", code: 4)
                    }
                    writer.startSession(atSourceTime: presentationTime)
                    self.sessionStartPTS = presentationTime
                    self.sessionStarted = true
                }
                guard writer.status == .writing else { return }
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                if let sessionStartPTS = self.sessionStartPTS,
                   CMTimeCompare(presentationTime, sessionStartPTS) < 0 { return }
                switch sampleBufferType {
                case .video:
                    guard self.shouldAppendVideo(at: presentationTime) else { return }
                    if self.videoInput?.isReadyForMoreMediaData == true {
                        try self.appendVideo(sampleBuffer, at: presentationTime)
                        self.lastPresentationTime = presentationTime
                    }
                case .audioApp:
                    if try self.appendAudio(sampleBuffer, to: self.appAudioInput) {
                        self.lastPresentationTime = presentationTime
                    }
                case .audioMic:
                    if try self.appendAudio(sampleBuffer, to: self.microphoneInput) {
                        self.lastPresentationTime = presentationTime
                    }
                @unknown default:
                    break
                }
            } catch {
                self.storeRecordingError(error, stage: "processSampleBuffer")
                self.updateSharedRecordingState(isActive: false)
                self.finishBroadcastWithError(error)
            }
        }
    }

    private func configureWriter(with sampleBuffer: CMSampleBuffer) throws {
        guard let writer,
              let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw NSError(domain: "MonoBroadcast", code: 2)
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        let preferences = UserDefaults(suiteName: "group.com.linchengbo.mono.screenaudio")
        let codec: AVVideoCodecType = preferences?.string(forKey: "screenCodec") == "h264" ? .h264 : .hevc
        let resolution = ScreenResolutionPreset(
            rawValue: preferences?.string(forKey: ScreenRecordingPreferenceKey.resolution) ?? ""
        ) ?? .native
        let storedFrameRate = preferences?.integer(forKey: ScreenRecordingPreferenceKey.frameRate) ?? 60
        let orientationMode = ScreenOrientationPreset(
            rawValue: preferences?.string(forKey: ScreenRecordingPreferenceKey.orientation) ?? ""
        ) ?? .automatic
        let bitratePreset = ScreenBitratePreset(
            rawValue: preferences?.string(forKey: ScreenRecordingPreferenceKey.bitratePreset) ?? ""
        ) ?? .highest
        let outputDimensions = resolution.dimensions(
            sourceWidth: Int(dimensions.width),
            sourceHeight: Int(dimensions.height)
        )
        configuredFrameRate = ScreenFrameRateLimit.clamp(storedFrameRate == 0 ? 60 : storedFrameRate)
        nextVideoPTS = nil
        let bitrate = bitratePreset.bitsPerSecond(
            width: outputDimensions.width,
            height: outputDimensions.height,
            frameRate: configuredFrameRate,
            isHEVC: codec == .hevc
        )
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: configuredFrameRate,
            AVVideoMaxKeyFrameIntervalKey: configuredFrameRate * 2,
            AVVideoAllowFrameReorderingKey: true
        ]
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            compression[AVVideoH264EntropyModeKey] = AVVideoH264EntropyModeCABAC
        } else {
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel
        }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: outputDimensions.width,
            AVVideoHeightKey: outputDimensions.height,
            AVVideoCompressionPropertiesKey: compression
        ]
        guard writer.canApply(
            outputSettings: videoSettings,
            forMediaType: .video
        ) else {
            throw NSError(
                domain: "MonoBroadcast",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "The selected video settings are not supported."]
            )
        }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        video.expectsMediaDataInRealTime = true
        let detectedOrientation = Self.sampleOrientation(from: sampleBuffer)
        let outputOrientation = Self.outputOrientation(
            mode: orientationMode,
            detected: detectedOrientation,
            width: outputDimensions.width,
            height: outputDimensions.height
        )
        video.transform = Self.transform(
            for: outputOrientation,
            width: outputDimensions.width,
            height: outputDimensions.height
        )
        guard writer.canAdd(video) else { throw NSError(domain: "MonoBroadcast", code: 3) }
        writer.add(video)
        videoInput = video

        let sourcePixelFormat = CVPixelBufferGetPixelFormatType(sourceBuffer)
        usesDirectVideoSamples = Int(dimensions.width) == outputDimensions.width
            && Int(dimensions.height) == outputDimensions.height
        if usesDirectVideoSamples {
            videoAdaptor = nil
            pixelTransferSession = nil
            return
        }

        let outputPixelFormat = Self.writerPixelFormat(for: sourcePixelFormat)
        videoAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: video,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: outputPixelFormat,
                kCVPixelBufferWidthKey as String: outputDimensions.width,
                kCVPixelBufferHeightKey as String: outputDimensions.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        var transferSession: VTPixelTransferSession?
        guard VTPixelTransferSessionCreate(
            allocator: kCFAllocatorDefault,
            pixelTransferSessionOut: &transferSession
        ) == noErr, let transferSession else {
            throw NSError(domain: "MonoBroadcast", code: 5)
        }
        VTSessionSetProperty(
            transferSession,
            key: kVTPixelTransferPropertyKey_ScalingMode,
            value: kVTScalingMode_Normal
        )
        pixelTransferSession = transferSession

    }

    private func configureAudioInput(
        with sampleBuffer: CMSampleBuffer,
        isMicrophone: Bool
    ) throws {
        guard let writer, writer.status == .unknown,
              let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
            return
        }
        let source = streamDescription.pointee
        let sampleRate = source.mSampleRate.isFinite && source.mSampleRate > 0
            ? source.mSampleRate
            : 48_000
        let channels = max(1, min(2, Int(source.mChannelsPerFrame)))
        let audio = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: channels == 1 ? 128_000 : 192_000
            ]
        )
        audio.expectsMediaDataInRealTime = true
        guard writer.canAdd(audio) else { return }
        writer.add(audio)
        if isMicrophone { microphoneInput = audio }
        else { appAudioInput = audio }
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer, at presentationTime: CMTime) throws {
        if usesDirectVideoSamples {
            guard videoInput?.append(sampleBuffer) == true else {
                throw writer?.error ?? NSError(domain: "MonoBroadcast", code: 9)
            }
            return
        }

        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer),
              let videoAdaptor,
              let pool = videoAdaptor.pixelBufferPool,
              let pixelTransferSession else {
            throw NSError(domain: "MonoBroadcast", code: 6)
        }
        var destination: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            pool,
            &destination
        ) == kCVReturnSuccess, let destination else {
            throw NSError(domain: "MonoBroadcast", code: 7)
        }
        guard VTPixelTransferSessionTransferImage(
            pixelTransferSession,
            from: source,
            to: destination
        ) == noErr else {
            throw NSError(domain: "MonoBroadcast", code: 8)
        }
        CVBufferPropagateAttachments(source, destination)
        guard videoAdaptor.append(destination, withPresentationTime: presentationTime) else {
            throw writer?.error ?? NSError(domain: "MonoBroadcast", code: 9)
        }
    }

    private func appendAudio(
        _ sampleBuffer: CMSampleBuffer,
        to input: AVAssetWriterInput?
    ) throws -> Bool {
        guard let input, input.isReadyForMoreMediaData else { return false }
        guard input.append(sampleBuffer) else {
            if let error = writer?.error { throw error }
            throw NSError(domain: "MonoBroadcast", code: 11)
        }
        return true
    }

    private static func writerPixelFormat(for sourcePixelFormat: OSType) -> OSType {
        switch sourcePixelFormat {
        case kCVPixelFormatType_32BGRA,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            sourcePixelFormat
        default:
            kCVPixelFormatType_32BGRA
        }
    }

    private func shouldAppendVideo(at presentationTime: CMTime) -> Bool {
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(15, configuredFrameRate)))
        guard let nextVideoPTS else {
            self.nextVideoPTS = CMTimeAdd(presentationTime, frameDuration)
            return true
        }
        guard CMTimeCompare(presentationTime, nextVideoPTS) >= 0 else { return false }

        let lag = max(0, CMTimeGetSeconds(CMTimeSubtract(presentationTime, nextVideoPTS)))
        let duration = CMTimeGetSeconds(frameDuration)
        let steps = max(1, Int(floor(lag / duration)) + 1)
        self.nextVideoPTS = CMTimeAdd(
            nextVideoPTS,
            CMTimeMultiply(frameDuration, multiplier: Int32(min(steps, Int(Int32.max))))
        )
        return true
    }

    private static func sampleOrientation(from sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        guard let value = CMGetAttachment(
            sampleBuffer,
            key: RPVideoSampleOrientationKey as CFString,
            attachmentModeOut: nil
        ) as? NSNumber else { return .up }
        return CGImagePropertyOrientation(rawValue: value.uint32Value) ?? .up
    }

    private static func outputOrientation(
        mode: ScreenOrientationPreset,
        detected: CGImagePropertyOrientation,
        width: Int,
        height: Int
    ) -> CGImagePropertyOrientation {
        switch mode {
        case .automatic:
            detected
        case .portrait:
            width >= height ? .right : .up
        case .landscape:
            width >= height ? .up : .right
        }
    }

    private static func transform(
        for orientation: CGImagePropertyOrientation,
        width: Int,
        height: Int
    ) -> CGAffineTransform {
        switch orientation {
        case .up, .upMirrored:
            .identity
        case .down, .downMirrored:
            CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: CGFloat(width), ty: CGFloat(height))
        case .left, .leftMirrored:
            CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: CGFloat(width))
        case .right, .rightMirrored:
            CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0)
        @unknown default:
            .identity
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func updateHeartbeatIfNeeded() {
        let now = Date().timeIntervalSince1970
        guard now - lastHeartbeatTime >= 1 else { return }
        lastHeartbeatTime = now
        let defaults = UserDefaults(suiteName: "group.com.linchengbo.mono.screenaudio")
        defaults?.set(now, forKey: ScreenRecordingPreferenceKey.heartbeatAt)
    }

    private func updateSharedRecordingState(isActive: Bool, completed: Bool = false) {
        let now = Date().timeIntervalSince1970
        let defaults = UserDefaults(suiteName: "group.com.linchengbo.mono.screenaudio")
        defaults?.set(isActive, forKey: ScreenRecordingPreferenceKey.isActive)
        defaults?.set(now, forKey: ScreenRecordingPreferenceKey.heartbeatAt)
        if isActive {
            defaults?.set(now, forKey: ScreenRecordingPreferenceKey.startedAt)
        } else if completed {
            defaults?.set(now, forKey: ScreenRecordingPreferenceKey.lastCompletedAt)
        }
    }

    private func clearLastRecordingError() {
        let defaults = UserDefaults(suiteName: "group.com.linchengbo.mono.screenaudio")
        defaults?.removeObject(forKey: ScreenRecordingPreferenceKey.lastError)
        defaults?.removeObject(forKey: ScreenRecordingPreferenceKey.lastErrorAt)
    }

    private func storeRecordingError(_ error: Error, stage: String) {
        let nsError = error as NSError
        let writerError = writer?.error as NSError?
        let details = [
            "stage=\(stage)",
            "error=\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)",
            writerError.map { "writer=\($0.domain)(\($0.code)): \($0.localizedDescription)" }
        ].compactMap { $0 }.joined(separator: " | ")
        let defaults = UserDefaults(suiteName: "group.com.linchengbo.mono.screenaudio")
        defaults?.set(details, forKey: ScreenRecordingPreferenceKey.lastError)
        defaults?.set(Date().timeIntervalSince1970, forKey: ScreenRecordingPreferenceKey.lastErrorAt)
    }
}
