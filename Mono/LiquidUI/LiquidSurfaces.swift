import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct LiquidStudioSurface: View {
    enum Kind: String, CaseIterable { case video = "视频"; case audio = "音频" }
    @State private var kind: Kind = .video
    @State private var importing = false
    @State private var video: Recording?
    @State private var audio: AudioRecording?
    @EnvironmentObject private var library: RecordingLibrary

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LiquidTitle(eyebrow: "CREATE", title: "创作流", detail: "从一段素材，进入完整时间线")
                HStack(spacing: 7) {
                    ForEach(Kind.allCases, id: \.self) { item in
                        Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { kind = item } } label: {
                            Label(item.rawValue, systemImage: item == .video ? "film.stack" : "waveform")
                                .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(kind == item ? .white : .primary)
                                .glassEffect(.regular.tint(kind == item ? LiquidPalette.indigo : .clear).interactive(), in: .capsule)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(6).glassEffect(.regular, in: .capsule)

                Button { importing = true } label: {
                    ZStack(alignment: .bottomTrailing) {
                        timeline
                        VStack(alignment: .leading, spacing: 7) {
                            Text("NEW PROJECT").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(LiquidPalette.indigo)
                            Text(kind == .video ? "建立一条新时间线" : "建立一个声音空间")
                                .font(.system(size: 27, weight: .bold, design: .rounded)).tracking(-0.7)
                            Text(kind == .video ? "逐帧 · 多轨 · 字幕 · 调色" : "剪辑 · 混音 · 歌词 · 人声")
                                .font(.caption.bold()).foregroundStyle(.secondary)
                            Spacer()
                        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.white)
                            .frame(width: 62, height: 62)
                            .glassEffect(.regular.tint(LiquidPalette.indigo).interactive(), in: .circle)
                    }
                    .padding(22).frame(maxWidth: .infinity, minHeight: 280)
                    .glassEffect(.regular.tint(LiquidPalette.indigo.opacity(0.08)).interactive(), in: .rect(cornerRadius: 40))
                }.buttonStyle(.plain).foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 12) {
                    Text("继续创作").font(.title3.bold())
                    if kind == .video {
                        ForEach(library.recordings.prefix(4)) { item in
                            NavigationLink(value: item) { recent(item.title, item.durationText, "film") }.buttonStyle(.plain)
                        }
                    } else {
                        ForEach(library.audioRecordings.prefix(4)) { item in
                            NavigationLink(value: item) { recent(item.title, item.durationText, "waveform") }.buttonStyle(.plain)
                        }
                    }
                    if (kind == .video ? library.recordings.isEmpty : library.audioRecordings.isEmpty) {
                        Text("导入后，项目会在这里继续").font(.subheadline.bold()).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 76).glassEffect(.regular, in: .rect(cornerRadius: 24))
                    }
                }
            }.padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 30)
        }.scrollIndicators(.hidden)
        .fileImporter(isPresented: $importing, allowedContentTypes: kind == .video ? [.movie] : [.audio]) { result in Task { await importMedia(result) } }
        .navigationDestination(isPresented: Binding(get: { video != nil }, set: { if !$0 { video = nil } })) { if let video { EditorView(recording: video) } }
        .navigationDestination(isPresented: Binding(get: { audio != nil }, set: { if !$0 { audio = nil } })) { if let audio { AudioEditorView(recording: audio) } }
    }

    private var timeline: some View {
        VStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(0..<(row == 0 ? 7 : 11), id: \.self) { i in
                        RoundedRectangle(cornerRadius: 5).fill([LiquidPalette.indigo, LiquidPalette.cyan, LiquidPalette.coral][row].opacity(i.isMultiple(of: 3) ? 0.65 : 0.22))
                            .frame(maxWidth: .infinity, minHeight: row == 0 ? 42 : 18)
                    }
                }
            }
        }.padding(.leading, 90).padding(.top, 95).opacity(0.8)
    }

    private func recent(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(LiquidPalette.indigo).frame(width: 42, height: 42).glassEffect(.regular, in: .circle)
            VStack(alignment: .leading) { Text(title).font(.subheadline.bold()); Text(detail).font(.caption2.monospaced()).foregroundStyle(.secondary) }
            Spacer(); Image(systemName: "arrow.up.right")
        }.padding(12).glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22)).foregroundStyle(.primary)
    }

    @MainActor private func importMedia(_ result: Result<URL, Error>) async {
        do {
            let source = try result.get(); let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
            try SharedStorage.prepare(); let directory = kind == .video ? SharedStorage.localDirectory : SharedStorage.audioDirectory
            let target = directory.appendingPathComponent("Import-\(UUID().uuidString).\(source.pathExtension)")
            try FileManager.default.copyItem(at: source, to: target)
            let asset = AVURLAsset(url: target); let duration = try await asset.load(.duration).seconds
            let bytes = ((try? FileManager.default.attributesOfItem(atPath: target.path)[.size]) as? NSNumber)?.int64Value ?? 0
            if kind == .video { video = Recording(id: UUID(), url: target, createdAt: .now, duration: duration, byteCount: bytes) }
            else { audio = AudioRecording(id: UUID(), url: target, createdAt: .now, duration: duration, byteCount: bytes) }
        } catch { }
    }
}

