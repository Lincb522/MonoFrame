import AVFoundation
import CoreImage
import CryptoKit
import UIKit
import XCTest
@testable import MonoFrame

final class ProEditingTests: XCTestCase {
    private let width = 160, height = 96
    private func buffer(phase: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferMetalCompatibilityKey as String: true, kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &buffer)
        XCTAssertEqual(status, 0)
        let result = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(result, [])
        let p = CVPixelBufferGetBaseAddress(result)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(result)
        for y in 0..<height { for x in 0..<width {
            let i = y * stride + x * 4
            p[i] = UInt8((x * 3 + phase * 19) % 256)
            p[i+1] = UInt8((y * 5 + phase * 13) % 256)
            p[i+2] = UInt8(((x / 20 + y / 16) % 2 == 0 ? 220 : 25) ^ (phase % 128))
            p[i+3] = 255
        }}
        CVPixelBufferUnlockBaseAddress(result, [])
        return result
    }
    private func pixels(_ buffer: CVPixelBuffer) -> Data {
        CVPixelBufferLockBaseAddress(buffer, .readOnly); defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        var data = Data()
        for row in 0..<height { data.append(CVPixelBufferGetBaseAddress(buffer)!.advanced(by: row * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: UInt8.self), count: width * 4) }
        return data
    }
    private func evidence() throws -> URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ProEditingEvidence")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    func testAll51KernelsHaveCorrectEndpointsAndDistinctInteriors() throws {
        XCTAssertEqual(VideoTransition.effects.count, 51)
        XCTAssertEqual(Set(VideoTransition.effects.map(\.functionName)).count, 51)
        let renderer = try VideoTransitionRenderer(), a = try buffer(phase: 0), b = try buffer(phase: 9), out = try buffer(phase: 0)
        let context = CIContext(mtlDevice: renderer.device)
        let directory = try evidence()
        var signatures = Set<String>(), report: [[String: Any]] = []
        for effect in VideoTransition.effects {
            for endpoint: Float in [0, 1] {
                try renderer.render(from: a, to: b, into: out, effect: effect, progress: endpoint)
                XCTAssertEqual(pixels(out), pixels(endpoint == 0 ? a : b), effect.rawValue + " endpoint / orientation")
            }
            var frames = Data()
            for progress: Float in [0.23, 0.51, 0.79] {
                try renderer.render(from: a, to: b, into: out, effect: effect, progress: progress)
                let data = pixels(out)
                XCTAssertNotEqual(data, pixels(a), effect.rawValue)
                XCTAssertNotEqual(data, pixels(b), effect.rawValue)
                XCTAssertTrue(data.enumerated().contains { $0.offset % 4 != 3 && $0.element > 10 }, effect.rawValue + " black frame")
                frames.append(data)
                if progress == 0.51 {
                    let image = try XCTUnwrap(context.createCGImage(CIImage(cvPixelBuffer: out), from: CGRect(x: 0, y: 0, width: width, height: height)))
                    try XCTUnwrap(UIImage(cgImage: image).pngData()).write(to: directory.appendingPathComponent(effect.functionName + ".png"))
                }
            }
            let hash = SHA256.hash(data: frames).map { String(format: "%02x", $0) }.joined()
            XCTAssertTrue(signatures.insert(hash).inserted, effect.rawValue + " duplicates another effect")
            report.append(["effect":effect.rawValue,"kernel":effect.functionName,"sha256":hash,"endpoints":true])
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: directory.appendingPathComponent("kernels.json"))
    }

    @MainActor func testMotionSplitUndoAndLegacyDecoding() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MotionModel-\(UUID()).mp4")
        try Data().write(to: url)
        let clip = VideoClip(sourceURL: url, sourceDuration: 6, start: 0, end: 6)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(clip)) as? [String: Any])
        json.removeValue(forKey: "motion")
        let decoded = try JSONDecoder().decode(VideoClip.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.motion); XCTAssertEqual(decoded.transition, .none)
        let editor = VideoEditor(sourceURL: clip.sourceURL, duration: 6)
        let motion = ClipMotion(start: .init(zoom: 1.1, x: -1), end: .init(zoom: 1.7, x: 1))
        editor.updateMotion(motion)
        XCTAssertTrue(editor.split(at: 3))
        XCTAssertEqual(editor.clips[0].motion?.end, editor.clips[1].motion?.start)
        XCTAssertEqual(editor.clips[1].motion?.end, motion.end)
        editor.beginContinuousEdit()
        for x in 0..<20 { editor.setTransition(.cube, duration: Double(x + 1) / 10, all: true) }
        editor.endContinuousEdit(); editor.undo()
        XCTAssertEqual(editor.clips[0].transition, .none)
        editor.redo(); XCTAssertEqual(editor.clips[0].transition, .cube)
        XCTAssertEqual(editor.snappedProjectTime(0.02, threshold: 0.1), 0)
    }

    private func makeSource(rotated: Bool = false) async throws -> URL {
        let url = try evidence().appendingPathComponent("ProSource-\(UUID()).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height])
        if rotated { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input); XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        for index in 0..<60 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            XCTAssertTrue(adaptor.append(try buffer(phase: index), withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        input.markAsFinished(); await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
        return url
    }

    @MainActor func testAllTransitionsInActualTimelinePreviewAndExport() async throws {
        let url = try await makeSource()
        let editor = VideoEditor(sourceURL: url, duration: 2)
        editor.setTrimEnd(0.6)
        for effect in VideoTransition.effects {
            editor.duplicateSelectedClip()
            let index = editor.clips.count - 2
            editor.selectClip(editor.clips[index].id)
            editor.setTransition(effect, duration: 0.2)
            editor.selectClip(editor.clips.last!.id)
        }
        editor.selectClip(editor.clips[0].id)
        editor.updateMotion(.init(start: .init(), end: .init(zoom: 1.3, x: 0.4)))
        let duration = editor.projectDuration
        XCTAssertEqual(duration, 21, accuracy: 0.05)
        XCTAssertEqual(editor.timecode(duration), "00:00:21:00")
        let preview = try await editor.makePreview()
        XCTAssertNotNil(preview.videoComposition)
        let output = try await editor.export()
        let result = try evidence().appendingPathComponent("all-51-transitions.mp4")
        if FileManager.default.fileExists(atPath: result.path) { try FileManager.default.removeItem(at: result) }
        try FileManager.default.copyItem(at: output, to: result)
        let asset = AVURLAsset(url: result)
        let actual = try await asset.load(.duration).seconds
        XCTAssertEqual(actual, duration, accuracy: 0.12)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        for index in 0..<51 {
            let time = editor.clipOffset(at: index + 1) + 0.1
            let frame = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
            XCTAssertEqual(frame.width, width); XCTAssertEqual(frame.height, height)
        }
        editor.saveDraft()
        let restored = VideoEditor(sourceURL: url, duration: 2)
        XCTAssertEqual(restored.clips, editor.clips)
        print("PRO_EDITING_EXPORT=\(result.path) DURATION=\(actual) TRANSITIONS=51")
    }
    @MainActor func testPortraitPreferredTransformMatchesOriginal() async throws {
        let url = try await makeSource(rotated: true)
        let editor = VideoEditor(sourceURL: url, duration: 2)
        editor.duplicateSelectedClip()
        let output = try await editor.export()
        func image(_ url: URL) async throws -> CGImage {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            return try await generator.image(at: CMTime(seconds: 0.2, preferredTimescale: 600)).image
        }
        let original = try await image(url), exported = try await image(output)
        XCTAssertEqual(exported.width, height); XCTAssertEqual(exported.height, width)
        func rgb(_ image: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            bytes.withUnsafeMutableBytes { ptr in
                let context = CGContext(data: ptr.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return bytes
        }
        let a = rgb(original), b = rgb(exported)
        let difference = zip(a, b).enumerated().filter { $0.offset % 4 != 3 }.reduce(0.0) { $0 + abs(Double($1.element.0) - Double($1.element.1)) } / Double(width * height * 3)
        XCTAssertLessThan(difference, 12, "Portrait rotation or mirroring changed: mean RGB delta \(difference)")
        print("PORTRAIT_MEAN_RGB_DELTA=\(difference)")
    }

    @MainActor func testStudioUserInterfaceProject() async throws {
        let source = try await makeSource()
        try SharedStorage.prepare()
        let url = SharedStorage.localDirectory.appendingPathComponent("ProStudio-Review.mov")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.copyItem(at: source, to: url)
        // Clear only the dedicated review project's previous test draft.
        let draft = SharedStorage.projectDirectory.appendingPathComponent("ProStudio-Review.json")
        if FileManager.default.fileExists(atPath: draft.path) { try FileManager.default.removeItem(at: draft) }
        let editor = VideoEditor(sourceURL: url, duration: 2)
        editor.duplicateSelectedClip(); editor.duplicateSelectedClip()
        editor.selectClip(editor.clips[0].id)
        editor.setTransition(.crossZoom, duration: 0.4, all: true)
        editor.addCaption(text: "MONOFRAME / MOTION STUDY", at: 0, duration: 2)
        editor.saveDraft()
        XCTAssertEqual(VideoEditor(sourceURL: url, duration: 2).clips.count, 3)
    }

}
