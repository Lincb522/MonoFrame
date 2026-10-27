import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Studio

struct CanvasStudioView: View {
    @StateObject private var model = CanvasStudioModel()
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        CanvasPage(horizontalPadding: 0, topPadding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                studioHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                filmRail
                    .padding(.top, 48)

                editorLane
                    .padding(.horizontal, 20)
                    .padding(.top, 25)

                recentProjects
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
            }
        }
        .fileImporter(
            isPresented: $model.isImporting,
            allowedContentTypes: model.pendingKind.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            Task { await model.importMedia(result, library: library) }
        }
        .navigationDestination(isPresented: videoDestination) {
            if let recording = model.importedVideo {
                CanvasVideoEditorView(recording: recording)
            }
        }
        .navigationDestination(isPresented: audioDestination) {
            if let recording = model.importedAudio {
                CanvasAudioEditorView(recording: recording)
            }
        }
        .alert("无法导入素材", isPresented: errorPresentation) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "请稍后重试")
        }
        .accessibilityIdentifier("canvas.studio.page")
    }

    private var filmRail: some View {
        ZStack {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 4) {
                    if library.recordings.isEmpty {
                        ForEach(0..<5, id: \.self) { index in
                            CanvasFilmPlaceholder(index: index)
                                .frame(width: 120, height: 100)
                        }
                    } else {
                        ForEach(library.recordings.prefix(8)) { recording in
                            CanvasStudioThumbnail(recording: recording)
                                .frame(width: 142, height: 100)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)

            Rectangle()
                .fill(CanvasColor.surface(scheme).opacity(0.92))
                .frame(width: 4, height: 132)
                .shadow(color: .black.opacity(0.12), radius: 3)
                .overlay(alignment: .top) {
                    Circle()
                        .fill(CanvasColor.coral)
                        .frame(width: 7, height: 7)
                        .offset(y: -3)
                }
                .allowsHitTesting(false)
        }
        .frame(height: 114)
        .accessibilityHidden(true)
    }

    private var editorLane: some View {
        ZStack {
            Rectangle()
                .fill(CanvasColor.hairline(scheme))
                .frame(width: 1, height: 266)
                .allowsHitTesting(false)

            VStack(spacing: 23) {
                importBar(kind: .video)

                CanvasWaveform(active: false, phase: 0, sampleCount: 78)
                    .frame(height: 112)
                    .padding(.horizontal, -20)

                importBar(kind: .audio)
            }
        }
    }

    private var studioHeader: some View {
        HStack(spacing: 12) {
            pageTitle("编辑")
            Spacer(minLength: 12)
            Menu {
                Button("导入视频") { model.beginImport(.video) }
                Button("导入音频") { model.beginImport(.audio) }
            } label: {
                CanvasGlyph(.more, size: 20)
                    .foregroundStyle(CanvasColor.secondary(scheme))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CanvasPressStyle())
            .accessibilityLabel("更多编辑操作")
            .accessibilityHint("可导入视频或音频")
            .accessibilityIdentifier("canvas.studio.more")
        }
        .frame(minHeight: 44)
    }

    private func importBar(kind: CanvasStudioModel.MediaKind) -> some View {
        CanvasGlassSurface(role: .segmented, cornerRadius: 12) {
            Button { model.beginImport(kind) } label: {
                HStack(spacing: 12) {
                    CanvasGlyph(kind == .video ? .video : .audio, size: 18)
                        .foregroundStyle(CanvasColor.secondary(scheme))
                    Text(kind == .video ? "导入视频" : "导入音频")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    CanvasGlyph(.plus, size: 18)
                        .foregroundStyle(CanvasColor.secondary(scheme))
                }
                .foregroundStyle(CanvasColor.ink(scheme))
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(CanvasPressStyle())
        }
        .accessibilityIdentifier("canvas.studio.import.\(kind.rawValue)")
        .accessibilityHint("打开系统文件选择器")
    }

    private var recentProjects: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近项目")
                .font(.headline.weight(.semibold))
                .foregroundStyle(CanvasColor.ink(scheme))

            if library.recordings.isEmpty && library.audioRecordings.isEmpty {
                HStack(spacing: 10) {
                    CanvasGlyph(.edit, size: 18)
                    Text("导入第一个素材后，项目会保留在这里。")
                        .font(.subheadline)
                }
                .foregroundStyle(CanvasColor.secondary(scheme))
                .frame(minHeight: 52)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        ForEach(library.recordings.prefix(6)) { recording in
                            NavigationLink(value: recording) {
                                VStack(alignment: .leading, spacing: 5) {
                                    CanvasStudioThumbnail(recording: recording)
                                        .frame(width: 64, height: 64)
                                    Text(recording.durationText)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(CanvasColor.secondary(scheme))
                                }
                            }
                            .buttonStyle(CanvasPressStyle())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func pageTitle(_ text: String) -> some View {
        Text(text)
            .font(.title.weight(.bold))
            .foregroundStyle(CanvasColor.ink(scheme))
            .accessibilityAddTraits(.isHeader)
    }

    private var videoDestination: Binding<Bool> {
        Binding(
            get: { model.importedVideo != nil },
            set: { if !$0 { model.importedVideo = nil } }
        )
    }

    private var audioDestination: Binding<Bool> {
        Binding(
            get: { model.importedAudio != nil },
            set: { if !$0 { model.importedAudio = nil } }
        )
    }

    private var errorPresentation: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

@MainActor
private final class CanvasStudioModel: ObservableObject {
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

private struct CanvasStudioThumbnail: View {
    let recording: Recording
    @State private var image: UIImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                CanvasFilmPlaceholder(index: abs(recording.id.hashValue) % 5)
            }
        }
        .clipped()
        .task(id: recording.url) { image = await ThumbnailLoader.image(for: recording.url) }
        .accessibilityHidden(true)
    }
}

private struct CanvasFilmPlaceholder: View {
    let index: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            CanvasColor.elevated(scheme)
            SwiftUI.Canvas { context, size in
                let base = CanvasColor.secondary(scheme).opacity(0.15 + Double(index % 3) * 0.035)
                let horizon = size.height * (0.43 + CGFloat(index % 3) * 0.07)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: horizon))
                path.addCurve(
                    to: CGPoint(x: size.width, y: horizon * 0.74),
                    control1: CGPoint(x: size.width * 0.35, y: horizon * 0.42),
                    control2: CGPoint(x: size.width * 0.64, y: horizon * 1.24)
                )
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(base))
            }
            CanvasGlyph(.video, size: 20)
                .foregroundStyle(CanvasColor.secondary(scheme).opacity(0.42))
        }
    }
}

