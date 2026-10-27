import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct StudioView: View {
    private enum MediaKind: String, CaseIterable {
        case video = "视频"
        case audio = "音频"

        var icon: String { self == .video ? "film.stack" : "waveform" }
    }

    @State private var kind: MediaKind = .video
    @State private var isImporterPresented = false
    @State private var importedVideo: Recording?
    @State private var importedAudio: AudioRecording?
    @State private var message: String?
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                modePicker
                newProjectStage
                capabilityRail
                recentProjects
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Color.clear)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: false,
            onCompletion: importMedia
        )
        .navigationDestination(isPresented: videoDestination) {
            if let importedVideo { EditorView(recording: importedVideo) }
        }
        .navigationDestination(isPresented: audioDestination) {
            if let importedAudio { AudioEditorView(recording: importedAudio) }
        }
        .overlay(alignment: .top) {
            if let message { toast(message) }
        }
    }

    private var header: some View {
        MonoPageHeader("创作空间") {
            MonoIcon("timeline.selection", size: 24, weight: 2.1)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 12) {
            ForEach(MediaKind.allCases, id: \.self) { item in
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.92)) { kind = item }
                } label: {
                    HStack(spacing: 9) {
                        MonoIcon(item.icon, size: 19, weight: 2.1)
                        Text(item == .video ? "视频剪辑" : "音频制作")
                            .font(.system(.subheadline, design: .rounded, weight: .black))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(kind == item ? Color.white : MonoTheme.muted(scheme))
                    .background(kind == item ? MonoTheme.primary : Color.clear)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(kind == item ? MonoTheme.primary.opacity(0.26) : Color.clear, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var newProjectStage: some View {
        ZStack(alignment: .bottomTrailing) {
            if kind == .video { videoTracks.padding(.leading, 118).padding(.trailing, 18).padding(.bottom, 22) }
            else { audioTracks.padding(.leading, 118).padding(.trailing, 18).padding(.bottom, 24) }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("新建")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(MonoTheme.muted(scheme))
                    Text(kind == .video ? "开始一段新剪辑" : "开始一段新制作")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .tracking(-0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Button { isImporterPresented = true } label: {
                ZStack {
                    Circle().fill(MonoTheme.primary.opacity(0.46))
                    Circle().stroke(Color.white.opacity(0.65), lineWidth: 1.5).padding(6)
                    MonoIcon("plus", size: 20, weight: 2.4).foregroundStyle(.white)
                }
                .frame(width: 62, height: 62)
                .glassEffect(.regular.tint(MonoTheme.primary).interactive(), in: .circle)
                .shadow(color: MonoTheme.primary.opacity(0.25), radius: 16, y: 8)
            }
            .buttonStyle(MonoSpringPressStyle())
            .accessibilityLabel(kind == .video ? "导入视频" : "导入音频")
        }
        .foregroundStyle(MonoTheme.ink(scheme))
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 248)
        .glassEffect(
            .regular.tint((kind == .video ? MonoTheme.primary : MonoTheme.mint).opacity(0.10)),
            in: .rect(cornerRadius: 30)
        )
        .shadow(color: MonoTheme.primary.opacity(0.10), radius: 26, y: 12)
    }

    private var capabilityRail: some View {
        VStack(alignment: .leading, spacing: 11) {
            MonoSectionHeader(title: "创作工具", detail: "4 项")
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    capability("逐帧剪辑", detail: "FRAME", icon: "timeline.selection", tint: MonoTheme.coral, width: 142)
                    capability("混音人声", detail: "MIX", icon: "waveform", tint: MonoTheme.electric, width: 126)
                    capability("字幕歌词", detail: "LYRIC", icon: "captions.bubble", tint: MonoTheme.cyan, width: 138)
                    capability("高清导出", detail: "2K", icon: "sparkles.rectangle.stack", tint: MonoTheme.success, width: 124)
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func capability(_ title: String, detail: String, icon: String, tint: Color, width: CGFloat) -> some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(tint.opacity(0.16))
                Circle().stroke(tint.opacity(0.22), lineWidth: 1)
                MonoIcon(icon, size: 17, weight: 2.1).foregroundStyle(tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(tint)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: width, alignment: .leading)
        .frame(minHeight: 62)
        .glassEffect(.regular.tint(tint.opacity(0.08)).interactive(), in: .capsule)
    }

    private var videoTracks: some View {
        VStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<9, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(index.isMultiple(of: 3) ? MonoTheme.primary.opacity(0.54) : MonoTheme.primary.opacity(0.18))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
            }
            HStack(spacing: 3) {
                ForEach(0..<27, id: \.self) { index in
                    Capsule()
                        .fill(MonoTheme.coral.opacity(index.isMultiple(of: 4) ? 1 : 0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: CGFloat(5 + (index * 11) % 22))
                }
            }
            .frame(height: 28)
        }
        .overlay {
            Rectangle()
                .fill(MonoTheme.coral)
                .frame(width: 2)
        }
        .accessibilityHidden(true)
    }

    private var audioTracks: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<38, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 5) ? MonoTheme.mint : MonoTheme.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: CGFloat(8 + (index * 17) % 62))
            }
        }
        .frame(height: 86)
        .accessibilityHidden(true)
    }

    private var recentProjects: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoSectionHeader(title: "最近项目", detail: "\(projectCount)")

            if projectCount == 0 {
                HStack(spacing: 12) {
                    MonoIcon(kind == .video ? "film" : "waveform", size: 20, weight: 2)
                    Text("导入素材后从这里继续")
                }
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(MonoTheme.muted(scheme))
                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        if kind == .video {
                            ForEach(Array(library.recordings.prefix(6))) { recording in
                                NavigationLink(value: recording) {
                                    projectRow(
                                        title: recording.title,
                                        detail: "\(recording.durationText) · \(recording.sizeText)",
                                        icon: "film"
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            ForEach(Array(library.audioRecordings.prefix(6))) { recording in
                                NavigationLink(value: recording) {
                                    projectRow(
                                        title: recording.title,
                                        detail: "\(recording.durationText) · \(recording.formatText)",
                                        icon: "waveform"
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .foregroundStyle(MonoTheme.ink(scheme))
    }

    private func projectRow(title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 13) {
            MonoIcon(icon, size: 20, weight: 2)
                .font(.system(size: 17, weight: .black))
                .frame(width: 44, height: 44)
                .background(MonoTheme.primary.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                Text(detail)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(MonoTheme.muted(scheme))
            }
            Spacer()
            MonoIcon("chevron.right", size: 15, weight: 2.2)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(MonoTheme.muted(scheme))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(width: 255)
        .frame(minHeight: 72)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        .contentShape(Rectangle())
    }

    private var projectCount: Int {
        kind == .video ? library.recordings.count : library.audioRecordings.count
    }

    private var allowedTypes: [UTType] {
        kind == .video ? [.movie, .mpeg4Movie, .quickTimeMovie] : [.audio]
    }

    private var videoDestination: Binding<Bool> {
        Binding(
            get: { importedVideo != nil },
            set: { if !$0 { importedVideo = nil } }
        )
    }

    private var audioDestination: Binding<Bool> {
        Binding(
            get: { importedAudio != nil },
            set: { if !$0 { importedAudio = nil } }
        )
    }

    private func importMedia(_ result: Result<[URL], Error>) {
        Task {
            do {
                guard let source = try result.get().first else { return }
                let didAccess = source.startAccessingSecurityScopedResource()
                defer { if didAccess { source.stopAccessingSecurityScopedResource() } }
                try SharedStorage.prepare()
                let directory = kind == .video ? SharedStorage.localDirectory : SharedStorage.audioDirectory
                let fallbackExtension = kind == .video ? "mp4" : "m4a"
                let pathExtension = source.pathExtension.isEmpty ? fallbackExtension : source.pathExtension
                let destination = directory.appendingPathComponent(
                    "Import-\(UUID().uuidString).\(pathExtension)"
                )
                try FileManager.default.copyItem(at: source, to: destination)

                let asset = AVURLAsset(url: destination)
                let duration = (try? await asset.load(.duration).seconds) ?? 0
                let size = Int64((try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                let createdAt = Date()
                if kind == .video {
                    importedVideo = Recording(
                        id: UUID(), url: destination, createdAt: createdAt,
                        duration: duration.isFinite ? duration : 0, byteCount: size
                    )
                } else {
                    importedAudio = AudioRecording(
                        id: UUID(), url: destination, createdAt: createdAt,
                        duration: duration.isFinite ? duration : 0, byteCount: size
                    )
                }
                await library.reload()
            } catch {
                show(error.localizedDescription)
            }
        }
    }

    private func toast(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .rounded, weight: .bold))
            .foregroundStyle(MonoTheme.background(scheme))
            .padding(.horizontal, 16)
            .frame(minHeight: 42)
            .background(MonoTheme.ink(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.top, 12)
    }

    private func show(_ text: String) {
        withAnimation(.easeOut(duration: 0.18)) { message = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.18)) { message = nil }
        }
    }
}
