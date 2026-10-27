import AVKit
import SwiftUI

private struct MediaQuickPreviewItem: Identifiable {
    let id: UUID
    let title: String
    let url: URL
    let isVideo: Bool
}

struct LibraryView: View {
    enum MediaType: String, CaseIterable { case video = "视频"; case audio = "音频" }

    @State private var mediaType: MediaType = .video
    @State private var actionTargetID: UUID?
    @State private var livePhotoTargetID: UUID?
    @State private var message: String?
    @State private var quickPreview: MediaQuickPreviewItem?
    @Namespace private var mediaSelectionNamespace
    @Namespace private var mediaZoomNamespace
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            header
            mediaPicker
            if isEmpty { emptyState }
            else { mediaList }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .background(Color.clear)
        .overlay(alignment: .top) {
            if let message { libraryToast(message) }
        }
        .sheet(item: $quickPreview) { item in
            MediaQuickPreview(item: item)
        }
        .navigationDestination(for: Recording.self) { recording in
            if reduceMotion {
                EditorView(recording: recording)
            } else {
                EditorView(recording: recording)
                    .navigationTransition(.zoom(sourceID: recording.id, in: mediaZoomNamespace))
            }
        }
        .navigationDestination(for: AudioRecording.self) { recording in
            if reduceMotion {
                AudioEditorView(recording: recording)
            } else {
                AudioEditorView(recording: recording)
                    .navigationTransition(.zoom(sourceID: recording.id, in: mediaZoomNamespace))
            }
        }
        .sensoryFeedback(.selection, trigger: mediaType)
        .sensoryFeedback(.impact(weight: .light), trigger: quickPreview?.id)
    }

    private var header: some View {
        MonoPageHeader("作品")
    }

    private var mediaPicker: some View {
        HStack(spacing: 10) {
            ForEach(MediaType.allCases, id: \.self) { item in
                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.36, dampingFraction: 0.88)) {
                        mediaType = item
                    }
                } label: {
                    HStack(spacing: 11) {
                        MonoIcon(item == .video ? "film" : "waveform", size: 19, weight: 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.rawValue)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                            Text("\(item == .video ? library.recordings.count : library.audioRecordings.count) 项")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .opacity(0.52)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background {
                        if mediaType == item {
                            Capsule()
                                .fill(MonoTheme.primary.opacity(0.13))
                                .matchedGeometryEffect(id: "library-media-selection", in: mediaSelectionNamespace)
                        }
                    }
                    .foregroundStyle(mediaType == item ? MonoTheme.ink(scheme) : MonoTheme.muted(scheme))
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(mediaType == item ? MonoTheme.primary.opacity(0.24) : Color.clear, lineWidth: 1)
                    }
                }
                .buttonStyle(MonoSpringPressStyle())
            }
        }
        .padding(5)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var isEmpty: Bool {
        mediaType == .video ? library.recordings.isEmpty : library.audioRecordings.isEmpty
    }

    private var mediaList: some View {
        ScrollView {
            Group {
                if mediaType == .video {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(library.recordings) { recording in
                        VStack(spacing: 7) {
                            ZStack(alignment: .topTrailing) {
                                NavigationLink(value: recording) {
                                    VideoTile(recording: recording)
                                        .matchedTransitionSource(id: recording.id, in: mediaZoomNamespace)
                                        .onLongPressGesture(minimumDuration: 0.42) {
                                            quickPreview = MediaQuickPreviewItem(
                                                id: recording.id,
                                                title: recording.title,
                                                url: recording.url,
                                                isVideo: true
                                            )
                                        }
                                }
                                .buttonStyle(MonoSpringPressStyle())
                                actionToggle(for: recording.id)
                                    .padding(8)
                            }
                            if actionTargetID == recording.id {
                                videoTileActions(recording)
                                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                            }
                        }
                    }
                }
                } else {
                    LazyVStack(spacing: 10) {
                    ForEach(library.audioRecordings) { recording in
                        VStack(spacing: 6) {
                            HStack(spacing: 8) {
                                NavigationLink(value: recording) {
                                    AudioRow(recording: recording)
                                        .matchedTransitionSource(id: recording.id, in: mediaZoomNamespace)
                                        .onLongPressGesture(minimumDuration: 0.42) {
                                            quickPreview = MediaQuickPreviewItem(
                                                id: recording.id,
                                                title: recording.title,
                                                url: recording.url,
                                                isVideo: false
                                            )
                                        }
                                }
                                    .buttonStyle(MonoSpringPressStyle())
                                    .frame(maxWidth: .infinity)
                                actionToggle(for: recording.id)
                            }
                            if actionTargetID == recording.id {
                                mediaActions(url: recording.url) {
                                    library.delete(recording)
                                    actionTargetID = nil
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(10)
                        .monoPanel()
                    }
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .refreshable { await library.reload() }
    }

    private func videoTileActions(_ recording: Recording) -> some View {
        VStack(spacing: 6) {
            Button { Task { await makeLivePhoto(from: recording) } } label: {
                HStack(spacing: 6) {
                    if livePhotoTargetID == recording.id { ProgressView().tint(.white) }
                    else { MonoIcon("livephoto", size: 14, weight: 2) }
                    Text("Live Photo")
                }
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(MonoTheme.coral)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(livePhotoTargetID != nil)

            HStack(spacing: 6) {
                ShareLink(item: recording.url) {
                    MonoLabel("共享", icon: "square.and.arrow.up", iconSize: 13)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(MonoTheme.surface(scheme))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Button(role: .destructive) {
                    library.delete(recording)
                    actionTargetID = nil
                } label: {
                    MonoIcon("trash", size: 13, weight: 2)
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 34)
                        .background(MonoTheme.stage)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(7)
        .monoPanel()
    }

    private func actionToggle(for id: UUID) -> some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.34, dampingFraction: 0.88)) {
                actionTargetID = actionTargetID == id ? nil : id
            }
        } label: {
            MonoIcon(actionTargetID == id ? "xmark" : "ellipsis", size: 16, weight: 2.1)
                .foregroundStyle(MonoTheme.ink(scheme))
                .frame(width: 44, height: 44)
                .background(MonoTheme.surfaceMuted(scheme))
                .clipShape(Circle())
        }
        .buttonStyle(MonoSpringPressStyle())
        .accessibilityLabel(actionTargetID == id ? "关闭操作" : "更多操作")
    }

    private func mediaActions(
        url: URL,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            ShareLink(item: url) {
                MonoLabel("共享", icon: "square.and.arrow.up")
                    .font(.system(.caption, design: .rounded, weight: .black))
                    .foregroundStyle(MonoTheme.ink(scheme))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(MonoTheme.background(scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Button(role: .destructive, action: onDelete) {
                MonoLabel("删除", icon: "trash")
                    .font(.system(.caption, design: .rounded, weight: .black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(MonoTheme.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .monoPanel()
    }

    private func videoActions(_ recording: Recording) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await makeLivePhoto(from: recording) }
            } label: {
                HStack(spacing: 6) {
                    if livePhotoTargetID == recording.id {
                        ProgressView().tint(.white)
                    } else {
                        MonoIcon("livephoto", size: 15, weight: 2.1)
                    }
                    Text("Live Photo")
                }
                .font(.system(.caption, design: .rounded, weight: .black))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(MonoTheme.coral)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(livePhotoTargetID != nil)

            ShareLink(item: recording.url) {
                MonoLabel("共享", icon: "square.and.arrow.up")
                    .font(.system(.caption, design: .rounded, weight: .black))
                    .foregroundStyle(MonoTheme.ink(scheme))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(MonoTheme.background(scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Button(role: .destructive) {
                library.delete(recording)
                actionTargetID = nil
            } label: {
                MonoIcon("trash", size: 15, weight: 2.1)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(MonoTheme.stage)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除")
        }
        .padding(8)
        .monoPanel()
    }

    private func makeLivePhoto(from recording: Recording) async {
        livePhotoTargetID = recording.id
        defer { livePhotoTargetID = nil }
        do {
            try await LivePhotoMaker.save(videoURL: recording.url)
            show("已保存 Live Photo")
        } catch {
            show(error.localizedDescription)
        }
    }

    private func show(_ text: String) {
        withAnimation(.easeOut(duration: 0.18)) { message = text }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeOut(duration: 0.18)) { message = nil }
        }
    }

    private func libraryToast(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 42)
            .background(MonoTheme.stage.opacity(0.94))
            .clipShape(Capsule())
            .padding(.top, 12)
    }

    private var emptyState: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.clear)

            Circle()
                .fill(MonoTheme.coral.opacity(0.14))
                .frame(width: 190, height: 190)
                .offset(x: 135, y: -95)

            VStack(spacing: 22) {
                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.76 - Double(index) * 0.12))
                            .frame(width: 118, height: 82)
                            .rotationEffect(.degrees(Double(index - 1) * 8))
                            .offset(x: CGFloat(index - 1) * 15, y: CGFloat(abs(index - 1)) * 9)
                    }
                    MonoIcon(mediaType == .video ? "play.fill" : "waveform", size: 27, weight: 2.1)
                        .foregroundStyle(mediaType == .video ? MonoTheme.primary : MonoTheme.mint)
                }
                .frame(height: 108)

                VStack(spacing: 6) {
                    Text(mediaType == .video ? "第一段画面会出现在这里" : "第一段声音会出现在这里")
                        .font(.system(.headline, design: .rounded, weight: .black))
                    Text(mediaType == .video ? "可逐帧剪辑·转 Live Photo·导出" : "可剪辑·混音·转码·导出")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(MonoTheme.muted(scheme))
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, minHeight: 330)
        .glassEffect(
            .regular.tint((mediaType == .video ? MonoTheme.primary : MonoTheme.mint).opacity(0.08)),
            in: .rect(cornerRadius: 34)
        )
        .foregroundStyle(MonoTheme.ink(scheme))
        .accessibilityElement(children: .combine)
    }
}

private struct VideoRow: View {
    let recording: Recording
    @State private var thumbnail: UIImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill() }
                    else {
                        MonoTheme.ink(scheme)
                            .overlay(MonoIcon("play.fill", size: 15, weight: 2.2).foregroundStyle(MonoTheme.background(scheme)))
                    }
                }
                .frame(width: 112, height: 74)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text(recording.durationText)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.76))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .padding(5)
            }
            rowText(title: recording.title, detail: "\(recording.sizeText)  ·  VIDEO")
        }
        .padding(.vertical, 12)
        .task { thumbnail = await ThumbnailLoader.image(for: recording.url) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recording.title)，\(recording.durationText)，\(recording.sizeText)")
        .accessibilityHint("打开视频编辑")
    }

    private func rowText(title: String, detail: String) -> some View {
        Group {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(.body, design: .rounded, weight: .black))
                Text(detail)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(MonoTheme.muted(scheme))
            }
            Spacer()
            MonoIcon("chevron.right", size: 15, weight: 2.2)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(MonoTheme.muted(scheme))
        }
        .foregroundStyle(MonoTheme.ink(scheme))
    }
}

