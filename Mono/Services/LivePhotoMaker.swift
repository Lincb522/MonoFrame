import AVFoundation
import CoreMedia
import ImageIO
import Photos
import UniformTypeIdentifiers
import UIKit

enum LivePhotoMaker {
    struct Selection: Equatable {
        var start: Double
        var duration: Double
        /// Offset inside the selected clip; written to BOTH JPEG and MOV metadata.
        var keyTime: Double
        var muted = false
        func validate(sourceDuration: Double) throws {
            guard start.isFinite, duration.isFinite, keyTime.isFinite, start >= 0,
                  duration > 0, duration <= 3.001, start + duration <= sourceDuration + 0.02,
                  keyTime >= 0, keyTime < duration else { throw EditingDeskError.invalidRange }
        }
    }

    static func save(videoURL: URL, selection: Selection? = nil) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MonoFrame-Live-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let identifier = UUID().uuidString
        let resourceName = "MonoFrame-\(identifier.prefix(8))"
        let clippedURL = directory.appendingPathComponent("clip.mov")
        let photoURL = directory.appendingPathComponent("\(resourceName).JPG")
        let pairedVideoURL = directory.appendingPathComponent("\(resourceName).MOV")

        let duration = try await AVURLAsset(url: videoURL).load(.duration).seconds
        let length = min(3, duration)
        let selection = selection ?? Selection(start: max(0, (duration - length) / 2),
                                                duration: length, keyTime: length / 2)
        try selection.validate(sourceDuration: duration)
        try await makeClip(from: videoURL, output: clippedURL, selection: selection)
        try await makePhoto(from: clippedURL, output: photoURL, identifier: identifier, keyTime: selection.keyTime)
        try await makePairedVideo(from: clippedURL, output: pairedVideoURL, identifier: identifier, keyTime: selection.keyTime, muted: selection.muted)

        try await PhotoLibraryWriter.saveLivePhoto(
            photoURL: photoURL,
            pairedVideoURL: pairedVideoURL,
            identifier: identifier
        )
    }

    private static func makeClip(from sourceURL: URL, output: URL, selection: Selection) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let clipSeconds = selection.duration
        let startSeconds = selection.start

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.livePhotoFailed
        }
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: clipSeconds, preferredTimescale: 600)
        )
        try await exporter.export(to: output, as: .mov)
    }

    private static func makePhoto(from videoURL: URL, output: URL, identifier: String, keyTime: Double) async throws {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let result = try await generator.image(
            at: CMTime(seconds: keyTime, preferredTimescale: 600)
        )

        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { throw ExportError.livePhotoFailed }

        let metadata: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: ["17": identifier],
            kCGImageDestinationLossyCompressionQuality: 0.94
        ]
        CGImageDestinationAddImage(destination, result.image, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.livePhotoFailed }
    }

    private static func makePairedVideo(from sourceURL: URL, output: URL, identifier: String, keyTime: Double, muted: Bool) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)

        let contentIdentifier = AVMutableMetadataItem()
        contentIdentifier.identifier = .quickTimeMetadataContentIdentifier
        contentIdentifier.value = identifier as NSString
        contentIdentifier.dataType = kCMMetadataBaseDataType_UTF8 as String
        writer.metadata = [contentIdentifier]

        var pipelines: [(AVAssetReaderOutput, AVAssetWriterInput)] = []
        for mediaType in (muted ? [AVMediaType.video] : [.video, .audio]) {
            guard let track = try await asset.loadTracks(withMediaType: mediaType).first else { continue }
            let descriptions = try await track.load(.formatDescriptions)
            guard let hint = descriptions.first else { continue }
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            let input = AVAssetWriterInput(mediaType: mediaType, outputSettings: nil, sourceFormatHint: hint)
            input.expectsMediaDataInRealTime = false
            if mediaType == .video { input.transform = try await track.load(.preferredTransform) }
            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                pipelines.append((output, input))
            }
        }

        guard !pipelines.isEmpty else { throw ExportError.livePhotoFailed }
        let metadataInput = try stillImageMetadataInput()
        guard writer.canAdd(metadataInput.input) else { throw ExportError.livePhotoFailed }
        writer.add(metadataInput.input)

        guard writer.startWriting() else { throw writer.error ?? ExportError.livePhotoFailed }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else {
            writer.cancelWriting()
            throw reader.error ?? ExportError.livePhotoFailed
        }

        let stillTime = CMTime(seconds: keyTime, preferredTimescale: 600)
        let stillItem = AVMutableMetadataItem()
        stillItem.identifier = AVMetadataIdentifier(rawValue: "mdta/com.apple.quicktime.still-image-time")
        stillItem.dataType = kCMMetadataBaseDataType_SInt8 as String
        stillItem.value = 0 as NSNumber
        guard metadataInput.input.isReadyForMoreMediaData,
              metadataInput.adaptor.append(AVTimedMetadataGroup(
            items: [stillItem],
            timeRange: CMTimeRange(start: stillTime, duration: CMTime(value: 1, timescale: 600))
        )) else {
            reader.cancelReading()
            writer.cancelWriting()
            throw ExportError.livePhotoFailed
        }
        metadataInput.input.markAsFinished()

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (output, input) in pipelines {
                    group.addTask {
                        // The reader is shared: another track can transition it to
                        // completed before this task observes its own EOF. Every
                        // writer input must still be closed exactly once.
                        defer { input.markAsFinished() }
                        while reader.status == .reading {
                            try Task.checkCancellation()
                            guard writer.status == .writing else {
                                throw writer.error ?? ExportError.livePhotoFailed
                            }
                            if input.isReadyForMoreMediaData {
                                guard let sample = output.copyNextSampleBuffer() else { break }
                                guard input.append(sample) else {
                                    throw writer.error ?? ExportError.livePhotoFailed
                                }
                            } else {
                                try await Task.sleep(for: .milliseconds(2))
                            }
                        }
                    }
                }
                try await group.waitForAll()
            }
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            throw error
        }

        guard reader.status == .completed else { throw reader.error ?? ExportError.livePhotoFailed }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ExportError.livePhotoFailed }
    }

    private static func stillImageMetadataInput() throws -> (
        input: AVAssetWriterInput,
        adaptor: AVAssetWriterInputMetadataAdaptor
    ) {
        let specification: NSDictionary = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier:
                "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType:
                kCMMetadataBaseDataType_SInt8
        ]
        var description: CMMetadataFormatDescription?
        let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [specification] as CFArray,
            formatDescriptionOut: &description
        )
        guard status == noErr, let description else { throw ExportError.livePhotoFailed }
        let input = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: description)
        return (input, AVAssetWriterInputMetadataAdaptor(assetWriterInput: input))
    }
}