struct LiquidLibrarySurface: View {
    enum Kind: String, CaseIterable { case video = "视频"; case audio = "音频" }
    @State private var kind: Kind = .video
    @EnvironmentObject private var library: RecordingLibrary

    var body: some View {
        VStack(spacing: 18) {
            LiquidTitle(eyebrow: "LIBRARY", title: "作品流", detail: "录屏、录音与导出结果")
            HStack(spacing: 8) {
                ForEach(Kind.allCases, id: \.self) { item in
                    Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { kind = item } } label: {
                        HStack { Text(item.rawValue); Spacer(); Text("\(item == .video ? library.recordings.count : library.audioRecordings.count)").font(.caption.monospaced()) }
                            .font(.subheadline.bold()).padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 54)
                            .foregroundStyle(kind == item ? .white : .primary)
                            .glassEffect(.regular.tint(kind == item ? LiquidPalette.indigo : .clear).interactive(), in: .capsule)
                    }.buttonStyle(.plain)
                }
            }.padding(6).glassEffect(.regular, in: .capsule)

            ScrollView {
                if kind == .video {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(library.recordings) { item in
                            NavigationLink(value: item) { mediaCard(item.title, item.durationText, "play.fill", LiquidPalette.indigo) }.buttonStyle(.plain)
                        }
                    }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(library.audioRecordings) { item in
                            NavigationLink(value: item) { audioRow(item) }.buttonStyle(.plain)
                        }
                    }
                }
                if kind == .video ? library.recordings.isEmpty : library.audioRecordings.isEmpty { empty }
            }.scrollIndicators(.hidden).refreshable { await library.reload() }
        }.padding(.horizontal, 18).padding(.top, 14)
    }

    private func mediaCard(_ title: String, _ detail: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack { RoundedRectangle(cornerRadius: 24).fill(tint.opacity(0.12)); Image(systemName: symbol).font(.title2).foregroundStyle(tint) }.frame(height: 150)
            Text(title).font(.subheadline.bold()); Text(detail).font(.caption2.monospaced()).foregroundStyle(.secondary)
        }.padding(12).glassEffect(.regular.interactive(), in: .rect(cornerRadius: 30)).foregroundStyle(.primary)
    }
    private func audioRow(_ item: AudioRecording) -> some View {
        HStack(spacing: 13) { Image(systemName: "waveform").foregroundStyle(LiquidPalette.mint).frame(width: 48, height: 48).glassEffect(.regular, in: .circle); VStack(alignment: .leading) { Text(item.title).bold(); Text("\(item.durationText) · \(item.formatText)").font(.caption2.monospaced()).foregroundStyle(.secondary) }; Spacer() }
            .padding(12).glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24)).foregroundStyle(.primary)
    }
    private var empty: some View {
        VStack(spacing: 16) { Image(systemName: kind == .video ? "viewfinder" : "waveform").font(.system(size: 42)); Text("这里还没有内容").font(.title3.bold()); Text("完成一次创作后会自动出现").font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, minHeight: 360).glassEffect(.regular.tint(LiquidPalette.indigo.opacity(0.07)), in: .rect(cornerRadius: 40))
    }
}

