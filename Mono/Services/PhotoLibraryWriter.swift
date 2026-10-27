@preconcurrency import AVFoundation
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

enum PhotoVideoSaveResult: Equatable {
    case complete
}

enum PhotoLibraryWriter {
    private struct PreparedVideo {
        let directory: URL
        let url: URL

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    static func saveVideo(_ sourceURL: URL) async throws -> PhotoVideoSaveResult {
        try await requirePhotoPermission()
        try await validateVideo(sourceURL)

        do {
            try await addVideoResource(sourceURL)
            return .complete
        } catch {
            guard isInvalidResource(error) else { throw mapped(error) }
        }

        // Normalize the resource while preserving its audio. Never silently
        // replace a requested video export with an audio-less file.
        do {
            try await encodeAndSave(sourceURL, includeAudio: true)
            return .complete
        } catch {
            throw mapped(error)
        }
    }

    static func saveLivePhoto(
        photoURL: URL,
        pairedVideoURL: URL,
        identifier: String
    ) async throws {
        try await requirePhotoPermission()
        try validatePhoto(photoURL, identifier: identifier)
        try await validatePairedVideo(pairedVideoURL, identifier: identifier)

        let photoOptions = PHAssetResourceCreationOptions()
        photoOptions.shouldMoveFile = false
        photoOptions.originalFilename = photoURL.lastPathComponent
        photoOptions.uniformTypeIdentifier = UTType.jpeg.identifier

        let videoOptions = PHAssetResourceCreationOptions()
        videoOptions.shouldMoveFile = false
        videoOptions.originalFilename = pairedVideoURL.lastPathComponent
        videoOptions.uniformTypeIdentifier = UTType.quickTimeMovie.identifier

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: photoURL, options: photoOptions)
                request.addResource(with: .pairedVideo, fileURL: pairedVideoURL, options: videoOptions)
            }
        } catch {
            throw mapped(error)
        }
    }

    private static func requirePhotoPermission() async throws {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let status = current == .notDetermined
            ? await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            : current
        if status == .limited { throw ExportError.photoLimitedAccess }
        guard status == .authorized else {
            throw ExportError.photoPermission
        }
    }

    private static func encodeAndSave(_ sourceURL: URL, includeAudio: Bool) async throws {
        let prepared = try await prepareCompatibleVideo(sourceURL, includeAudio: includeAudio)
        defer { prepared.remove() }
        try await saveCompatibleVideo(prepared.url)
    }

    private static func saveCompatibleVideo(_ url: URL) async throws {
        do {
            try await addVideoResource(url)
        } catch {
            guard isInvalidResource(error) else { throw mapped(error) }
            do {
                try await UIKitVideoAlbumSaver.save(url)
            } catch {
                throw mapped(error)
            }
        }
    }

    private static func prepareCompatibleVideo(
        _ sourceURL: URL,
        includeAudio: Bool
    ) async throws -> PreparedVideo {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MonoFrame-Photos-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent("MonoFrame-\(UUID().uuidString).mp4")

        do {
            let asset = AVURLAsset(url: sourceURL)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard let videoTrack = videoTracks.first else {
                throw ExportError.invalidPhotoResource
            }

            let reader = try AVAssetReader(asset: asset)
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            let size = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)
            let dataRate = try await videoTrack.load(.estimatedDataRate)
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            let width = Self.evenDimension(abs(size.width))
            let height = Self.evenDimension(abs(size.height))
            let bitrate = min(40_000_000, max(6_000_000, Int(dataRate.rounded())))

            let videoOutput = AVAssetReaderTrackOutput(
                track: videoTrack,
                outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                ]
            )
            let videoInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: width,
                    AVVideoHeightKey: height,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: bitrate,
                        AVVideoExpectedSourceFrameRateKey: max(15, Int(nominalFrameRate.rounded())),
                        AVVideoMaxKeyFrameIntervalKey: max(30, Int(nominalFrameRate.rounded()) * 2),
                        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                        AVVideoAllowFrameReorderingKey: true
                    ]
                ]
            )
            videoInput.transform = transform
            guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else {
                throw ExportError.invalidPhotoResource
            }
            reader.add(videoOutput)
            writer.add(videoInput)

            var pipelines: [(AVAssetReaderOutput, AVAssetWriterInput)] = [(videoOutput, videoInput)]
            if includeAudio,
               let audioTrack = try audioTracks.first(where: { try hasReadableSample($0, asset: asset) }) {
                let audioOutput = AVAssetReaderAudioMixOutput(
                    audioTracks: [audioTrack],
                    audioSettings: [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: 48_000,
                        AVNumberOfChannelsKey: 2,
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
                        AVEncoderBitRateKey: 192_000
                    ]
                )
                if reader.canAdd(audioOutput), writer.canAdd(audioInput) {
                    reader.add(audioOutput)
                    writer.add(audioInput)
                    pipelines.append((audioOutput, audioInput))
                }
            }

            guard writer.startWriting(), reader.startReading() else {
                throw writer.error ?? reader.error ?? ExportError.invalidPhotoResource
            }
            writer.startSession(atSourceTime: .zero)
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for (output, input) in pipelines {
                        group.addTask {
                            try await pump(output: output, input: input)
                        }
                    }
                    try await group.waitForAll()
                }
            } catch {
                reader.cancelReading()
                writer.cancelWriting()
                throw error
            }
            guard reader.status == .completed else {
                writer.cancelWriting()
                throw reader.error ?? ExportError.invalidPhotoResource
            }
            await writer.finishWriting()
            guard writer.status == .completed else {
                throw writer.error ?? ExportError.invalidPhotoResource
            }
            try await validateVideo(outputURL)
            return PreparedVideo(directory: directory, url: outputURL)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func validateVideo(_ url: URL) async throws {
        guard FileManager.default.isReadableFile(atPath: url.path),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0 else {
            throw ExportError.invalidPhotoResource
        }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard duration.seconds.isFinite, duration.seconds > 0, let track = tracks.first else {
            throw ExportError.invalidPhotoResource
        }

        let descriptions = try await track.load(.formatDescriptions)
        guard !descriptions.isEmpty else { throw ExportError.invalidPhotoResource }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { throw ExportError.invalidPhotoResource }
        reader.add(output)
        guard reader.startReading(), output.copyNextSampleBuffer() != nil else {
            throw reader.error ?? ExportError.invalidPhotoResource
        }
        reader.cancelReading()
    }

    private static func addVideoResource(_ url: URL) async throws {
        let options = PHAssetResourceCreationOptions()
        options.shouldMoveFile = false
        options.originalFilename = url.lastPathComponent
        options.uniformTypeIdentifier = url.pathExtension.lowercased() == "mp4"
            ? UTType.mpeg4Movie.identifier
            : UTType.quickTimeMovie.identifier

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .video, fileURL: url, options: options)
        }
    }

    private static func validatePhoto(_ url: URL, identifier: String) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let maker = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any],
              maker["17"] as? String == identifier else {
            throw ExportError.livePhotoFailed
        }
    }

    private static func validatePairedVideo(_ url: URL, identifier: String) async throws {
        try await validateVideo(url)
        let asset = AVURLAsset(url: url)
        let metadata = try await asset.loadMetadata(for: .quickTimeMetadata)
        var hasIdentifier = false
        for item in metadata where item.identifier == .quickTimeMetadataContentIdentifier {
            if try await item.load(.stringValue) == identifier {
                hasIdentifier = true
                break
            }
        }
        guard hasIdentifier else { throw ExportError.livePhotoFailed }

        guard let metadataTrack = try await asset.loadTracks(withMediaType: .metadata).first else {
            throw ExportError.livePhotoFailed
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: metadataTrack, outputSettings: nil)
        guard reader.canAdd(output) else { throw ExportError.livePhotoFailed }
        reader.add(output)
        let adaptor = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: output)
        guard reader.startReading(),
              let group = adaptor.nextTimedMetadataGroup(),
              group.items.contains(where: {
                  $0.identifier?.rawValue == "mdta/com.apple.quicktime.still-image-time"
              }) else {
            throw reader.error ?? ExportError.livePhotoFailed
        }
        reader.cancelReading()
    }

    private static func isInvalidResource(_ error: Error) -> Bool {
        let value = error as NSError
        return value.domain == PHPhotosErrorDomain && value.code == 3302
    }

    private static func hasReadableSample(_ track: AVAssetTrack, asset: AVAsset) throws -> Bool {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { return false }
        reader.add(output)
        guard reader.startReading() else { return false }
        let hasSample = output.copyNextSampleBuffer() != nil
        reader.cancelReading()
        return hasSample
    }

    private static func pump(
        output: AVAssetReaderOutput,
        input: AVAssetWriterInput
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "app.monoframe.photos.\(UUID().uuidString)")
            var finished = false
            input.requestMediaDataWhenReady(on: queue) {
                guard !finished else { return }
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer() else {
                        finished = true
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    guard input.append(sample) else {
                        finished = true
                        continuation.resume(throwing: ExportError.invalidPhotoResource)
                        return
                    }
                }
            }
        }
    }

    private static func evenDimension(_ value: CGFloat) -> Int {
        let rounded = max(2, Int(value.rounded()))
        return rounded.isMultiple(of: 2) ? rounded : rounded + 1
    }

    private static func mapped(_ error: Error) -> Error {
        let value = error as NSError
        guard value.domain == PHPhotosErrorDomain else { return error }
        switch value.code {
        case 3302:
            if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited {
                return ExportError.photoLimitedAccess
            }
            return ExportError.invalidPhotoResource
        case 3305:
            return ExportError.photoStorageFull
        case 3310, 3311:
            return ExportError.photoPermission
        default:
            return error
        }
    }
}

@MainActor
private final class UIKitVideoAlbumSaver: NSObject {
    private var continuation: CheckedContinuation<Void, Error>?

    static func save(_ url: URL) async throws {
        guard UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(url.path) else {
            throw ExportError.invalidPhotoResource
        }
        let saver = UIKitVideoAlbumSaver()
        try await saver.saveVideo(at: url)
    }

    private func saveVideo(at url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            UISaveVideoAtPathToSavedPhotosAlbum(
                url.path,
                self,
                #selector(saveCompleted(_:didFinishSavingWithError:contextInfo:)),
                nil
            )
        }
    }

    @objc private func saveCompleted(
        _ path: String,
        didFinishSavingWithError error: Error?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }
}
