import AVFoundation
import CoreImage
import XCTest
@testable import MonoFrame

@MainActor
final class EditingDeskTests: XCTestCase {
    private func source() throws -> URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings/LivePhoto-Source.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Install the real media validation source first")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("EditingTest-\(UUID()).mp4")
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }

    func testProjectTimeUndoRedactionCaptionAndDraft() throws {
        let url = try source()
        let editor = VideoEditor(sourceURL: url, duration: 6)
        editor.speed = 2
        XCTAssertEqual(editor.projectDuration, 3, accuracy: 0.01)
        XCTAssertTrue(editor.splitProject(at: 1))
        XCTAssertEqual(editor.clips.count, 2)
        XCTAssertEqual(editor.sourcePosition(at: 2)?.time ?? -1, 4, accuracy: 0.01)
        editor.addCaption(text: "Edited captions", at: 0.5, duration: 1.25)
        let id = editor.addRedaction(at: 0.75)
        XCTAssertEqual(editor.redactions.count, 1)
        editor.undo()
        XCTAssertTrue(editor.redactions.isEmpty)
        XCTAssertEqual(editor.captions.count, 1)
        editor.redo()
        XCTAssertEqual(editor.redactions.first?.id, id)
        editor.saveDraft()
        let restored = VideoEditor(sourceURL: url, duration: 6)
        XCTAssertEqual(restored.redactions, editor.redactions)
        XCTAssertEqual(restored.captions, editor.captions)
        XCTAssertEqual(restored.clips, editor.clips)
        let srt = VideoCaptionTranscriber.srt(editor.captions)
        XCTAssertTrue(srt.contains("00:00:00,500 --> 00:00:01,750"))
        XCTAssertTrue(srt.contains("Edited captions"))
    }

    func testLivePhotoSelectionRejectsInvalidRanges() throws {
        XCTAssertNoThrow(try LivePhotoMaker.Selection(start: 1, duration: 2, keyTime: 0.3).validate(sourceDuration: 6))
        XCTAssertThrowsError(try LivePhotoMaker.Selection(start: 5, duration: 3, keyTime: 1).validate(sourceDuration: 6))
        XCTAssertThrowsError(try LivePhotoMaker.Selection(start: 0, duration: 2, keyTime: 2).validate(sourceDuration: 6))
        XCTAssertThrowsError(try LivePhotoMaker.Selection(start: .nan, duration: 2, keyTime: 1).validate(sourceDuration: 6))
    }

    func testActualExportBurnsTimedMaskAndCaptionsAndCompressionFits() async throws {
        let url = try source()
        let editor = VideoEditor(sourceURL: url, duration: 6)
        let id = editor.addRedaction(at: 1)
        var mask = try XCTUnwrap(editor.redactions.first(where: { $0.id == id }))
        mask.x = 0.2; mask.y = 0.2; mask.width = 0.6; mask.height = 0.4; mask.duration = 2
        editor.updateRedaction(mask)
        editor.addCaption(text: "MONO EDITING DESK", at: 0.5, duration: 3)
        let output = try await editor.export()
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 6, accuracy: 0.1)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let before = try await generator.image(at: CMTime(seconds: 0.25, preferredTimescale: 600)).image
        let covered = try await generator.image(at: CMTime(seconds: 1.5, preferredTimescale: 600)).image
        func pixel(_ image: CGImage, x: Double, y: Double) -> [UInt8] {
            let ci = CIImage(cgImage: image)
            var rgba = [UInt8](repeating: 0, count: 4)
            CIContext().render(ci, toBitmap: &rgba, rowBytes: 4,
                bounds: CGRect(x: Double(image.width) * x, y: Double(image.height) * y, width: 1, height: 1),
                format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return rgba
        }
        let black = pixel(covered, x: 0.5, y: 0.65)
        XCTAssertLessThan(Int(black[0]) + Int(black[1]) + Int(black[2]), 35)
        let original = pixel(before, x: 0.5, y: 0.65)
        XCTAssertGreaterThan(Int(original[0]) + Int(original[1]) + Int(original[2]), 80)

        let compressed = try await MediaTranscoder().compress(inputURL: output, maximumBytes: 500_000)
        let bytes = try compressed.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        XCTAssertGreaterThan(bytes, 0); XCTAssertLessThanOrEqual(bytes, 500_000)
        let compressedDuration = try await AVURLAsset(url: compressed).load(.duration).seconds
        XCTAssertEqual(compressedDuration, duration, accuracy: 0.1)
        let evidence = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EditingDeskEvidence")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        for (source, name) in [(output, "masked-captioned.mp4"), (compressed, "compressed-500KB.mp4")] {
            let dest = evidence.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.copyItem(at: source, to: dest)
        }
        print("EDITING_DESK_EVIDENCE \(evidence.path); compressed bytes \(bytes)")
    }
}
