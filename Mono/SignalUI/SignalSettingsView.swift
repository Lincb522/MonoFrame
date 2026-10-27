import SwiftUI

struct SignalSettingsView: View {
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
            VStack(spacing: SignalSpace.xl) {
                SignalPageHeader(title: "调成你的样子", detail: "画面、性能与同步，一处管好")

                settingsHero
                    .youthStageEntrance()

                settingsSection("录屏") {
                    choiceRow(
                        "画质",
                        detail: "输出画面的长边尺寸",
                        values: [
                            ScreenResolutionPreset.p720,
                            .p1080,
                            .p2K,
                            .native
                        ].map { ($0.rawValue, $0.title) },
                        selection: $resolution
                    )
                    SignalRule().padding(.leading, SignalSpace.md)
                    sliderRow
                    SignalRule().padding(.leading, SignalSpace.md)
                    choiceRow("编码", detail: "HEVC 文件更小，H.264 兼容性更高", values: [("hevc", "HEVC"), ("h264", "H.264")], selection: $codec)
                    SignalRule().padding(.leading, SignalSpace.md)
                    choiceRow(
                        "方向",
                        detail: "自动跟随设备或锁定输出方向",
                        values: ScreenOrientationPreset.allCases.map { ($0.rawValue, $0.title) },
                        selection: $orientation
                    )
                    SignalRule().padding(.leading, SignalSpace.md)
                    choiceRow(
                        "码率",
                        detail: "最高会根据画面尺寸与帧率动态计算",
                        values: ScreenBitratePreset.allCases.map { ($0.rawValue, $0.title) },
                        selection: $bitrate
                    )
                }
                .youthDelayedReveal(delay: 0.42)

                settingsSection("外观") {
                    choiceRow(
                        "显示模式",
                        detail: "可以跟随系统自动切换",
                        values: [("system", "自动"), ("light", "浅色"), ("dark", "深色")],
                        selection: $appearance
                    )
                }
                .youthDelayedReveal(delay: 0.48)

                settingsSection("同步") {
                    VStack(spacing: SignalSpace.md) {
                        Toggle(isOn: $iCloudSyncEnabled) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("iCloud Drive")
                                    .font(.system(.body, design: .rounded, weight: .bold))
                                Text("录屏、录音、字幕和工程文件双向合并")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(SignalColor.secondary(scheme))
                            }
                        }
                        .tint(SignalColor.coral)

                        HStack(spacing: SignalSpace.sm) {
                            if cloudSync.state == .syncing { ProgressView().controlSize(.small) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cloudSync.statusText)
                                    .font(.system(.caption, design: .rounded, weight: .bold))
                                if let date = cloudSync.lastSyncDate {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(SignalColor.secondary(scheme))
                                }
                            }
                            Spacer()
                            Button("立即同步") { Task { await cloudSync.sync() } }
                                .font(.system(.caption, design: .rounded, weight: .bold))
                                .foregroundStyle(SignalColor.coral)
                                .disabled(!iCloudSyncEnabled || cloudSync.state == .syncing)
                        }
                    }
                    .padding(SignalSpace.md)
                }

                settingsSection("关于") {
                    legalLink("隐私权利", detail: "数据与权限说明", symbol: "hand.raised", document: .privacyRights)
                    SignalRule().padding(.leading, 60)
                    legalLink("用户协议", detail: "使用条款", symbol: "checkmark.shield", document: .userAgreement)
                    SignalRule().padding(.leading, 60)
                    legalLink("FFmpeg 开源协议", detail: "第三方软件声明", symbol: "doc.text", document: .ffmpeg)
                    SignalRule().padding(.leading, 60)
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("MonoFrame").font(.system(.body, design: .rounded, weight: .bold))
                            Text("版本 \(versionText)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(SignalColor.secondary(scheme))
                        }
                        Spacer()
                        Text("LOCAL FIRST")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(SignalColor.secondary(scheme))
                    }
                    .padding(.horizontal, SignalSpace.md)
                    .frame(minHeight: 66)
                }
            }
            .signalPagePadding()
            .padding(.bottom, 124)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .onChange(of: iCloudSyncEnabled) { _, enabled in
            if enabled { Task { await cloudSync.sync() } }
        }
    }

    private var settingsHero: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 20) {
                Text("当前预设")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
                Text("\(ScreenResolutionPreset(rawValue: resolution)?.title ?? "设备屏幕")  ·  \(frameRate) FPS")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                HStack(spacing: 10) {
                    ForEach([SignalColor.acid, SignalColor.cobalt, SignalColor.coral], id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 44, height: 44)
                            .overlay { Circle().stroke(.white.opacity(0.24), lineWidth: 4).padding(4) }
                    }
                    Spacer()
                    Text(codec.uppercased())
                        .font(.system(.caption, design: .monospaced, weight: .black))
                        .foregroundStyle(SignalColor.acid)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 188, alignment: .leading)
            .background(SignalColor.stage)
            .clipShape(YouthNotchedPanelShape(cornerRadius: 34, notchWidth: 94, notchDepth: 62))

            YouthStatusBubble(value: "\(frameRate)", symbol: "slider.horizontal.3")
                .padding(8)
        }
        .accessibilityElement(children: .combine)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SignalSpace.sm) {
            SignalSectionHeader(title: title)
            SignalPanel { VStack(spacing: 0) { content() } }
        }
    }

    private func choiceRow(
        _ title: String,
        detail: String,
        values: [(String, String)],
        selection: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: SignalSpace.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(.body, design: .rounded, weight: .bold))
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(SignalColor.secondary(scheme))
            }
            SignalSegmentedControl(values: values, selection: selection)
        }
        .padding(SignalSpace.md)
    }

    private var sliderRow: some View {
        VStack(spacing: SignalSpace.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("帧率").font(.system(.body, design: .rounded, weight: .bold))
                    Text("更高帧率会增加文件体积")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(SignalColor.secondary(scheme))
                }
                Spacer()
                Text("\(frameRate) FPS")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
            }
            Slider(
                value: Binding(get: { Double(frameRate) }, set: { frameRate = Int($0.rounded()) }),
                in: 15...60,
                step: 1
            )
            .tint(SignalColor.coral)
        }
        .padding(SignalSpace.md)
    }

    private func legalLink(
        _ title: String,
        detail: String,
        symbol: String,
        document: LegalDocument
    ) -> some View {
        NavigationLink { LegalDocumentView(document: document) } label: {
            HStack(spacing: SignalSpace.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(SignalColor.ink(scheme))
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(.body, design: .rounded, weight: .bold))
                    Text(detail).font(.system(.caption, design: .rounded)).foregroundStyle(SignalColor.secondary(scheme))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(SignalColor.secondary(scheme))
            }
            .foregroundStyle(SignalColor.ink(scheme))
            .padding(.horizontal, SignalSpace.md)
            .frame(minHeight: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}
