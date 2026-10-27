import FFmpegSwiftSDK
import SwiftUI
import UniformTypeIdentifiers

enum PearlMediaItem: Hashable, Identifiable {
    case video(Recording), audio(AudioRecording)
    var id: URL { url }
    var url: URL { switch self { case .video(let r): r.url; case .audio(let r): r.url } }
    var title: String { switch self { case .video(let r): r.title; case .audio(let r): r.title } }
    var createdAt: Date { switch self { case .video(let r): r.createdAt; case .audio(let r): r.createdAt } }
    var duration: String { switch self { case .video(let r): r.durationText; case .audio(let r): r.durationText } }
    var size: String { switch self { case .video(let r): r.sizeText; case .audio(let r): r.sizeText } }
    var isVideo: Bool { if case .video = self { return true }; return false }
}

struct PearlThumbnail: View {
    let url: URL
    var isVideo = true
    @State private var image: UIImage?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PearlColor.elevated(scheme)
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { PearlGlyph(isVideo ? .video : .audio, size: 30).foregroundStyle(PearlColor.accent(scheme)) }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .task(id: url) { image = nil; if isVideo { image = await ThumbnailLoader.image(for: url) } }
        .accessibilityHidden(true)
    }
}

struct PearlWaveform: View {
    let samples: [Float]
    var progress: Double? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { context, size in
            let count = min(80, max(2, Int(size.width / 5)))
            for i in 0..<count {
                let sample = samples.isEmpty ? 0 : samples[min(samples.count - 1, i * samples.count / count)]
                let h = max(2, CGFloat(min(1, abs(sample))) * size.height * 0.9)
                let x = (CGFloat(i) + 0.5) * size.width / CGFloat(count)
                let active = progress == nil || Double(i) / Double(count) <= (progress ?? 0)
                let path = Path(roundedRect: CGRect(x: x - 1.25, y: (size.height - h) / 2, width: 2.5, height: h), cornerRadius: 1.25)
                context.fill(path, with: .color(PearlColor.accent(scheme).opacity(active ? 0.95 : 0.27)))
            }
        }.accessibilityHidden(true)
    }
}

struct PearlFileWaveform: View {
    let url: URL
    @State private var samples: [Float] = []
    var body: some View {
        PearlWaveform(samples: samples).task(id: url) {
            samples = []
            if let values = try? await WaveformGenerator().generate(url: url.path, samplesCount: 72, maxDuration: 20) {
                guard !Task.isCancelled else { return }
                samples = values.map { max(abs($0.positive), abs($0.negative)) }
            }
        }
    }
}

struct PearlMediaRow: View {
    let item: PearlMediaItem
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 14) {
            NavigationLink(value: item) {
                HStack(spacing: 14) {
                    PearlThumbnail(url: item.url, isVideo: item.isVideo).frame(width: 66, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.title).font(.headline).foregroundStyle(PearlColor.ink(scheme)).lineLimit(2)
                        Text("\(item.duration) · \(item.size)").font(.caption).foregroundStyle(PearlColor.secondary(scheme))
                        PearlFileWaveform(url: item.url).frame(height: 27)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.buttonStyle(PearlPressStyle())
                .accessibilityLabel("编辑\(item.isVideo ? "视频" : "音频")，\(item.title)，\(item.duration)")
            PearlMediaMenu(item: item)
        }.padding(.vertical, 14)
            .overlay(alignment: .bottom) { PearlHairline() }
    }
}

