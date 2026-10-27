import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct WildTranscodeView: View {
    @StateObject private var queue = TranscodeQueue()
    @State private var importing = false
    @State private var errorMessage: String?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                WildHeader("信号变形", kicker: "TRANSCODE 04") {
                    if !queue.jobs.isEmpty {
                        WildIconButton(symbol: "trash", tint: WildColor.orange) { queue.clearFinished() }
                    }
                }
                .wildEntrance()

                pipeline
                    .wildEntrance(0.04)

                Button { importing = true } label: {
                    HStack {
                        RailGlyph(systemName: "plus")
                        Text("添加文件")
                        Spacer()
                        Text("VIDEO / AUDIO").font(.system(.caption, design: .monospaced, weight: .bold))
                    }
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .padding(.horizontal, 17)
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(WildActionStyle(tint: WildColor.blue))
                .wildEntrance(0.08)

                jobList
                    .wildEntrance(0.12)

                Button {
                    queue.isRunning ? queue.stop() : queue.start()
                } label: {
                    HStack {
                        RailGlyph(systemName: queue.isRunning ? "pause.fill" : "play.fill")
                        Text(queue.isRunning ? "完成当前项后停止" : "开始转换")
                        Spacer()
                    }
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .padding(.horizontal, 17)
                    .frame(maxWidth: .infinity, minHeight: 58)
                }
                .buttonStyle(WildActionStyle())
                .disabled(!queue.isRunning && queue.waitingCount == 0)
                .opacity(!queue.isRunning && queue.waitingCount == 0 ? 0.44 : 1)
            }
            .wildPage()
            .padding(.bottom, 116)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.movie, .audio, .data],
            allowsMultipleSelection: true
        ) { result in Task { await receive(result) } }
        .alert("无法加入任务", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "请稍后重试") }
    }

    private var pipeline: some View {
        VStack(spacing: 0) {
            HStack {
                WildStamp(text: queue.isRunning ? "RUNNING" : queue.completedCount > 0 ? "COMPLETE" : "IDLE", tint: queue.isRunning ? WildColor.orange : WildColor.mint)
                Spacer()
                Text("\(queue.completedCount) / \(queue.jobs.count)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(WildColor.stageSecondary(scheme))
            }
            .padding(.horizontal, 17)
            .frame(height: 58)

            HStack(spacing: 10) {
                flowNode("输入", symbol: "tray.and.arrow.down", active: !queue.jobs.isEmpty)
                flowConnector(active: queue.isRunning)
                flowNode("编码", symbol: "memorychip", active: queue.isRunning)
                flowConnector(active: queue.completedCount > 0)
                flowNode("输出", symbol: "folder", active: queue.completedCount > 0)
            }
            .padding(17)

            ProgressView(value: queue.overallProgress)
                .tint(WildColor.orange)
                .background(WildColor.stageRule(scheme))
        }
        .background(WildColor.stage(scheme))
        .overlay { WildPanelShape(cut: 18).stroke(WildColor.rule(scheme), lineWidth: 1) }
        .clipShape(WildPanelShape(cut: 18))
    }

    private func flowNode(_ title: String, symbol: String, active: Bool) -> some View {
        VStack(spacing: 7) {
            RailGlyph(systemName: symbol).font(.system(size: 18, weight: .bold))
            Text(title).font(.system(.caption, design: .rounded, weight: .bold))
        }
        .foregroundStyle(active ? WildColor.stageInk(scheme) : WildColor.stageSecondary(scheme))
        .frame(width: 64)
        .frame(minHeight: 64)
    }

    private func flowConnector(active: Bool) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(WildColor.stageRule(scheme)).frame(height: 1)
                if active {
                    TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { context in
                        let phase = reduceMotion ? 0.5 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        Capsule().fill(WildColor.orange).frame(width: 18, height: 4)
                            .offset(x: max(0, (proxy.size.width - 18) * phase))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 4, maxHeight: 4)
    }

    @ViewBuilder private var jobList: some View {
        if queue.jobs.isEmpty {
            WildSurface { WildEmptyState(title: "等待文件", detail: "可批量处理视频与音频", symbol: "rectangle.dashed") }
        } else {
            LazyVStack(spacing: 10) {
                ForEach(queue.jobs) { job in jobRow(job) }
            }
        }
    }

    private func jobRow(_ job: TranscodeJob) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                RailGlyph(systemName: job.probe.hasVideo ? "film" : "waveform")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(job.probe.hasVideo ? WildColor.onBlue : WildColor.onOrange)
                    .frame(width: 40, height: 40)
                    .background(job.probe.hasVideo ? WildColor.blue : WildColor.orange)
                    .clipShape(WildTicketShape())
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title).font(.system(.body, design: .rounded, weight: .bold)).lineLimit(1)
                    Text(job.detail).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(WildColor.secondary(scheme)).lineLimit(1)
                }
                Spacer()
                status(job)
            }

            HStack {
                Menu {
                    ForEach(queue.availableTargets(for: job.probe)) { target in
                        Button { queue.setTarget(target, for: job.id) } label: {
                            if target == job.target { RailLabel(target.title, systemImage: "checkmark") }
                            else { Text(target.title) }
                        }
                    }
                } label: {
                    RailLabel(job.target.title, systemImage: "arrow.turn.down.right")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(WildColor.ink(scheme))
                        .padding(.horizontal, 11)
                        .frame(minHeight: 36)
                        .background(WildColor.raised(scheme))
                        .clipShape(WildTicketShape())
                }
                Spacer()
                if case let .completed(outputURL) = job.status {
                    ShareLink(item: outputURL) {
                        RailLabel("导出", systemImage: "square.and.arrow.up")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(WildColor.onBlue)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 40)
                            .background(WildColor.blue)
                            .clipShape(WildTicketShape())
                    }
                    .accessibilityLabel("导出 \(job.title)")
                }
                if case .failed = job.status {
                    Button("重试") { queue.retry(job.id) }.font(.caption.bold()).foregroundStyle(WildColor.signalInk(scheme))
                }
                Button(role: .destructive) { queue.remove(job.id) } label: {
                    RailGlyph(systemName: "trash").frame(width: 40, height: 40)
                }
                .disabled(isRunning(job))
            }
            if isRunning(job) { ProgressView(value: job.progress).tint(WildColor.orange) }
        }
        .foregroundStyle(WildColor.ink(scheme))
        .padding(14)
        .background(WildColor.paper(scheme))
        .clipShape(WildPanelShape(cut: 14))
    }

    @ViewBuilder private func status(_ job: TranscodeJob) -> some View {
        switch job.status {
        case .waiting: WildStamp(text: "WAIT", tint: WildColor.raised(scheme), foreground: WildColor.ink(scheme))
        case .running: WildStamp(text: "\(Int(job.progress * 100))%", tint: WildColor.orange)
        case .completed: WildStamp(text: "DONE", tint: WildColor.mint)
        case .failed: WildStamp(text: "ERROR", tint: WildColor.orange)
        }
    }

    private func isRunning(_ job: TranscodeJob) -> Bool {
        if case .running = job.status { return true }
        return false
    }

    @MainActor private func receive(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            for source in urls {
                let access = source.startAccessingSecurityScopedResource()
                defer { if access { source.stopAccessingSecurityScopedResource() } }
                try SharedStorage.prepare()
                let ext = source.pathExtension.isEmpty ? "media" : source.pathExtension
                let target = SharedStorage.transcodeDirectory.appendingPathComponent("Input-\(UUID().uuidString).\(ext)")
                try FileManager.default.copyItem(at: source, to: target)
                let probe = try await MediaProbe.inspect(target)
                try queue.add(files: [(target, probe)])
            }
        } catch { errorMessage = error.localizedDescription }
    }
}

