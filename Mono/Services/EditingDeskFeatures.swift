import AVFoundation
import Foundation
import Speech
import CoreImage

struct VideoRedaction: Codable, Equatable, Identifiable, Sendable {
    enum Style: String, Codable, CaseIterable { case solid = "实色遮挡", mosaic = "马赛克" }
    var id = UUID()
    var x = 0.25
    var y = 0.3
    var width = 0.5
    var height = 0.18
    var start: Double
    var duration: Double
    var style: Style = .solid

    func rect(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width, y: (1 - y - height) * size.height,
               width: width * size.width, height: height * size.height)
    }

    func applied(to image: CIImage, size: CGSize) -> CIImage {
        let area = rect(in: size).intersection(CGRect(origin: .zero, size: size))
        let cover: CIImage
        switch style {
        case .solid: cover = CIImage(color: .black).cropped(to: area)
        case .mosaic:
            cover = image.clampedToExtent().applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: max(18, min(size.width, size.height) * 0.055)
            ]).cropped(to: area)
        }
        return cover.composited(over: image)
    }
}

enum EditingDeskError: LocalizedError {
    case invalidRange, speechUnavailable, localeUnavailable, noSpeech, sizeTooSmall, sizeExceeded
    var errorDescription: String? {
        switch self {
        case .invalidRange: return "所选时间范围无效，请重新选择入点和出点。"
        case .speechUnavailable: return "当前设备未提供本地语音转写能力，请在支持 SpeechTranscriber 的真机上使用自动字幕。"
        case .localeUnavailable: return "系统暂不支持所选识别语言。"
        case .noSpeech: return "没有识别到语音。原有字幕已保留，请检查视频是否包含清晰人声。"
        case .sizeTooSmall: return "目标体积太小，扣除音频和封装后的视频码率不足。请增加目标 MB。"
        case .sizeExceeded: return "实际输出仍超过目标体积，本次未交付超限文件。请增加体积或降低导出尺寸。"
        }
    }
}

enum VideoCaptionTranscriber {
    /// Transcribe the edited audio timeline, not the original asset's source time.
    static func transcribe(url: URL, localeID: String,
                           status: @escaping @MainActor (String) -> Void) async throws -> [TimedCaption] {
        guard SpeechTranscriber.isAvailable else { throw EditingDeskError.speechUnavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else {
            throw EditingDeskError.localeUnavailable
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        await status("准备本地语音模型；首次使用可能需要下载")
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else { throw ExportError.missingAudio }
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("Captions-\(UUID()).m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ExportError.exportFailed
        }
        try await exporter.export(to: audioURL, as: .m4a)
        await status("正在识别语音并生成时间轴")
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task { () throws -> [TimedCaption] in
            var captions: [TimedCaption] = []
            for try await result in transcriber.results {
                try Task.checkCancellation()
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                if result.isFinal && !text.isEmpty {
                    captions.append(TimedCaption(text: text, start: max(0, result.range.start.seconds),
                        duration: max(0.1, result.range.duration.seconds), position: .bottom))
                }
            }
            return captions
        }
        do {
            try await analyzer.start(inputAudioFile: AVAudioFile(forReading: audioURL), finishAfterFile: true)
            let result = try await withTaskCancellationHandler {
                try await collector.value
            } onCancel: {
                collector.cancel()
                Task { await analyzer.cancelAndFinishNow() }
            }
            guard !result.isEmpty else { throw EditingDeskError.noSpeech }
            return result.sorted { $0.start < $1.start }
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    static func srt(_ captions: [TimedCaption]) -> String {
        func time(_ seconds: Double) -> String {
            let ms = max(0, Int((seconds * 1000).rounded()))
            return String(format: "%02d:%02d:%02d,%03d", ms / 3600000, ms / 60000 % 60, ms / 1000 % 60, ms % 1000)
        }
        return captions.sorted { $0.start < $1.start }.enumerated().map { i, c in
            "\(i + 1)\n\(time(c.start)) --> \(time(c.start + c.duration))\n\(c.text)\n"
        }.joined(separator: "\n")
    }
}

enum EditorMediaImport {
    static func copy(_ url: URL) throws -> URL {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try SharedStorage.prepare()
        let directory = SharedStorage.projectDirectory.appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(UUID())-\(url.lastPathComponent)")
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}
