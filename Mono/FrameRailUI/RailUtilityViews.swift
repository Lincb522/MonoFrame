import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct RailTranscodeView: View {
    @StateObject private var queue = TranscodeQueue()
    @State private var importing = false
    @State private var errorMessage: String?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                RailPageHeader(title: "格式转换") {
                    if !queue.jobs.isEmpty {
                        RailIconButton(symbol: "trash", title: nil) { queue.clearFinished() }
                    }
                }
                .railEntrance()

                pipeline
                    .railEntrance(delay: 0.04)

                Button { importing = true } label: {
                    HStack {
                        RailGlyph(systemName: "plus")
                        Text("添加文件")
                        Spacer()
                        Text("VIDEO / AUDIO").font(.system(.caption, design: .monospaced, weight: .bold)).opacity(0.72)
                    }
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .padding(.horizontal, 17)
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(RailPrimaryButtonStyle(tint: RailColor.blue))
                .railEntrance(delay: 0.08)

                jobList
                    .railEntrance(delay: 0.12)

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
                .buttonStyle(RailPrimaryButtonStyle())
                .disabled(!queue.isRunning && queue.waitingCount == 0)
                .opacity(!queue.isRunning && queue.waitingCount == 0 ? 0.44 : 1)
            }
            .railPagePadding()
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
                RailStatus(text: queue.isRunning ? "RUNNING" : queue.completedCount > 0 ? "COMPLETE" : "IDLE", tint: queue.isRunning ? RailColor.coral : RailColor.mint)
                Spacer()
                Text("\(queue.completedCount) / \(queue.jobs.count)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(.white.opacity(0.70))
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
                .tint(RailColor.coral)
                .background(.white.opacity(0.12))
        }
        .background(Color(red: 0.055, green: 0.06, blue: 0.075))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func flowNode(_ title: String, symbol: String, active: Bool) -> some View {
        VStack(spacing: 7) {
            RailGlyph(systemName: symbol).font(.system(size: 18, weight: .bold))
            Text(title).font(.system(.caption, design: .rounded, weight: .bold))
        }
        .foregroundStyle(active ? .white : .white.opacity(0.36))
        .frame(width: 64)
        .frame(minHeight: 64)
    }

    private func flowConnector(active: Bool) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.16)).frame(height: 1)
                if active {
                    TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { context in
                        let phase = reduceMotion ? 0.5 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        Capsule().fill(RailColor.coral).frame(width: 18, height: 4)
                            .offset(x: max(0, (proxy.size.width - 18) * phase))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 4, maxHeight: 4)
    }

    @ViewBuilder private var jobList: some View {
        if queue.jobs.isEmpty {
            RailSurface { RailEmptyState(title: "等待文件", detail: "可批量处理视频与音频", symbol: "rectangle.dashed") }
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
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(job.probe.hasVideo ? RailColor.blue : RailColor.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title).font(.system(.body, design: .rounded, weight: .bold)).lineLimit(1)
                    Text(job.detail).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(RailColor.secondary(scheme)).lineLimit(1)
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
                        .foregroundStyle(RailColor.ink(scheme))
                        .padding(.horizontal, 11)
                        .frame(minHeight: 36)
                        .background(RailColor.raised(scheme))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Spacer()
                if case let .completed(outputURL) = job.status {
                    ShareLink(item: outputURL) {
                        RailLabel("导出", systemImage: "square.and.arrow.up")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 40)
                            .background(RailColor.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .accessibilityLabel("导出 \(job.title)")
                }
                if case .failed = job.status {
                    Button("重试") { queue.retry(job.id) }.font(.caption.bold()).foregroundStyle(RailColor.coral)
                }
                Button(role: .destructive) { queue.remove(job.id) } label: {
                    RailGlyph(systemName: "trash").frame(width: 40, height: 40)
                }
                .disabled(isRunning(job))
            }
            if isRunning(job) { ProgressView(value: job.progress).tint(RailColor.coral) }
        }
        .foregroundStyle(RailColor.ink(scheme))
        .padding(14)
        .background(RailColor.surface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder private func status(_ job: TranscodeJob) -> some View {
        switch job.status {
        case .waiting: RailStatus(text: "WAIT", tint: RailColor.secondary(scheme))
        case .running: RailStatus(text: "\(Int(job.progress * 100))%", tint: RailColor.coral)
        case .completed: RailStatus(text: "DONE", tint: RailColor.mint)
        case .failed: RailStatus(text: "ERROR", tint: RailColor.coral)
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

struct RailSettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
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
                RailPageHeader(title: "系统调校")
                    .railEntrance()
                settingsGroup("外观") {
                    choice(
                        "颜色模式",
                        detail: appearanceDescription,
                        values: [("system", "自动"), ("light", "浅色"), ("dark", "深色")],
                        selection: $appearance
                    )
                }
                .railEntrance(delay: 0.04)
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
                                Text("录屏、录音、字幕和工程文件双向合并").font(.system(.caption, design: .rounded)).foregroundStyle(RailColor.secondary(scheme))
                            }
                        }
                        .tint(RailColor.coral)
                        HStack {
                            if cloudSync.state == .syncing { ProgressView().controlSize(.small) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cloudSync.statusText).font(.caption.bold())
                                if let date = cloudSync.lastSyncDate {
                                    Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption2.monospaced()).foregroundStyle(RailColor.secondary(scheme))
                                }
                            }
                            Spacer()
                            Button("立即同步") { Task { await cloudSync.sync() } }
                                .font(.caption.bold()).foregroundStyle(RailColor.coral)
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
                            Text("版本 \(versionText)").font(.caption.monospaced()).foregroundStyle(RailColor.secondary(scheme))
                        }
                        Spacer()
                        RailStatus(text: "LOCAL FIRST")
                    }
                    .padding(16)
                }
            }
            .railPagePadding()
            .padding(.bottom, 116)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .onChange(of: iCloudSyncEnabled) { _, value in if value { Task { await cloudSync.sync() } } }
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 11) {
            RailSectionTitle(title: title)
            RailSurface { VStack(spacing: 0) { content() } }
        }
    }

    private func choice(_ title: String, detail: String, values: [(String, String)], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(.body, design: .rounded, weight: .bold))
                Text(detail).font(.system(.caption, design: .rounded)).foregroundStyle(RailColor.secondary(scheme))
            }
            RailSegmented(values: values, selection: selection)
        }
        .padding(16)
    }

    private var slider: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("帧率").font(.system(.body, design: .rounded, weight: .bold))
                    Text("更高帧率会增加文件体积").font(.caption).foregroundStyle(RailColor.secondary(scheme))
                }
                Spacer()
                Text("\(frameRate) FPS").font(.caption.monospaced().bold())
            }
            Slider(value: Binding(get: { Double(frameRate) }, set: { frameRate = Int($0.rounded()) }), in: 15...60, step: 1).tint(RailColor.coral)
        }
        .padding(16)
    }

    private var divider: some View { RailHairline() }

    private var appearanceDescription: String {
        switch appearance {
        case "light": "始终使用浅色界面"
        case "dark": "始终使用深色界面"
        default: "跟随 iPhone 外观"
        }
    }

    private func legalRow(_ document: LegalDocument) -> some View {
        NavigationLink { RailLegalDocumentView(document: document) } label: {
            HStack(spacing: 13) {
                RailGlyph(systemName: document.icon).font(.system(size: 16, weight: .bold)).foregroundStyle(RailColor.coral).frame(width: 28)
                Text(document.title).font(.system(.body, design: .rounded, weight: .bold))
                Spacer()
                RailGlyph(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(RailColor.secondary(scheme))
            }
            .foregroundStyle(RailColor.ink(scheme))
            .padding(.horizontal, 15)
            .frame(minHeight: 60)
        }
        .buttonStyle(.plain)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}