// MARK: - Library

struct CanvasLibraryView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all
        case video
        case audio
        var id: String { rawValue }
        var title: String {
            switch self { case .all: "全部"; case .video: "视频"; case .audio: "音频" }
        }
    }

    @State private var query = ""
    @State private var filter: Filter = .all
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                if filteredVideos.isEmpty && filteredAudio.isEmpty {
                    emptyState
                        .padding(.horizontal, 22)
                        .padding(.top, 118)
                } else {
                    ForEach(filteredVideos) { recording in
                        CanvasLibraryVideoTile(recording: recording) {
                            library.delete(recording)
                        }
                    }

                    if !filteredAudio.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredAudio.enumerated()), id: \.element.id) { index, recording in
                                CanvasLibraryAudioRow(recording: recording) {
                                    library.delete(recording)
                                }
                                if index < filteredAudio.count - 1 {
                                    CanvasHairline().padding(.leading, 76)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, filteredVideos.isEmpty ? 0 : 16)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { await library.reload() }
        .background(CanvasBackdrop())
        .task {
            if library.recordings.isEmpty && library.audioRecordings.isEmpty {
                await library.reload()
            }
        }
        .accessibilityIdentifier("canvas.library.page")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("作品")
                .font(.title.weight(.bold))
                .foregroundStyle(CanvasColor.ink(scheme))
                .accessibilityAddTraits(.isHeader)

            CanvasGlassSurface(role: .search, cornerRadius: 18) {
                HStack(spacing: 10) {
                    CanvasGlyph(.search, size: 17)
                        .foregroundStyle(CanvasColor.secondary(scheme))
                    TextField("搜索", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.subheadline)

                    if !query.isEmpty {
                        Button { query = "" } label: {
                            CanvasGlyph(.close, size: 15)
                                .foregroundStyle(CanvasColor.secondary(scheme))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(CanvasPressStyle())
                        .accessibilityLabel("清除搜索")
                    }

                    Menu {
                        ForEach(Filter.allCases) { candidate in
                            Button(candidate.title) { filter = candidate }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(filter.title)
                            CanvasGlyph(.chevronRight, size: 12).rotationEffect(.degrees(90))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(CanvasColor.secondary(scheme))
                        .frame(minWidth: 64, minHeight: 44)
                    }
                    .accessibilityLabel("筛选作品")
                    .accessibilityValue(filter.title)
                }
                .padding(.leading, 14)
                .padding(.trailing, 5)
                .frame(minHeight: 48)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            CanvasGlyph(filter == .audio ? .audio : .library, size: 27)
                .foregroundStyle(CanvasColor.tertiary(scheme))
            Text(query.isEmpty ? "还没有作品" : "没有找到结果")
                .font(.headline.weight(.semibold))
                .foregroundStyle(CanvasColor.ink(scheme))
            Text(query.isEmpty ? "录屏或导入素材后，会按时间显示在这里。" : "试试其他文件名。")
                .font(.subheadline)
                .foregroundStyle(CanvasColor.secondary(scheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var filteredVideos: [Recording] {
        guard filter != .audio else { return [] }
        guard !query.isEmpty else { return library.recordings }
        return library.recordings.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredAudio: [AudioRecording] {
        guard filter != .video else { return [] }
        guard !query.isEmpty else { return library.audioRecordings }
        return library.audioRecordings.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct CanvasLibraryVideoTile: View {
    let recording: Recording
    let delete: () -> Void
    @State private var thumbnail: UIImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationLink(value: recording) {
            ZStack(alignment: .bottom) {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill()
                    } else {
                        CanvasFilmPlaceholder(index: abs(recording.id.hashValue) % 5)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(2.1, contentMode: .fit)
                .clipped()

                Text(
                    "\(recording.createdAt.formatted(date: .numeric, time: .omitted))"
                        + "  ·  \(recording.durationText)"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .monospacedDigit()
                .shadow(color: .black.opacity(0.34), radius: 2, y: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 11)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CanvasPressStyle())
        .contextMenu {
            ShareLink(item: recording.url) { Text("分享文件") }
            Button("删除", role: .destructive, action: delete)
        }
        .task(id: recording.url) { thumbnail = await ThumbnailLoader.image(for: recording.url) }
        .accessibilityLabel("\(recording.title)，\(recording.durationText)")
        .accessibilityHint("打开视频编辑")
    }
}

private struct CanvasLibraryAudioRow: View {
    let recording: AudioRecording
    let delete: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: recording) {
                HStack(spacing: 12) {
                    CanvasGlyph(.waveform, size: 21)
                        .foregroundStyle(CanvasColor.accent(scheme))
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recording.title).font(.body.weight(.medium)).lineLimit(1)
                        Text("\(recording.durationText)  ·  \(recording.formatText)  ·  \(recording.sizeText)")
                            .font(.caption)
                            .foregroundStyle(CanvasColor.secondary(scheme))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    CanvasGlyph(.chevronRight, size: 13)
                        .foregroundStyle(CanvasColor.tertiary(scheme))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(CanvasPressStyle())

            Menu {
                ShareLink(item: recording.url) { Text("分享文件") }
                Button("删除", role: .destructive, action: delete)
            } label: {
                CanvasGlyph(.more, size: 18)
                    .foregroundStyle(CanvasColor.secondary(scheme))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("更多操作")
        }
        .foregroundStyle(CanvasColor.ink(scheme))
        .frame(minHeight: 68)
    }
}

// MARK: - Transcode

struct CanvasTranscodeView: View {
    @StateObject private var model = CanvasTranscodeModel()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        CanvasPage(horizontalPadding: 20, topPadding: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text("转码")
                    .font(.title.weight(.bold))
                    .foregroundStyle(CanvasColor.ink(scheme))
                    .accessibilityAddTraits(.isHeader)

                flow
                    .padding(.top, 64)

                primaryAction
                    .padding(.top, 88)

                if !model.queue.jobs.isEmpty {
                    jobList.padding(.top, 28)
                }
            }
        }
        .fileImporter(
            isPresented: $model.isImporting,
            allowedContentTypes: [.movie, .audio, .data],
            allowsMultipleSelection: true
        ) { result in
            Task { await model.receive(result) }
        }
        .alert("无法加入任务", isPresented: errorPresentation) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "请稍后重试")
        }
        .accessibilityIdentifier("canvas.transcode.page")
    }

    private var flow: some View {
        VStack(spacing: 0) {
            inputNode

            flowConnector

            compactFlowNode(
                glyph: .format,
                title: "格式",
                primary: model.queue.jobs.first?.target.title ?? "自动匹配",
                secondary: model.queue.jobs.isEmpty ? "导入后可更改" : "为当前文件选择"
            )

            flowConnector

            compactFlowNode(
                glyph: .folder,
                title: "输出",
                primary: outputTitle,
                secondary: "/MonoFrame/输出"
            )
        }
        .padding(.leading, 20)
    }

    private var inputNode: some View {
        let job = model.queue.jobs.first
        return HStack(spacing: 16) {
            CanvasTranscodeInputPreview(job: job)
                .frame(width: 120, height: 88)

            flowCopy(
                title: "输入",
                primary: job?.title ?? "选择一个媒体文件",
                secondary: job?.detail ?? "MOV、MP4、M4A、WAV 等"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 88)
        .accessibilityElement(children: .combine)
    }

    private func compactFlowNode(
        glyph: CanvasGlyphName,
        title: String,
        primary: String,
        secondary: String
    ) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CanvasColor.elevated(scheme))
                    .frame(width: 72, height: 72)
                CanvasGlyph(glyph, size: 25)
                    .foregroundStyle(CanvasColor.secondary(scheme))
            }
            .frame(width: 120, height: 72)
            .accessibilityHidden(true)

            flowCopy(title: title, primary: primary, secondary: secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 80)
    }

    private func flowCopy(
        title: String,
        primary: String,
        secondary: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(primary)
                .font(.subheadline)
                .lineLimit(1)
            Text(secondary)
                .font(.caption)
                .foregroundStyle(CanvasColor.secondary(scheme))
                .lineLimit(1)
        }
        .foregroundStyle(CanvasColor.ink(scheme))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var flowConnector: some View {
        VStack(spacing: 0) {
            Rectangle().fill(CanvasColor.hairline(scheme)).frame(width: 1, height: 40)
            CanvasGlyph(.chevronRight, size: 12, weight: 1.5)
                .foregroundStyle(CanvasColor.tertiary(scheme))
                .rotationEffect(.degrees(90))
                .frame(height: 18)
            Rectangle().fill(CanvasColor.hairline(scheme)).frame(width: 1, height: 26)
        }
        .frame(width: 18)
        .frame(width: 120)
        .accessibilityHidden(true)
    }

    private var jobList: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.queue.jobs.enumerated()), id: \.element.id) { index, job in
                CanvasTranscodeJobRow(
                    job: job,
                    availableTargets: model.queue.availableTargets(for: job.probe),
                    setTarget: { model.queue.setTarget($0, for: job.id) },
                    retry: { model.queue.retry(job.id) },
                    remove: { model.queue.remove(job.id) }
                )
                if index < model.queue.jobs.count - 1 { CanvasHairline() }
            }
        }
    }

    private var primaryAction: some View {
        VStack(spacing: 10) {
            if model.queue.jobs.isEmpty {
                Button { model.isImporting = true } label: {
                    HStack(spacing: 9) {
                        CanvasGlyph(.plus, size: 17)
                        Text("添加文件")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(CanvasPressStyle())
                .background(CanvasColor.lagoon, in: Capsule())
                .frame(maxWidth: 266)
                .frame(maxWidth: .infinity)
            } else {
                Button {
                    model.queue.isRunning ? model.queue.stop() : model.queue.start()
                } label: {
                    HStack(spacing: 9) {
                        CanvasGlyph(model.queue.isRunning ? .pause : .play, size: 17)
                        Text(model.queue.isRunning ? "完成当前项后停止" : "开始转换")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(CanvasPressStyle())
                .background(CanvasColor.lagoon, in: Capsule())
                .disabled(!model.queue.isRunning && model.queue.waitingCount == 0)
                .opacity(!model.queue.isRunning && model.queue.waitingCount == 0 ? 0.45 : 1)
                .frame(maxWidth: 266)
                .frame(maxWidth: .infinity)

                Button { model.isImporting = true } label: {
                    Text("继续添加文件")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CanvasColor.accent(scheme))
                        .frame(minHeight: 44)
                }
                .buttonStyle(CanvasPressStyle())
            }
        }
    }

    private var outputTitle: String {
        if model.queue.isRunning { return "正在写入…" }
        if model.queue.completedCount > 0 { return "已完成 \(model.queue.completedCount) 项" }
        return "等待转换"
    }

    private var errorPresentation: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

@MainActor
private final class CanvasTranscodeModel: ObservableObject {
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

private struct CanvasTranscodeInputPreview: View {
    let job: TranscodeJob?
    @State private var thumbnail: UIImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let job, !job.probe.hasVideo {
                ZStack {
                    CanvasColor.elevated(scheme)
                    CanvasGlyph(.audio, size: 28)
                        .foregroundStyle(CanvasColor.secondary(scheme))
                }
            } else if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                CanvasFilmPlaceholder(index: placeholderIndex)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: job?.id) {
            thumbnail = nil
            guard let job, job.probe.hasVideo else { return }
            thumbnail = await ThumbnailLoader.image(for: job.inputURL)
        }
        .accessibilityHidden(true)
    }

    private var placeholderIndex: Int {
        guard let job else { return 0 }
        return abs(job.id.hashValue) % 5
    }
}

private struct CanvasTranscodeJobRow: View {
    let job: TranscodeJob
    let availableTargets: [MediaTranscodeTarget]
    let setTarget: (MediaTranscodeTarget) -> Void
    let retry: () -> Void
    let remove: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CanvasGlyph(job.probe.hasVideo ? .video : .audio, size: 20)
                    .foregroundStyle(CanvasColor.accent(scheme))
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
                .foregroundStyle(CanvasColor.ink(scheme))

                Spacer(minLength: 8)

                Menu {
                    ForEach(availableTargets) { target in
                        Button(target.title) { setTarget(target) }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(job.target.title).lineLimit(1)
                        CanvasGlyph(.chevronRight, size: 11).rotationEffect(.degrees(90))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CanvasColor.secondary(scheme))
                    .frame(minHeight: 44)
                }
                .disabled(!canChangeTarget)
            }

            if case .running = job.status {
                ProgressView(value: job.progress)
                    .tint(CanvasColor.accent(scheme))
                    .accessibilityLabel("转换进度")
                    .accessibilityValue("\(Int(job.progress * 100))%")
            }

            HStack {
                Spacer()
                if case let .completed(url) = job.status {
                    ShareLink(item: url) {
                        HStack(spacing: 6) {
                            CanvasGlyph(.export, size: 15)
                            Text("导出")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CanvasColor.accent(scheme))
                        .frame(minHeight: 44)
                    }
                }
                if case .failed = job.status {
                    Button(action: retry) {
                        Text("重试")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CanvasColor.accent(scheme))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(CanvasPressStyle())
                }
                Button(role: .destructive, action: remove) {
                    CanvasGlyph(.trash, size: 16)
                        .foregroundStyle(CanvasColor.danger(scheme))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(CanvasPressStyle())
                .disabled(isRunning)
                .accessibilityLabel("删除 \(job.title)")
            }
        }
        .padding(.vertical, 11)
    }

    private var isRunning: Bool {
        if case .running = job.status { return true }
        return false
    }

    private var canChangeTarget: Bool {
        switch job.status {
        case .waiting, .failed: true
        case .running, .completed: false
        }
    }

    private var statusText: String {
        switch job.status {
        case .waiting: "等待转换"
        case .running: "正在转换 \(Int(job.progress * 100))%"
        case .completed: "已完成"
        case let .failed(message): message
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .completed: CanvasColor.accent(scheme)
        case .failed: CanvasColor.danger(scheme)
        default: CanvasColor.secondary(scheme)
        }
    }
}

