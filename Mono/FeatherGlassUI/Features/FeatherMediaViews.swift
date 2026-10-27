import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Studio

struct FeatherStudioView: View {
    @StateObject private var model = FeatherStudioViewModel()
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FeatherPage {
            VStack(alignment: .leading, spacing: 28) {
                mediaKindSelector
                importStage
                librarySummary
            }
        }
        .featherNavigationTitle("编辑")
        .accessibilityIdentifier("feather.studio")
        .fileImporter(
            isPresented: $model.isImporting,
            allowedContentTypes: model.kind.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            Task { await model.importMedia(result, library: library) }
        }
        .navigationDestination(isPresented: videoDestination) {
            if let recording = model.importedVideo {
                FeatherVideoEditorView(recording: recording)
            }
        }
        .navigationDestination(isPresented: audioDestination) {
            if let recording = model.importedAudio {
                FeatherAudioEditorView(recording: recording)
            }
        }
        .alert("无法导入素材", isPresented: errorPresentation) {
            Button("好", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "请稍后重试")
        }
    }

    private var mediaKindSelector: some View {
        HStack(spacing: 4) {
            ForEach(FeatherStudioViewModel.MediaKind.allCases) { kind in
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { model.kind = kind }
                } label: {
                    HStack(spacing: 8) {
                        FeatherIcon(name: kind.icon, size: 17)
                        Text(kind.title)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(model.kind == kind ? .white : FeatherColor.ink(scheme))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        model.kind == kind ? FeatherColor.lagoon : Color.clear,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(FeatherPressStyle())
                .accessibilityIdentifier("feather.studio.kind.\(kind.rawValue)")
                .accessibilityAddTraits(model.kind == kind ? .isSelected : [])
            }
        }
        .padding(4)
        .background(FeatherColor.raised(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("素材类型")
    }

    private var importStage: some View {
        Button { model.isImporting = true } label: {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(FeatherColor.lagoonWash(scheme))
                        .frame(width: 72, height: 72)
                    FeatherIcon(name: model.kind.icon, size: 30)
                }

                VStack(spacing: 6) {
                    Text(model.kind == .video ? "选择要编辑的视频" : "选择要编辑的音频")
                        .font(.title3.weight(.semibold))
                    Text(model.kind.supportedFormats)
                        .font(.subheadline)
                        .foregroundStyle(FeatherColor.secondary(scheme))
                }

                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.bold))
                    Text("从文件中选择")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(FeatherColor.accent(scheme))
                .frame(minHeight: 44)
            }
            .foregroundStyle(FeatherColor.ink(scheme))
            .frame(maxWidth: .infinity, minHeight: 268)
            .padding(24)
            .contentShape(Rectangle())
        }
        .buttonStyle(FeatherPressStyle())
        .background(FeatherColor.surface(scheme), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(FeatherColor.rule(scheme), style: StrokeStyle(lineWidth: 1, dash: [7, 7]))
        }
        .accessibilityIdentifier("feather.studio.import")
        .accessibilityHint("打开系统文件选择器")
    }

    private var librarySummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeatherSectionHeader("已有作品")
            FeatherSurface {
                HStack(spacing: 14) {
                    FeatherIcon(name: "rectangle.stack", size: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("也可以从作品页继续编辑")
                            .font(.body.weight(.medium))
                        Text("\(library.recordings.count) 个视频 · \(library.audioRecordings.count) 个音频")
                            .font(.subheadline)
                            .foregroundStyle(FeatherColor.secondary(scheme))
                    }
                    Spacer(minLength: 12)
                }
                .foregroundStyle(FeatherColor.ink(scheme))
                .padding(16)
                .frame(minHeight: 72)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feather.studio.librarySummary")
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
            set: { if !$0 { model.dismissError() } }
        )
    }
}

@MainActor
private final class FeatherStudioViewModel: ObservableObject {
    enum MediaKind: String, CaseIterable, Identifiable {
        case video
        case audio

        var id: String { rawValue }
        var title: String { self == .video ? "视频" : "音频" }
        var icon: String { self == .video ? "film" : "waveform" }
        var supportedFormats: String { self == .video ? "MOV、MP4" : "M4A、WAV、MP3、FLAC" }
        var allowedContentTypes: [UTType] { self == .video ? [.movie] : [.audio] }
    }