struct WildSettingsView: View {
    @AppStorage(WildAppearance.storageKey) private var appearance = WildAppearance.defaultValue
    @AppStorage("screenCodec", store: UserDefaults(suiteName: SharedStorage.appGroup)) private var codec = "hevc"
    @AppStorage(ScreenRecordingPreferenceKey.resolution, store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var resolution = ScreenResolutionPreset.native.rawValue
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
        ScrollView {
            VStack(spacing: 24) {
                WildHeader("控制台", kicker: "CONTROL 05")
                    .wildEntrance()
                settingsGroup("外观") {
                    choice(
                        "颜色模式",
                        detail: appearanceDescription,
                        values: [("system", "自动"), ("light", "浅色"), ("dark", "深色")],
                        selection: $appearance
                    )
                }
                .wildEntrance(0.04)
                settingsGroup("录制输出") {
                    choice("画质", detail: "输出画面的长边尺寸", values: [ScreenResolutionPreset.p720, .p1080, .p2K, .native].map { ($0.rawValue, $0.title) }, selection: $resolution)
                    divider
                    slider
                    divider
                    choice("编码", detail: "HEVC 体积更小，H.264 兼容性更高", values: [("hevc", "HEVC"), ("h264", "H.264")], selection: $codec)
                    divider
                    choice("方向", detail: "自动跟随设备或锁定输出", values: ScreenOrientationPreset.allCases.map { ($0.rawValue, $0.title) }, selection: $orientation)
                    divider
                    choice("码率", detail: "根据画面与帧率动态计算", values: ScreenBitratePreset.allCases.map { ($0.rawValue, $0.title) }, selection: $bitrate)
                }
                settingsGroup("同步") {
                    VStack(spacing: 14) {
                        Toggle(isOn: $iCloudSyncEnabled) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("iCloud Drive").font(.system(.body, design: .rounded, weight: .bold))
                                Text("录屏、录音、字幕和工程文件双向合并").font(.system(.caption, design: .rounded)).foregroundStyle(WildColor.secondary(scheme))
                            }
                        }
                        .tint(WildColor.blue)
                        HStack {
                            if cloudSync.state == .syncing { ProgressView().controlSize(.small) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cloudSync.statusText).font(.caption.bold())
                                if let date = cloudSync.lastSyncDate {
                                    Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption2.monospaced()).foregroundStyle(WildColor.secondary(scheme))
                                }
                            }
                            Spacer()
                            Button("立即同步") { Task { await cloudSync.sync() } }
                                .font(.caption.bold()).foregroundStyle(WildColor.blue)
                                .disabled(!iCloudSyncEnabled || cloudSync.state == .syncing)
                        }
                    }
                    .padding(16)
                }
                settingsGroup("文档") {
                    legalRow(.privacyRights)
                    divider.padding(.leading, 56)
                    legalRow(.userAgreement)
                    divider.padding(.leading, 56)
                    legalRow(.disclaimer)
                    divider.padding(.leading, 56)
                    legalRow(.ffmpeg)
                    divider.padding(.leading, 56)
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("MonoFrame").font(.system(.body, design: .rounded, weight: .bold))
                            Text("版本 \(versionText)").font(.caption.monospaced()).foregroundStyle(WildColor.secondary(scheme))
                        }
                        Spacer()
                        WildStamp(text: "LOCAL FIRST")
                    }
                    .padding(16)
                }
            }
            .wildPage()
            .padding(.bottom, 116)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .onChange(of: iCloudSyncEnabled) { _, value in if value { Task { await cloudSync.sync() } } }
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 11) {
            WildSectionLabel(index: sectionCode(title), title: title)
            WildSurface { VStack(spacing: 0) { content() } }
        }
    }

    private func choice(_ title: String, detail: String, values: [(String, String)], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(.body, design: .rounded, weight: .bold))
                Text(detail).font(.system(.caption, design: .rounded)).foregroundStyle(WildColor.secondary(scheme))
            }
            WildSegmented(values: values, selection: selection)
        }
        .padding(16)
    }

    private var slider: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("帧率").font(.system(.body, design: .rounded, weight: .bold))
                    Text("更高帧率会增加文件体积").font(.caption).foregroundStyle(WildColor.secondary(scheme))
                }
                Spacer()
                Text("\(frameRate) FPS").font(.caption.monospaced().bold())
            }
            Slider(value: Binding(get: { Double(frameRate) }, set: { frameRate = Int($0.rounded()) }), in: 15...60, step: 1).tint(WildColor.blue)
        }
        .padding(16)
    }

    private var divider: some View { WildRule() }

    private var appearanceDescription: String {
        switch appearance {
        case "light": "始终使用浅色界面"
        case "dark": "始终使用深色界面"
        default: "跟随 iPhone 外观"
        }
    }

    private func legalRow(_ document: LegalDocument) -> some View {
        NavigationLink { WildLegalDocumentView(document: document) } label: {
            HStack(spacing: 13) {
                RailGlyph(systemName: document.icon).font(.system(size: 16, weight: .bold)).foregroundStyle(WildColor.blue).frame(width: 28)
                Text(document.title).font(.system(.body, design: .rounded, weight: .bold))
                Spacer()
                RailGlyph(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(WildColor.secondary(scheme))
            }
            .foregroundStyle(WildColor.ink(scheme))
            .padding(.horizontal, 15)
            .frame(minHeight: 60)
        }
        .buttonStyle(.plain)
    }

    private func sectionCode(_ title: String) -> String {
        switch title { case "外观": "A"; case "录制输出": "B"; case "同步": "C"; default: "D" }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}
