import AVFoundation
import Foundation
import Photos
import UIKit

@MainActor
final class RecordingLibrary: ObservableObject {
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var audioRecordings: [AudioRecording] = []
    @Published private(set) var isLoading = false

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try SharedStorage.prepare()
            let directories = [SharedStorage.localDirectory, SharedStorage.broadcastDirectory].compactMap { $0 }
            let urls = directories.flatMap { directory in
                (try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
            }
            .filter {
                ["mp4", "mov"].contains($0.pathExtension.lowercased())
                    && !$0.lastPathComponent.hasPrefix("Edit-")
            }

            var loaded: [Recording] = []
            for url in urls {
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                let asset = AVURLAsset(url: url)
                let duration = (try? await asset.load(.duration).seconds) ?? 0
                loaded.append(Recording(
                    id: stableID(for: url),
                    url: url,
                    createdAt: values?.creationDate ?? .distantPast,
                    duration: duration.isFinite ? duration : 0,
                    byteCount: Int64(values?.fileSize ?? 0)
                ))
            }
            recordings = loaded.sorted { $0.createdAt > $1.createdAt }

            let audioURLs = ((try? FileManager.default.contentsOfDirectory(
                at: SharedStorage.audioDirectory,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []).filter {
                ["m4a", "aac", "wav", "caf", "mp3", "flac", "ogg"].contains($0.pathExtension.lowercased())
            }
            var loadedAudio: [AudioRecording] = []
            for url in audioURLs {
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                let asset = AVURLAsset(url: url)
                let duration = (try? await asset.load(.duration).seconds) ?? 0
                loadedAudio.append(AudioRecording(
                    id: stableID(for: url),
                    url: url,
                    createdAt: values?.creationDate ?? .distantPast,
                    duration: duration.isFinite ? duration : 0,
                    byteCount: Int64(values?.fileSize ?? 0)
                ))
            }
            audioRecordings = loadedAudio.sorted { $0.createdAt > $1.createdAt }
        } catch {
            recordings = []
            audioRecordings = []
        }
    }

    func delete(_ recording: Recording) {
        try? FileManager.default.removeItem(at: recording.url)
        recordings.removeAll { $0.id == recording.id }
    }

    func delete(_ recording: AudioRecording) {
        try? FileManager.default.removeItem(at: recording.url)
        for lyricExtension in LyricDocumentCodec.supportedFileExtensions {
            let lyricURL = recording.url.deletingPathExtension().appendingPathExtension(lyricExtension)
            try? FileManager.default.removeItem(at: lyricURL)
        }
        audioRecordings.removeAll { $0.id == recording.id }
    }

    func saveVideoToPhotos(_ url: URL) async throws -> PhotoVideoSaveResult {
        try await PhotoLibraryWriter.saveVideo(url)
    }

    private func stableID(for url: URL) -> UUID {
        let data = Data(url.path.utf8)
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in data.enumerated() { bytes[index % 16] = bytes[index % 16] &+ byte }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

enum ExportError: LocalizedError {
    case photoPermission
    case photoLimitedAccess
    case photoStorageFull
    case invalidPhotoResource
    case missingVideo
    case missingAudio
    case exportFailed
    case livePhotoFailed

    var errorDescription: String? {
        switch self {
        case .photoPermission: "未获得照片写入权限"
        case .photoLimitedAccess: "照片权限为有限访问，请在系统设置中改为完全访问后重试"
        case .photoStorageFull: "设备储存空间不足，无法写入照片图库"
        case .invalidPhotoResource: "视频未通过照片图库校验，原文件已保留"
        case .missingVideo: "视频不可用"
        case .missingAudio: "音频不可用"
        case .exportFailed: "导出失败"
        case .livePhotoFailed: "Live Photo 生成失败"
        }
    }
}