    @Published var kind: MediaKind = .video
    @Published var isImporting = false
    @Published var importedVideo: Recording?
    @Published var importedAudio: AudioRecording?
    @Published private(set) var errorMessage: String?

    func importMedia(_ result: Result<[URL], Error>, library: RecordingLibrary) async {
        do {
            guard let source = try result.get().first else { return }
            let imported = try await stage(source: source, kind: kind)
            switch imported {
            case let .video(recording): importedVideo = recording
            case let .audio(recording): importedAudio = recording
            }
            await library.reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() { errorMessage = nil }

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

// MARK: - Library

struct FeatherLibraryView: View {
    @StateObject private var model = FeatherLibraryViewModel()
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FeatherPage {
            VStack(alignment: .leading, spacing: 22) {
                searchBar
                filterSelector
                libraryContent
            }
        }
        .featherNavigationTitle("作品")
        .accessibilityIdentifier("feather.library")
        .refreshable { await library.reload() }
        .task {
            if library.recordings.isEmpty && library.audioRecordings.isEmpty {
                await library.reload()
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            FeatherGlassControl(cornerRadius: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(FeatherColor.secondary(scheme))
                    TextField("搜索文件", text: $model.query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !model.query.isEmpty {
                        Button { model.query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(FeatherColor.secondary(scheme))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(FeatherPressStyle())
                        .accessibilityLabel("清除搜索")
                        .accessibilityIdentifier("feather.library.search.clear")
                    }
                }
                .padding(.leading, 15)
                .padding(.trailing, model.query.isEmpty ? 15 : 2)
                .frame(minHeight: 50)
            }
            .accessibilityIdentifier("feather.library.search")

            Button { Task { await library.reload() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FeatherColor.ink(scheme))
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(FeatherPressStyle())
            .background(FeatherColor.surface(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("刷新作品")
            .accessibilityIdentifier("feather.library.reload")
        }
    }

    private var filterSelector: some View {
        HStack(spacing: 4) {
            filterButton(.video, count: library.recordings.count)
            filterButton(.audio, count: library.audioRecordings.count)
        }
        .padding(4)
        .background(FeatherColor.raised(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func filterButton(_ filter: FeatherLibraryViewModel.Filter, count: Int) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { model.filter = filter }
        } label: {
            HStack(spacing: 7) {
                Text(filter.title)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.filter == filter ? .white : FeatherColor.secondary(scheme))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(model.filter == filter ? .white : FeatherColor.ink(scheme))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                model.filter == filter ? FeatherColor.lagoon : Color.clear,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(FeatherPressStyle())
        .accessibilityIdentifier("feather.library.filter.\(filter.rawValue)")
        .accessibilityAddTraits(model.filter == filter ? .isSelected : [])
    }

    @ViewBuilder private var libraryContent: some View {
        if library.isLoading && library.recordings.isEmpty && library.audioRecordings.isEmpty {
            FeatherSurface {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在载入作品")
                        .font(.subheadline)
                        .foregroundStyle(FeatherColor.secondary(scheme))
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            }
            .accessibilityIdentifier("feather.library.loading")
        } else if model.filter == .video {
            let recordings = model.filteredVideos(in: library)
            if recordings.isEmpty {
                FeatherSurface {
                    FeatherEmptyState(
                        icon: "rectangle.stack",
                        title: model.query.isEmpty ? "还没有视频" : "没有找到视频",
                        detail: model.query.isEmpty ? "完成录屏或导入视频后，会显示在这里。" : "试试其他文件名。"
                    )
                }
                .accessibilityIdentifier("feather.library.empty.video")
            } else {
                videoList(recordings)
            }
        } else {
            let recordings = model.filteredAudio(in: library)
            if recordings.isEmpty {
                FeatherSurface {
                    FeatherEmptyState(
                        icon: "waveform",
                        title: model.query.isEmpty ? "还没有音频" : "没有找到音频",
                        detail: model.query.isEmpty ? "完成录音或导入音频后，会显示在这里。" : "试试其他文件名。"
                    )
                }
                .accessibilityIdentifier("feather.library.empty.audio")
            } else {
                audioList(recordings)
            }
        }
    }

    private func videoList(_ recordings: [Recording]) -> some View {
        FeatherSurface {
            LazyVStack(spacing: 0) {
                ForEach(Array(recordings.enumerated()), id: \.element.id) { index, recording in
                    FeatherVideoLibraryRow(recording: recording) { library.delete(recording) }
                    if index < recordings.count - 1 { FeatherRule().padding(.leading, 126) }
                }
            }
        }
        .accessibilityIdentifier("feather.library.videoList")
    }

    private func audioList(_ recordings: [AudioRecording]) -> some View {
        FeatherSurface {
            LazyVStack(spacing: 0) {
                ForEach(Array(recordings.enumerated()), id: \.element.id) { index, recording in
                    FeatherAudioLibraryRow(recording: recording) { library.delete(recording) }
                    if index < recordings.count - 1 { FeatherRule().padding(.leading, 86) }
                }
            }
        }
        .accessibilityIdentifier("feather.library.audioList")
    }
}

@MainActor
private final class FeatherLibraryViewModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case video
        case audio

        var id: String { rawValue }
        var title: String { self == .video ? "视频" : "音频" }
    }

    @Published var filter: Filter = .video
    @Published var query = ""

    func filteredVideos(in library: RecordingLibrary) -> [Recording] {
        guard !query.isEmpty else { return library.recordings }
        return library.recordings.filter { recording in
            recording.title.localizedCaseInsensitiveContains(query)
                || recording.url.lastPathComponent.localizedCaseInsensitiveContains(query)
        }
    }

    func filteredAudio(in library: RecordingLibrary) -> [AudioRecording] {
        guard !query.isEmpty else { return library.audioRecordings }
        return library.audioRecordings.filter { recording in
            recording.title.localizedCaseInsensitiveContains(query)
                || recording.url.lastPathComponent.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct FeatherVideoLibraryRow: View {
    let recording: Recording
    let onDelete: () -> Void
    @State private var thumbnail: UIImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink(value: recording) {
                HStack(spacing: 14) {
                    thumbnailView
                    VStack(alignment: .leading, spacing: 5) {
                        Text(recording.title)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text("\(recording.durationText) · \(recording.url.pathExtension.uppercased()) · \(recording.sizeText)")
                            .font(.caption)
                            .foregroundStyle(FeatherColor.secondary(scheme))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FeatherColor.secondary(scheme))
                }
                .foregroundStyle(FeatherColor.ink(scheme))
                .contentShape(Rectangle())
            }
            .buttonStyle(FeatherPressStyle())
            .accessibilityIdentifier("feather.library.video.\(recording.id.uuidString)")

            itemMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(minHeight: 92)
        .task(id: recording.url) { thumbnail = await ThumbnailLoader.image(for: recording.url) }
    }

    private var thumbnailView: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFill()
            } else {
                FeatherColor.raised(scheme)
                    .overlay { FeatherIcon(name: "film", size: 24) }
            }
        }
        .frame(width: 100, height: 66)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    private var itemMenu: some View {
        Menu {
            ShareLink(item: recording.url) { Label("分享文件", systemImage: "square.and.arrow.up") }
            Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(FeatherColor.secondary(scheme))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("更多操作")
        .accessibilityIdentifier("feather.library.video.menu.\(recording.id.uuidString)")
    }
}

private struct FeatherAudioLibraryRow: View {
    let recording: AudioRecording
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink(value: recording) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(FeatherColor.lagoonWash(scheme))
                        FeatherIcon(name: "waveform", size: 24)
                    }
                    .frame(width: 60, height: 60)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(recording.title)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text("\(recording.durationText) · \(recording.formatText) · \(recording.sizeText)")
                            .font(.caption)
                            .foregroundStyle(FeatherColor.secondary(scheme))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FeatherColor.secondary(scheme))
                }
                .foregroundStyle(FeatherColor.ink(scheme))
                .contentShape(Rectangle())
            }
            .buttonStyle(FeatherPressStyle())
            .accessibilityIdentifier("feather.library.audio.\(recording.id.uuidString)")

            Menu {
                ShareLink(item: recording.url) { Label("分享文件", systemImage: "square.and.arrow.up") }
                Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FeatherColor.secondary(scheme))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("更多操作")
            .accessibilityIdentifier("feather.library.audio.menu.\(recording.id.uuidString)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 82)
    }
}

// MARK: - Transcode

struct FeatherTranscodeView: View {
    @StateObject private var model = FeatherTranscodeViewModel()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FeatherPage {
            VStack(alignment: .leading, spacing: 24) {
                summary
                addFilesButton
                jobSection
                runButton
            }
        }
        .featherNavigationTitle("转码")
        .accessibilityIdentifier("feather.transcode")
        .fileImporter(
            isPresented: $model.isImporting,
            allowedContentTypes: [.movie, .audio, .data],
            allowsMultipleSelection: true
        ) { result in
            Task { await model.receive(result) }
        }
        .alert("无法加入任务", isPresented: errorPresentation) {
            Button("好", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "请稍后重试")
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.queue.isRunning ? "正在转换" : "任务队列")
                        .font(.title3.weight(.semibold))
                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(FeatherColor.secondary(scheme))
                }
                Spacer(minLength: 12)
                Text("\(Int(model.queue.overallProgress * 100))%")
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }

            ProgressView(value: model.queue.overallProgress)
                .tint(FeatherColor.accent(scheme))

            if model.queue.completedCount > 0 || model.queue.failedCount > 0 {
                Button("清理已结束任务") { model.queue.clearFinished() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FeatherColor.danger(scheme))
                    .frame(minHeight: 44, alignment: .leading)
                    .buttonStyle(FeatherPressStyle())
                    .accessibilityIdentifier("feather.transcode.clearFinished")
            }
        }
        .padding(18)
        .background(FeatherColor.surface(scheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feather.transcode.summary")
    }

    private var addFilesButton: some View {
        Button { model.isImporting = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(FeatherColor.lagoonWash(scheme)).frame(width: 44, height: 44)
                    Image(systemName: "plus").font(.body.weight(.bold)).foregroundStyle(FeatherColor.accent(scheme))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("添加文件").font(.body.weight(.semibold))
                    Text("支持批量选择视频和音频")
                        .font(.caption)
                        .foregroundStyle(FeatherColor.secondary(scheme))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FeatherColor.secondary(scheme))
            }
            .foregroundStyle(FeatherColor.ink(scheme))
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(FeatherPressStyle())
        .background(FeatherColor.surface(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("feather.transcode.import")
        .accessibilityHint("打开系统文件选择器")
    }

    @ViewBuilder private var jobSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeatherSectionHeader("文件", detail: model.queue.jobs.isEmpty ? nil : "\(model.queue.jobs.count) 项")
            if model.queue.jobs.isEmpty {
                FeatherSurface {
                    FeatherEmptyState(
                        icon: "arrow.triangle.2.circlepath",
                        title: "还没有转码任务",
                        detail: "添加文件后选择输出格式，再开始转换。",
                        actionTitle: "添加文件",
                        action: { model.isImporting = true }
                    )
                }
                .accessibilityIdentifier("feather.transcode.empty")
            } else {
                FeatherSurface {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.queue.jobs.enumerated()), id: \.element.id) { index, job in
                            FeatherTranscodeJobRow(
                                job: job,
                                availableTargets: model.queue.availableTargets(for: job.probe),
                                setTarget: { model.queue.setTarget($0, for: job.id) },
                                retry: { model.queue.retry(job.id) },
                                remove: { model.queue.remove(job.id) }
                            )
                            if index < model.queue.jobs.count - 1 { FeatherRule().padding(.leading, 70) }
                        }
                    }
                }
                .accessibilityIdentifier("feather.transcode.jobList")
            }
        }
    }

    private var runButton: some View {
        FeatherPrimaryButton(
            title: model.queue.isRunning ? "完成当前项后停止" : "开始转换",
            icon: model.queue.isRunning ? "pause" : "play",
            isEnabled: model.queue.isRunning || model.queue.waitingCount > 0
        ) {
            model.queue.isRunning ? model.queue.stop() : model.queue.start()
        }
        .accessibilityIdentifier("feather.transcode.startStop")
    }

    private var summaryText: String {
        if model.queue.jobs.isEmpty { return "添加文件开始转换" }
        return "完成 \(model.queue.completedCount) · 等待 \(model.queue.waitingCount) · 失败 \(model.queue.failedCount)"
    }

    private var errorPresentation: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.dismissError() } }
        )
    }
}