private struct VideoTile: View {
    let recording: Recording
    @State private var thumbnail: UIImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [MonoTheme.stage, MonoTheme.electric.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .overlay(MonoIcon("play.fill", size: 19, weight: 2).foregroundStyle(.white))
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1.05, contentMode: .fit)
                .clipped()

                Text(recording.durationText)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.66))
                    .clipShape(Capsule())
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(recording.title)
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                    .lineLimit(1)
                Text(recording.sizeText)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(MonoTheme.muted(scheme))
            }
            .padding(.horizontal, 11)
            .padding(.bottom, 11)
        }
        .foregroundStyle(MonoTheme.ink(scheme))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        }
        .task { thumbnail = await ThumbnailLoader.image(for: recording.url) }
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开视频编辑")
    }
}

private struct AudioRow: View {
    let recording: AudioRecording
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 14) {
            MonoIcon("waveform", size: 20, weight: 2)
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 74, height: 74)
                .background(MonoTheme.stage)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 7) {
                Text(recording.title)
                    .font(.system(.body, design: .rounded, weight: .black))
                Text("\(recording.durationText)  ·  \(recording.sizeText)  ·  \(recording.formatText)")
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .foregroundStyle(MonoTheme.muted(scheme))
            }
            Spacer()
            MonoIcon("chevron.right", size: 15, weight: 2.2)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(MonoTheme.muted(scheme))
        }
        .foregroundStyle(MonoTheme.ink(scheme))
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开音频剪辑")
    }
}

private struct MediaQuickPreview: View {
    let item: MediaQuickPreviewItem
    @State private var player: AVPlayer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    init(item: MediaQuickPreviewItem) {
        self.item = item
        _player = State(initialValue: AVPlayer(url: item.url))
    }

    var body: some View {
        ZStack {
            MonoImmersiveBackground()
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("快速预览")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(MonoTheme.muted(scheme))
                        Text(item.title)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .lineLimit(1)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        MonoIcon("xmark", size: 15, weight: 2.2)
                            .frame(width: 42, height: 42)
                            .background(MonoTheme.surface(scheme))
                            .clipShape(Circle())
                    }
                    .buttonStyle(MonoSpringPressStyle())
                }

                if item.isVideo {
                    VideoPlayer(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [MonoTheme.primary.opacity(0.18), MonoTheme.lavender.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        MonoIcon("waveform", size: 70, weight: 1.8)
                        VideoPlayer(player: player).opacity(0.001)
                    }
                }
            }
            .padding(20)
            .foregroundStyle(MonoTheme.ink(scheme))
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { player.play() }
        .onDisappear { player.pause() }
    }
}
