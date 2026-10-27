import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct SignalStudioView: View {
    enum MediaKind: String, CaseIterable { case video = "视频"; case audio = "音频" }

    @State private var mediaKind: MediaKind = .video
    @State private var presentsImporter = false
    @State private var importedVideo: Recording?
    @State private var importedAudio: AudioRecording?
    @State private var importError: String?
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(spacing: SignalSpace.lg) {
                SignalPageHeader(title: "做点新的", detail: "视频、声音，从一段素材开始")

                SignalSegmentedControl(
                    values: MediaKind.allCases.map { ($0, $0.rawValue) },
                    selection: $mediaKind
                )
                .youthDelayedReveal(delay: 0.36)

                importStage
                    .youthStageEntrance()
                recentMedia
                    .youthDelayedReveal(delay: 0.46)
            }
            .signalPagePadding()
            .padding(.bottom, 124)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .fileImporter(
            isPresented: $presentsImporter,
            allowedContentTypes: mediaKind == .video ? [.movie] : [.audio],
            allowsMultipleSelection: false
        ) { result in
            Task { await importMedia(result) }
        }
        .navigationDestination(isPresented: Binding(
            get: { importedVideo != nil },
            set: { if !$0 { importedVideo = nil } }
        )) {
            if let importedVideo { EditorView(recording: importedVideo) }
        }
        .navigationDestination(isPresented: Binding(
            get: { importedAudio != nil },
            set: { if !$0 { importedAudio = nil } }
        )) {
            if let importedAudio { AudioEditorView(recording: importedAudio) }
        }
        .alert("无法导入素材", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("好", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "请稍后重试")
        }
    }

    private var importStage: some View {
        Button { presentsImporter = true } label: {
            VStack(spacing: SignalSpace.lg) {
                HStack {
                    Text(mediaKind == .video ? "VIDEO INPUT" : "AUDIO INPUT")
                    Spacer()
                    Text(mediaKind == .video ? "MOV · MP4" : "M4A · WAV · FLAC")
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))

                Spacer(minLength: SignalSpace.sm)

                VStack(spacing: 8) {
                    Image(systemName: mediaKind == .video ? "film.stack" : "waveform")
                        .font(.system(size: 44, weight: .medium))
                        .contentTransition(.symbolEffect(.replace))
                    Text(mediaKind == .video ? "导入一段视频" : "导入一段音频")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text("原始文件保留不变")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: SignalSpace.md)

                Label("选择文件", systemImage: "plus")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(SignalColor.acid)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .foregroundStyle(.white)
            .padding(SignalSpace.md)
            .frame(maxWidth: .infinity, minHeight: 330)
            .background {
                ZStack(alignment: .bottomTrailing) {
                    SignalColor.stage
                    Circle()
                        .fill((mediaKind == .video ? SignalColor.cobalt : SignalColor.violet).opacity(0.35))
                        .frame(width: 190, height: 190)
                        .blur(radius: 56)
                        .offset(x: 60, y: 60)
                }
            }
            .clipShape(YouthNotchedPanelShape(cornerRadius: 34, notchWidth: 92, notchDepth: 62))
            .overlay(alignment: .topTrailing) {
                YouthStatusBubble(
                    value: mediaKind == .video ? "4K" : "48K",
                    symbol: mediaKind == .video ? "play.fill" : "waveform"
                )
                .padding(8)
            }
        }
        .buttonStyle(SignalPressStyle())
        .accessibilityHint("打开文件选择器")
    }

    @ViewBuilder private var recentMedia: some View {
        let videos = Array(library.recordings.prefix(4))
        let audio = Array(library.audioRecordings.prefix(4))
        let isEmpty = mediaKind == .video ? videos.isEmpty : audio.isEmpty

        VStack(alignment: .leading, spacing: SignalSpace.sm) {
            SignalSectionHeader(
                title: "继续创作",
                detail: isEmpty ? nil : "最近 \(mediaKind == .video ? videos.count : audio.count) 项"
            )

            if isEmpty {
                HStack(spacing: SignalSpace.sm) {
                    Image(systemName: "tray")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("没有最近素材")
                            .font(.system(.body, design: .rounded, weight: .bold))
                        Text("导入后可直接进入编辑器")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(SignalColor.secondary(scheme))
                    }
                    Spacer()
                }
                .padding(SignalSpace.md)
                .frame(minHeight: 82)
                .background(SignalColor.surface(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(SignalColor.rule(scheme), lineWidth: 1)
                }
            } else if mediaKind == .video {
                SignalPanel {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { index, item in
                            NavigationLink(value: item) { recentRow(item.title, detail: "\(item.durationText) · \(item.sizeText)", symbol: "film") }
                                .buttonStyle(.plain)
                            if index < videos.count - 1 { SignalRule().padding(.leading, 60) }
                        }
                    }
                }
            } else {
                SignalPanel {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(audio.enumerated()), id: \.element.id) { index, item in
                            NavigationLink(value: item) { recentRow(item.title, detail: "\(item.durationText) · \(item.formatText)", symbol: "waveform") }
                                .buttonStyle(.plain)
                            if index < audio.count - 1 { SignalRule().padding(.leading, 60) }
                        }
                    }
                }
            }
        }
    }

    private func recentRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: SignalSpace.sm) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(SignalColor.coral)
                .frame(width: 36, height: 36)
                .background(SignalColor.raised(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(.body, design: .rounded, weight: .bold)).lineLimit(1)
                Text(detail).font(.system(.caption, design: .monospaced)).foregroundStyle(SignalColor.secondary(scheme))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(SignalColor.secondary(scheme))
        }
        .foregroundStyle(SignalColor.ink(scheme))
        .padding(.horizontal, SignalSpace.md)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    @MainActor private func importMedia(_ result: Result<[URL], Error>) async {
        do {
            guard let source = try result.get().first else { return }
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }

            try SharedStorage.prepare()
            let directory = mediaKind == .video ? SharedStorage.localDirectory : SharedStorage.audioDirectory
            let fallbackExtension = mediaKind == .video ? "mp4" : "m4a"
            let fileExtension = source.pathExtension.isEmpty ? fallbackExtension : source.pathExtension
            let target = directory.appendingPathComponent("Import-\(UUID().uuidString).\(fileExtension)")
            try FileManager.default.copyItem(at: source, to: target)

            let asset = AVURLAsset(url: target)
            let duration = try await asset.load(.duration).seconds
            let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
            let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0

            if mediaKind == .video {
                importedVideo = Recording(id: UUID(), url: target, createdAt: .now, duration: duration, byteCount: bytes)
            } else {
                importedAudio = AudioRecording(id: UUID(), url: target, createdAt: .now, duration: duration, byteCount: bytes)
            }
            await library.reload()
        } catch {
            importError = error.localizedDescription
        }
    }
}