@MainActor
private final class FeatherTranscodeViewModel: ObservableObject {
    @Published var isImporting = false
    @Published private(set) var errorMessage: String?
    let queue: TranscodeQueue
    private var queueObserver: AnyCancellable?

    init() {
        let queue = TranscodeQueue()
        self.queue = queue
        queueObserver = queue.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
    }

    func receive(_ result: Result<[URL], Error>) async {
        var staged: [(URL, MediaProbe)] = []
        do {
            let sources = try result.get()
            for source in sources {
                staged.append(try await stage(source: source))
            }
            try queue.add(files: staged)
        } catch {
            for (url, _) in staged { try? FileManager.default.removeItem(at: url) }
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() { errorMessage = nil }

    private func stage(source: URL) async throws -> (URL, MediaProbe) {
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

private struct FeatherTranscodeJobRow: View {
    let job: TranscodeJob
    let availableTargets: [MediaTranscodeTarget]
    let setTarget: (MediaTranscodeTarget) -> Void
    let retry: () -> Void
    let remove: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(job.probe.hasVideo ? FeatherColor.lagoonWash(scheme) : FeatherColor.coralWash(scheme))
                    FeatherIcon(name: job.probe.hasVideo ? "film" : "waveform", size: 22)
                }
                .frame(width: 46, height: 46)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(FeatherColor.secondary(scheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                statusBadge
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(availableTargets) { target in
                        Button {
                            setTarget(target)
                        } label: {
                            if target == job.target { Label(target.title, systemImage: "checkmark") }
                            else { Text(target.title) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(job.target.title).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FeatherColor.ink(scheme))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(FeatherColor.raised(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(!canChangeTarget)
                .accessibilityLabel("输出格式")
                .accessibilityValue(job.target.title)
                .accessibilityIdentifier("feather.transcode.target.\(job.id.uuidString)")

                Spacer(minLength: 0)

                if case let .completed(outputURL) = job.status {
                    ShareLink(item: outputURL) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(FeatherColor.lagoon, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .accessibilityLabel("导出 \(job.title)")
                    .accessibilityIdentifier("feather.transcode.export.\(job.id.uuidString)")
                }

                if case .failed = job.status {
                    Button(action: retry) {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(FeatherColor.accent(scheme))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(FeatherPressStyle())
                    .accessibilityLabel("重试 \(job.title)")
                    .accessibilityIdentifier("feather.transcode.retry.\(job.id.uuidString)")
                }

                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(FeatherColor.danger(scheme))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(FeatherPressStyle())
                .disabled(isRunning)
                .accessibilityLabel("删除 \(job.title)")
                .accessibilityIdentifier("feather.transcode.delete.\(job.id.uuidString)")
            }

            if isRunning {
                ProgressView(value: job.progress)
                    .tint(FeatherColor.accent(scheme))
                    .accessibilityLabel("转换进度")
                    .accessibilityValue("\(Int(job.progress * 100))%")
            }

            if case let .failed(message) = job.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(FeatherColor.danger(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .foregroundStyle(FeatherColor.ink(scheme))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feather.transcode.job.\(job.id.uuidString)")
    }

    @ViewBuilder private var statusBadge: some View {
        switch job.status {
        case .waiting:
            badge("等待", color: FeatherColor.secondary(scheme))
        case .running:
            badge("\(Int(job.progress * 100))%", color: FeatherColor.accent(scheme))
        case .completed:
            badge("完成", color: FeatherColor.successInk(scheme))
        case .failed:
            badge("失败", color: FeatherColor.danger(scheme))
        }
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .background(color.opacity(scheme == .dark ? 0.20 : 0.11), in: Capsule())
    }

    private var detail: String {
        let kind = job.probe.hasVideo ? "视频" : "音频"
        let codec = (job.probe.videoCodec ?? job.probe.audioCodec ?? "未知编码").uppercased()
        let seconds = max(0, Int(job.probe.duration.rounded()))
        return "\(kind) · \(codec) · \(String(format: "%02d:%02d", seconds / 60, seconds % 60))"
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
}
