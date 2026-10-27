import AVFoundation
import Combine
import UniformTypeIdentifiers

@MainActor
final class PearlImportModel: ObservableObject {
    enum MediaKind: String, CaseIterable, Identifiable {
        case video
        case audio

        var id: String { rawValue }
        var allowedContentTypes: [UTType] { self == .video ? [.movie] : [.audio] }
    }

    @Published var pendingKind: MediaKind = .video
    @Published var isImporting = false
    @Published var importedVideo: Recording?
    @Published var importedAudio: AudioRecording?
    @Published var errorMessage: String?

    func beginImport(_ kind: MediaKind) {
        pendingKind = kind
        isImporting = true
    }

    func importMedia(_ result: Result<[URL], Error>, library: RecordingLibrary) async {
        do {
            guard let source = try result.get().first else { return }
            let imported = try await stage(source: source, kind: pendingKind)
            switch imported {
            case let .video(recording): importedVideo = recording
            case let .audio(recording): importedAudio = recording
            }
            await library.reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stage(source: URL, kind: MediaKind) async throws -> ImportedMedia {
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }
        try SharedStorage.prepare()
        let directory = kind == .video ? SharedStorage.localDirectory : SharedStorage.audioDirectory
        let fallbackExtension = kind == .video ? "mp4" : "m4a"
        let fileExtension = source.pathExtension.isEmpty ? fallbackExtension : source.pathExtension
        let target = directory.appendingPathComponent("Import-\(UUID().uuidString).\(fileExtension)")

        do {
            try FileManager.default.copyItem(at: source, to: target)
            let loadedDuration = (try? await AVURLAsset(url: target).load(.duration).seconds) ?? 0
            let duration = loadedDuration.isFinite ? max(0, loadedDuration) : 0
            let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            if kind == .video {
                return .video(Recording(id: UUID(), url: target, createdAt: .now, duration: duration, byteCount: byteCount))
            }
            return .audio(AudioRecording(id: UUID(), url: target, createdAt: .now, duration: duration, byteCount: byteCount))
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }

    private enum ImportedMedia {
        case video(Recording)
        case audio(AudioRecording)
    }
}


@MainActor
final class PearlTranscodeModel: ObservableObject {
    @Published var isImporting = false
    @Published var errorMessage: String?
    let queue: TranscodeQueue
    private var observer: AnyCancellable?

    init() {
        let queue = TranscodeQueue()
        self.queue = queue
        observer = queue.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
    }

    func receive(_ result: Result<[URL], Error>) async {
        var staged: [(URL, MediaProbe)] = []
        do {
            for source in try result.get() {
                staged.append(try await stage(source))
            }
            try queue.add(files: staged)
        } catch {
            for (url, _) in staged { try? FileManager.default.removeItem(at: url) }
            errorMessage = error.localizedDescription
        }
    }

    private func stage(_ source: URL) async throws -> (URL, MediaProbe) {
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }
        try SharedStorage.prepare()
        let fileExtension = source.pathExtension.isEmpty ? "media" : source.pathExtension
        let target = SharedStorage.transcodeDirectory
            .appendingPathComponent("Input-\(UUID().uuidString).\(fileExtension)")
        do {
            try FileManager.default.copyItem(at: source, to: target)
            return (target, try await MediaProbe.inspect(target))
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }
}