struct PearlMediaMenu: View {
    let item: PearlMediaItem
    @State private var export: PearlExportItem?
    @State private var deleting = false
    @State private var isMakingLivePhoto = false
    @State private var livePhotoItem: PearlExportItem?
    @State private var message: String?
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Menu {
            Button { export = PearlExportItem(url: item.url) } label: { menuLabel("导出文件", .export) }
            ShareLink(item: item.url) { menuLabel("分享", .share) }
            if item.isVideo {
                Button(action: makeLivePhoto) {
                    Label("转为 Live Photo", systemImage: "livephoto")
                }
                .accessibilityIdentifier("pearl.media.livePhoto")
                Button {
                    Task {
                        do { _ = try await library.saveVideoToPhotos(item.url); message = "视频已保存到相册。" }
                        catch { message = "保存失败：\(error.localizedDescription)" }
                    }
                } label: { menuLabel("保存到相册", .download) }
            }
            Button(role: .destructive) { deleting = true } label: { menuLabel("删除", .trash) }
        } label: {
            Group {
                if isMakingLivePhoto { ProgressView().tint(PearlColor.accent(scheme)) }
                else { PearlGlyph(.more, size: 19).foregroundStyle(PearlColor.ink(scheme)) }
            }
            .frame(width: 44, height: 44)
            .background(PearlColor.surface(scheme).opacity(0.86), in: Circle())
        }
        .disabled(isMakingLivePhoto)
        .accessibilityLabel(isMakingLivePhoto ? "正在制作 Live Photo" : "\(item.title) 的更多操作")
        .accessibilityIdentifier("pearl.media.more.\(item.isVideo ? "video" : "audio")")
        .confirmationDialog("删除这份素材？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除素材", role: .destructive) {
                switch item { case .video(let r): library.delete(r); case .audio(let r): library.delete(r) }
            }
        } message: { Text("此操作将删除 App 内的文件。") }
        .sheet(item: $livePhotoItem) { PearlLivePhotoEditor(url: $0.url) }
        .sheet(item: $export) { PearlFileExporter(url: $0.url) }
        .alert("保存结果", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }
    private func makeLivePhoto() {
        livePhotoItem = PearlExportItem(url: item.url)
    }

    private func menuLabel(_ title: String, _ glyph: PearlGlyphName) -> some View { Label { Text(title) } icon: { PearlGlyph(glyph) } }
}

struct PearlLibraryView: View {
    @StateObject private var importer = PearlImportModel()
    @State private var filter = 0
    @State private var query = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var items: [PearlMediaItem] {
        (library.recordings.map(PearlMediaItem.video) + library.audioRecordings.map(PearlMediaItem.audio))
            .filter { filter == 0 || (filter == 1 ? $0.isVideo : !$0.isVideo) }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        PearlPage {
            VStack(alignment: .leading, spacing: 18) {
                PearlRootHeader(title: "素材") {
                    HStack(spacing: 5) {
                        PearlIconButton(title: "搜索素材", glyph: .search) { searching.toggle(); searchFocused = searching }
                        Menu {
                            Button("导入视频") { importer.beginImport(.video) }
                            Button("导入音频") { importer.beginImport(.audio) }
                        } label: { PearlGlyph(.plus).frame(width: 44, height: 44) }
                            .accessibilityLabel("导入素材").accessibilityIdentifier("pearl.library.import")
                    }
                }
                PearlCountHeading(count: items.count, label: "份素材")
                if searching {
                    HStack {
                        PearlGlyph(.search, size: 18)
                        TextField("搜索文件名", text: $query).focused($searchFocused).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("pearl.library.search")
                        if !query.isEmpty { PearlIconButton(title: "清除搜索", glyph: .close) { query = "" } }
                    }.padding(.leading, 14).frame(minHeight: 48).background(PearlColor.surface(scheme), in: RoundedRectangle(cornerRadius: 16))
                }
                filterStrip
                if library.isLoading && items.isEmpty { ProgressView("正在读取素材").frame(maxWidth: .infinity).padding(50) }
                else if items.isEmpty {
                    PearlEmptyState(glyph: .library, title: query.isEmpty ? "还没有素材" : "没有找到素材", message: query.isEmpty ? "导入视频或音频，开始整理与剪辑。" : "换一个文件名试试。")
                    if query.isEmpty {
                        Button { importer.beginImport(.video) } label: { PearlPrimaryLabel(title: "导入视频", glyph: .plus) }
                            .buttonStyle(PearlPressStyle())
                    }
                } else {
                    ForEach(groupedDays, id: \.self) { day in
                        Text(Calendar.current.isDateInToday(day) ? "今天" : day.formatted(.dateTime.month(.twoDigits).day(.twoDigits))).font(.headline).padding(.top, 5)
                        mediaGroup(items.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: day) })
                    }
                }
            }
        }
        .refreshable { await library.reload() }
        .modifier(PearlImportPresentation(model: importer, opensEditor: false))

    }
    private var groupedDays: [Date] { Array(Set(items.map { Calendar.current.startOfDay(for: $0.createdAt) })).sorted(by: >) }
    private var filterStrip: some View {
        HStack(spacing: 25) {
            ForEach(Array(["全部", "视频", "音频"].enumerated()), id: \.offset) { index, title in
                Button { filter = index } label: {
                    Text(title).font(.subheadline.weight(filter == index ? .semibold : .regular))
                        .foregroundStyle(filter == index ? PearlColor.accent(scheme) : PearlColor.secondary(scheme))
                        .frame(minWidth: 44, minHeight: 44)
                        .overlay(alignment: .bottom) { if filter == index { Capsule().fill(PearlColor.accent(scheme)).frame(height: 2) } }
                }.buttonStyle(PearlPressStyle()).accessibilityAddTraits(filter == index ? .isSelected : [])
                    .accessibilityIdentifier("pearl.library.filter.\(index)")
            }
            Spacer(minLength: 0)
        }.overlay(alignment: .bottom) { PearlHairline().zIndex(-1) }
    }
    @ViewBuilder private func mediaGroup(_ group: [PearlMediaItem]) -> some View {
        let videos = group.filter(\.isVideo)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 280 : 150), spacing: 16)], spacing: 22) {
            ForEach(videos) { videoTile($0) }
        }
        ForEach(group.filter { !$0.isVideo }) { PearlMediaRow(item: $0) }
    }
    private func videoTile(_ item: PearlMediaItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: item) {
                PearlThumbnail(url: item.url).aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottomLeading) {
                        Text(item.duration).font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.white).padding(7).background(.black.opacity(0.7), in: Capsule()).padding(8)
                    }
            }.buttonStyle(PearlPressStyle()).accessibilityLabel("编辑视频，\(item.title)，\(item.duration)")
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(item.size).font(.caption).foregroundStyle(PearlColor.secondary(scheme))
                }.frame(maxWidth: .infinity, alignment: .leading)
                PearlMediaMenu(item: item)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pearl.library.video")
    }
}