// MARK: - Settings

struct CanvasSettingsView: View {
    @AppStorage(CanvasAppearancePreference.storageKey)
    private var appearance = CanvasAppearancePreference.defaultValue
    @AppStorage("screenCodec", store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var codec = "hevc"
    @AppStorage(ScreenRecordingPreferenceKey.resolution, store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var resolution = ScreenResolutionPreset.p1080.rawValue
    @AppStorage(ScreenRecordingPreferenceKey.frameRate, store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var frameRate = 60
    @AppStorage(ScreenRecordingPreferenceKey.orientation, store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var orientation = ScreenOrientationPreset.automatic.rawValue
    @AppStorage(ScreenRecordingPreferenceKey.bitratePreset, store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var bitrate = ScreenBitratePreset.highest.rawValue
    @AppStorage("iCloudSyncEnabledV1") private var iCloudSyncEnabled = false

    @EnvironmentObject private var cloudSync: CloudSyncService
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        CanvasPage(horizontalPadding: 20, topPadding: 4) {
            LazyVStack(alignment: .leading, spacing: 28) {
                Text("设置")
                    .font(.title.weight(.bold))
                    .foregroundStyle(CanvasColor.ink(scheme))
                    .accessibilityAddTraits(.isHeader)

                appearanceSection
                recordingSection
                filesSection
                generalSection

                Text("MonoFrame  \(versionText)")
                    .font(.caption)
                    .foregroundStyle(CanvasColor.tertiary(scheme))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
        .onChange(of: iCloudSyncEnabled) { _, enabled in
            if enabled { Task { await cloudSync.sync() } }
        }
        .accessibilityIdentifier("canvas.settings.page")
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            CanvasSectionLabel("外观")
            HStack(spacing: 0) {
                Text("外观")
                    .font(.body)
                    .foregroundStyle(CanvasColor.ink(scheme))
                Spacer(minLength: 16)
                CanvasGlassSurface(role: .segmented, cornerRadius: 24) {
                    HStack(spacing: 2) {
                        ForEach(CanvasAppearancePreference.options, id: \.value) { option in
                            Button {
                                appearance = option.value
                            } label: {
                                Text(option.title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(
                                        appearance == option.value
                                            ? .white
                                            : CanvasColor.secondary(scheme)
                                    )
                                    .padding(.horizontal, 8)
                                    .frame(
                                        minWidth: option.value == "system" ? 84 : 64,
                                        minHeight: 42
                                    )
                                    .background(
                                        appearance == option.value ? CanvasColor.lagoon : Color.clear,
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(CanvasPressStyle())
                            .accessibilityLabel(option.title)
                            .accessibilityValue(appearance == option.value ? "已选中" : "未选中")
                            .accessibilityAddTraits(appearance == option.value ? .isSelected : [])
                        }
                    }
                    .padding(3)
                }
                .accessibilityIdentifier("canvas.settings.appearance")
            }
            .frame(minHeight: 52)
            CanvasHairline()
        }
    }

    private var recordingSection: some View {
        settingGroup("录制") {
            settingsMenuRow("分辨率", selection: $resolution, values: [
                (ScreenResolutionPreset.p720.rawValue, "720p"),
                (ScreenResolutionPreset.p1080.rawValue, "1080p"),
                (ScreenResolutionPreset.p2K.rawValue, "2K"),
                (ScreenResolutionPreset.native.rawValue, "设备屏幕")
            ])
            CanvasHairline()
            settingsMenuRow("帧率", selection: frameRateBinding, values: [
                ("24", "24 fps"), ("30", "30 fps"), ("60", "60 fps")
            ])
            CanvasHairline()
            settingsMenuRow("编码", selection: $codec, values: [("hevc", "HEVC"), ("h264", "H.264")])
            CanvasHairline()
            settingsMenuRow(
                "方向",
                selection: $orientation,
                values: ScreenOrientationPreset.allCases.map { ($0.rawValue, $0.title) }
            )
            CanvasHairline()
            settingsMenuRow(
                "码率",
                selection: $bitrate,
                values: ScreenBitratePreset.allCases.map { ($0.rawValue, $0.title) }
            )
        }
    }

    private var filesSection: some View {
        settingGroup("文件") {
            CanvasPlainRow("默认保存位置", accessibilityValue: "/MonoFrame") {
                rowValue("/MonoFrame")
            }
            CanvasHairline()
            CanvasPlainRow("文件命名规则", accessibilityValue: "日期时间") {
                rowValue("日期时间")
            }
            CanvasHairline()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Drive")
                    Text(cloudSync.statusText)
                        .font(.caption)
                        .foregroundStyle(CanvasColor.secondary(scheme))
                }
                Spacer()
                Toggle("iCloud Drive", isOn: $iCloudSyncEnabled).labelsHidden()
            }
            .frame(minHeight: 54)
        }
    }

    private var generalSection: some View {
        settingGroup("通用") {
            ForEach(Array(legalDocuments.enumerated()), id: \.element.id) { index, document in
                NavigationLink {
                    CanvasLegalDocumentView(document: document)
                } label: {
                    CanvasPlainRow(document.title) { rowValue("") }
                }
                .buttonStyle(CanvasPressStyle())
                if index < legalDocuments.count - 1 { CanvasHairline() }
            }
        }
    }

    private func settingGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            CanvasSectionLabel(title)
            VStack(spacing: 0) { content() }
        }
    }

    private func settingsMenuRow(
        _ title: String,
        selection: Binding<String>,
        values: [(String, String)]
    ) -> some View {
        Menu {
            ForEach(values, id: \.0) { value, label in
                Button(label) { selection.wrappedValue = value }
            }
        } label: {
            CanvasPlainRow(title, accessibilityValue: values.first(where: { $0.0 == selection.wrappedValue })?.1) {
                rowValue(values.first(where: { $0.0 == selection.wrappedValue })?.1 ?? "—")
            }
        }
        .buttonStyle(CanvasPressStyle())
    }

    private func rowValue(_ text: String) -> some View {
        HStack(spacing: 6) {
            if !text.isEmpty {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(CanvasColor.tertiary(scheme))
                    .lineLimit(1)
            }
            CanvasGlyph(.chevronRight, size: 12)
                .foregroundStyle(CanvasColor.tertiary(scheme))
        }
    }

    private var frameRateBinding: Binding<String> {
        Binding(
            get: { String(frameRate) },
            set: { frameRate = ScreenFrameRateLimit.clamp(Int($0) ?? 60) }
        )
    }

    private var legalDocuments: [LegalDocument] {
        [.privacyRights, .userAgreement, .disclaimer, .ffmpeg]
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}