struct LiquidTranscodeSurface: View {
    @StateObject private var queue = TranscodeQueue()
    @State private var importing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LiquidTitle(eyebrow: "CONVERT", title: "格式实验室", detail: "视频、音频与批量队列")
                Button { importing = true } label: {
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 7) { Text("放入媒体").font(.system(size: 27, weight: .bold, design: .rounded)); Text("自动识别并开放全部可用格式").font(.caption.bold()).foregroundStyle(.secondary) }
                        Spacer(); Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.white).frame(width: 72, height: 72).glassEffect(.regular.tint(LiquidPalette.indigo).interactive(), in: .circle)
                    }.padding(24).frame(maxWidth: .infinity, minHeight: 190).glassEffect(.regular.tint(LiquidPalette.indigo.opacity(0.08)).interactive(), in: .rect(cornerRadius: 40))
                }.buttonStyle(.plain).foregroundStyle(.primary)

                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        family("视频", "MP4 MOV MKV WEBM", "film", LiquidPalette.indigo)
                        family("音频", "FLAC WAV MP3 OPUS", "waveform", LiquidPalette.mint)
                        family("编码", "HEVC H264 AV1", "bolt", LiquidPalette.coral)
                    }
                }.scrollIndicators(.hidden)

                if !queue.jobs.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(queue.jobs) { job in
                            HStack { Image(systemName: job.probe.hasVideo ? "film" : "waveform"); VStack(alignment: .leading) { Text(job.title).font(.subheadline.bold()).lineLimit(1); Text(job.detail).font(.caption2.monospaced()).foregroundStyle(.secondary) }; Spacer(); Text(job.target.pathExtension.uppercased()).font(.caption.bold()) }
                                .padding(14).glassEffect(.regular, in: .rect(cornerRadius: 22))
                        }
                        Button { queue.isRunning ? queue.stop() : queue.start() } label: { Label(queue.isRunning ? "停止队列" : "开始转码", systemImage: queue.isRunning ? "pause.fill" : "play.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 56).foregroundStyle(.white).glassEffect(.regular.tint(LiquidPalette.indigo).interactive(), in: .capsule) }.buttonStyle(.plain)
                    }
                }
            }.padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 30)
        }.scrollIndicators(.hidden)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie, .audio, .data], allowsMultipleSelection: true) { result in Task { await receive(result) } }
    }

    private func family(_ title: String, _ detail: String, _ symbol: String, _ tint: Color) -> some View {
        HStack { Image(systemName: symbol).foregroundStyle(tint); VStack(alignment: .leading) { Text(title).bold(); Text(detail).font(.caption2.monospaced()).foregroundStyle(.secondary) } }.padding(.horizontal, 16).frame(width: 190, height: 70).glassEffect(.regular.tint(tint.opacity(0.07)), in: .capsule)
    }
    @MainActor private func receive(_ result: Result<[URL], Error>) async {
        guard let urls = try? result.get() else { return }
        for source in urls {
            let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
            do { try SharedStorage.prepare(); let target = SharedStorage.transcodeDirectory.appendingPathComponent("Input-\(UUID().uuidString).\(source.pathExtension)"); try FileManager.default.copyItem(at: source, to: target); let probe = try await MediaProbe.inspect(target); try queue.add(files: [(target, probe)]) } catch { }
        }
    }
}

struct LiquidSettingsSurface: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("screenCodec", store: UserDefaults(suiteName: SharedStorage.appGroup)) private var codec = "hevc"
    @AppStorage(ScreenRecordingPreferenceKey.frameRate, store: UserDefaults(suiteName: SharedStorage.appGroup)) private var fps = 60
    @AppStorage(ScreenRecordingPreferenceKey.resolution, store: UserDefaults(suiteName: SharedStorage.appGroup)) private var resolution = ScreenResolutionPreset.native.rawValue

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LiquidTitle(eyebrow: "CONTROL", title: "控制空间", detail: "少量选择，立即生效")
                settingGroup("录屏", "record.circle", LiquidPalette.indigo) {
                    choice("画质", values: ScreenResolutionPreset.allCases.map { ($0.rawValue, $0.title) }, selection: $resolution)
                    choice("编码", values: [("hevc", "HEVC"), ("h264", "H.264")], selection: $codec)
                    VStack(spacing: 8) { HStack { Text("帧率").bold(); Spacer(); Text("\(fps) FPS").font(.caption.monospaced()) }; Slider(value: Binding(get: { Double(fps) }, set: { fps = Int($0) }), in: 15...60, step: 1).tint(LiquidPalette.coral) }
                }
                settingGroup("外观", "circle.lefthalf.filled", LiquidPalette.cyan) {
                    choice("模式", values: [("system", "自动"), ("light", "浅色"), ("dark", "深色")], selection: $appearance)
                }
                settingGroup("系统", "gearshape", LiquidPalette.mint) {
                    NavigationLink { LegalDocumentView(document: .privacyRights) } label: { row("隐私权利", "hand.raised") }.buttonStyle(.plain)
                    NavigationLink { LegalDocumentView(document: .ffmpeg) } label: { row("FFmpeg 开源协议", "doc.text") }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 30)
        }.scrollIndicators(.hidden)
    }

    private func settingGroup<Content: View>(_ title: String, _ symbol: String, _ tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) { Label(title, systemImage: symbol).font(.title3.bold()).foregroundStyle(tint); content() }
            .padding(20).glassEffect(.regular.tint(tint.opacity(0.055)), in: .rect(cornerRadius: 32))
    }
    private func choice(_ title: String, values: [(String, String)], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 9) { Text(title).font(.caption.bold()).foregroundStyle(.secondary); HStack(spacing: 7) { ForEach(values, id: \.0) { value, label in Button { selection.wrappedValue = value } label: { Text(label).font(.caption.bold()).frame(maxWidth: .infinity, minHeight: 40).foregroundStyle(selection.wrappedValue == value ? .white : .primary).glassEffect(.regular.tint(selection.wrappedValue == value ? LiquidPalette.indigo : .clear).interactive(), in: .capsule) }.buttonStyle(.plain) } } }
    }
    private func row(_ title: String, _ symbol: String) -> some View { HStack { Label(title, systemImage: symbol).bold(); Spacer(); Image(systemName: "arrow.up.right") }.frame(minHeight: 48).foregroundStyle(.primary) }
}