struct PearlStudioView: View {
    @StateObject private var model = PearlImportModel()
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var recent: [PearlMediaItem] {
        (library.recordings.map(PearlMediaItem.video) + library.audioRecordings.map(PearlMediaItem.audio)).sorted { $0.createdAt > $1.createdAt }
    }
    var body: some View {
        PearlPage {
            VStack(alignment: .leading, spacing: 24) {
                PearlRootHeader(title: "剪辑", brand: true) { PearlSettingsLink() }
                Text("从一份素材开始").font(.title.weight(.bold))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { importButton(.video); importButton(.audio) }
                    VStack(spacing: 16) { importButton(.video); importButton(.audio) }
                }
                HStack {
                    Text("最近素材").font(.title3.weight(.bold))
                    Spacer()
                    Text("\(recent.count) 份").font(.subheadline).foregroundStyle(PearlColor.secondary(scheme))
                }.padding(.top, 12)
                PearlHairline()
                if recent.isEmpty {
                    PearlEmptyState(glyph: .edit, title: "还没有可编辑的素材", message: "从上方导入视频或音频。")
                } else {
                    LazyVStack(spacing: 0) { ForEach(recent.prefix(8)) { PearlMediaRow(item: $0) } }
                }
            }
        }.modifier(PearlImportPresentation(model: model))
    }
    private func importButton(_ kind: PearlImportModel.MediaKind) -> some View {
        let video = kind == .video
        return Button { model.beginImport(kind) } label: {
            VStack(alignment: .leading, spacing: 30) {
                PearlGlyph(video ? .video : .audio, size: 28)
                    .foregroundStyle(video ? PearlColor.onAccent(scheme) : PearlColor.background(scheme))
                    .frame(width: 62, height: 62)
                    .background(video ? PearlColor.action(scheme) : PearlColor.ink(scheme), in: Circle())
                HStack {
                    Text(video ? "导入视频" : "导入音频").font(.headline).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    PearlGlyph(.plus, size: 20)
                }
            }.foregroundStyle(PearlColor.ink(scheme))
                .padding(20).frame(minWidth: typeSize.isAccessibilitySize ? 240 : 140, maxWidth: .infinity, alignment: .leading)
                .background(PearlColor.surface(scheme), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(PearlPressStyle()).accessibilityIdentifier(video ? "pearl.studio.new" : "pearl.studio.newAudio")
    }
}

struct PearlImportPresentation: ViewModifier {
    @ObservedObject var model: PearlImportModel
    var opensEditor = true
    @EnvironmentObject private var library: RecordingLibrary
    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $model.isImporting, allowedContentTypes: model.pendingKind.allowedContentTypes, allowsMultipleSelection: false) { result in
            Task {
                await model.importMedia(result, library: library)
                if !opensEditor { model.importedVideo = nil; model.importedAudio = nil }
            }
        }
        .navigationDestination(isPresented: Binding(get: { opensEditor && model.importedVideo != nil }, set: { if !$0 { model.importedVideo = nil } })) {
            if let recording = model.importedVideo { PearlVideoEditorView(recording: recording) }
        }
        .navigationDestination(isPresented: Binding(get: { opensEditor && model.importedAudio != nil }, set: { if !$0 { model.importedAudio = nil } })) {
            if let recording = model.importedAudio { PearlAudioEditorView(recording: recording) }
        }
        .alert("无法导入素材", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "请重新选择文件。") }
    }
}
