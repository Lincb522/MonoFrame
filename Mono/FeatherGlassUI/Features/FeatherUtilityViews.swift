import SwiftUI
import UIKit

// MARK: - Settings

struct FeatherSettingsView: View {
    @AppStorage(AppAppearancePreference.storageKey)
    private var appearance = AppAppearancePreference.defaultValue
    @AppStorage("screenCodec", store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var codec = "hevc"
    @AppStorage(
        ScreenRecordingPreferenceKey.resolution,
        store: UserDefaults(suiteName: SharedStorage.appGroup)
    ) private var resolution = ScreenResolutionPreset.native.rawValue
    @AppStorage(
        ScreenRecordingPreferenceKey.frameRate,
        store: UserDefaults(suiteName: SharedStorage.appGroup)
    ) private var frameRate = 60
    @AppStorage(
        ScreenRecordingPreferenceKey.orientation,
        store: UserDefaults(suiteName: SharedStorage.appGroup)
    ) private var orientation = ScreenOrientationPreset.automatic.rawValue
    @AppStorage(
        ScreenRecordingPreferenceKey.bitratePreset,
        store: UserDefaults(suiteName: SharedStorage.appGroup)
    ) private var bitrate = ScreenBitratePreset.highest.rawValue
    @AppStorage("iCloudSyncEnabledV1") private var iCloudSyncEnabled = false

    @EnvironmentObject private var cloudSync: CloudSyncService
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        FeatherPage {
            LazyVStack(alignment: .leading, spacing: 30) {
                appearanceSection
                recordingSection
                syncSection
                privacySection
                aboutSection
            }
        }
        .featherNavigationTitle("设置")
        .onChange(of: iCloudSyncEnabled) { _, enabled in
            guard enabled else { return }
            Task { await cloudSync.sync() }
        }
    }

    private var appearanceSection: some View {
        settingsSection(title: "外观", detail: appearanceDetail) {
            VStack(alignment: .leading, spacing: 14) {
                Label("界面模式", systemImage: "circle.lefthalf.filled")
                    .font(.body.weight(.medium))

                Picker("界面模式", selection: $appearance) {
                    ForEach(AppAppearancePreference.options, id: \.value) { option in
                        Text(option.title).tag(option.value)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 44)
                .accessibilityIdentifier("feather.settings.appearance")
                .accessibilityHint("选择跟随系统、浅色或深色界面")
            }
            .padding(16)
        }
    }

    private var recordingSection: some View {
        settingsSection(title: "录制输出", detail: recordingSummary) {
            VStack(spacing: 0) {
                menuRow(
                    title: "分辨率",
                    detail: "限制输出画面的长边尺寸",
                    icon: "rectangle.expand.vertical",
                    selection: $resolution,
                    values: [ScreenResolutionPreset.p720, .p1080, .p2K, .native]
                        .map { ($0.rawValue, $0.title) },
                    identifier: "feather.settings.resolution"
                )

                FeatherRule().padding(.leading, 58)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        settingIcon("speedometer")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("帧率").font(.body.weight(.medium))
                            Text("更高帧率会增加文件体积")
                                .font(.caption)
                                .foregroundStyle(FeatherColor.secondary(scheme))
                        }
                        Spacer(minLength: 10)
                        Text("\(frameRate) fps")
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { Double(frameRate) },
                            set: { frameRate = ScreenFrameRateLimit.clamp(Int($0.rounded())) }
                        ),
                        in: Double(ScreenFrameRateLimit.minimum)...Double(ScreenFrameRateLimit.maximum),
                        step: 1
                    )
                    .tint(FeatherColor.accent(scheme))
                    .accessibilityLabel("录制帧率")
                    .accessibilityValue("\(frameRate) 帧每秒")
                    .accessibilityIdentifier("feather.settings.frameRate")
                }
                .padding(16)

                FeatherRule().padding(.leading, 58)

                menuRow(
                    title: "编码",
                    detail: "HEVC 更省空间，H.264 兼容性更高",
                    icon: "cpu",
                    selection: $codec,
                    values: [("hevc", "HEVC"), ("h264", "H.264")],
                    identifier: "feather.settings.codec"
                )

                FeatherRule().padding(.leading, 58)

                menuRow(
                    title: "方向",
                    detail: "自动跟随设备，或锁定画面方向",
                    icon: "rectangle.rotate",
                    selection: $orientation,
                    values: ScreenOrientationPreset.allCases.map { ($0.rawValue, $0.title) },
                    identifier: "feather.settings.orientation"
                )

                FeatherRule().padding(.leading, 58)

                menuRow(
                    title: "码率",
                    detail: "最高会依据画面与帧率动态计算",
                    icon: "gauge.with.dots.needle.50percent",
                    selection: $bitrate,
                    values: ScreenBitratePreset.allCases.map { ($0.rawValue, $0.title) },
                    identifier: "feather.settings.bitrate"
                )
            }
        }
    }

    private var syncSection: some View {
        settingsSection(title: "同步", detail: "由你的 iCloud Drive 保存") {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    settingIcon("icloud")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("iCloud Drive").font(.body.weight(.medium))
                        Text("双向合并录屏、录音、字幕和工程文件")
                            .font(.caption)
                            .foregroundStyle(FeatherColor.secondary(scheme))
                    }
                    Spacer(minLength: 12)
                    Toggle("iCloud Drive", isOn: $iCloudSyncEnabled)
                        .labelsHidden()
                        .tint(FeatherColor.accent(scheme))
                        .accessibilityIdentifier("feather.settings.icloud")
                }
                .padding(16)

                FeatherRule().padding(.leading, 58)

                HStack(spacing: 12) {
                    if cloudSync.state == .syncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Circle()
                            .fill(syncStatusColor)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(cloudSync.statusText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FeatherColor.ink(scheme))
                        if let lastSyncDate = cloudSync.lastSyncDate {
                            Text("上次同步：\(lastSyncDate.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(FeatherColor.secondary(scheme))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        Task { await cloudSync.sync() }
                    } label: {
                        FeatherGlassControl(cornerRadius: 13) {
                            Text("立即同步")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(FeatherColor.accent(scheme))
                                .padding(.horizontal, 13)
                                .frame(minHeight: 44)
                        }
                    }
                    .buttonStyle(FeatherPressStyle())
                    .disabled(!iCloudSyncEnabled || cloudSync.state == .syncing)
                    .opacity(iCloudSyncEnabled && cloudSync.state != .syncing ? 1 : 0.45)
                    .accessibilityIdentifier("feather.settings.syncNow")
                }
                .padding(16)
            }
        }
    }

    private var privacySection: some View {
        settingsSection(title: "隐私与法务", detail: "本地处理，不含广告追踪") {
            VStack(spacing: 0) {
                ForEach(Array(legalDocuments.enumerated()), id: \.element.id) { index, document in
                    NavigationLink {
                        FeatherLegalDocumentView(document: document)
                    } label: {
                        HStack(spacing: 14) {
                            settingIcon(document.icon)
                            Text(document.title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(FeatherColor.ink(scheme))
                            Spacer(minLength: 12)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(FeatherColor.secondary(scheme))
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(FeatherPressStyle())
                    .accessibilityIdentifier("feather.settings.legal.\(document.rawValue)")

                    if index < legalDocuments.count - 1 {
                        FeatherRule().padding(.leading, 58)
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MonoFrame")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FeatherColor.ink(scheme))
            Text("版本 \(versionText) · 媒体处理默认在设备上完成")
                .font(.caption)
                .foregroundStyle(FeatherColor.secondary(scheme))
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    private func settingsSection<Content: View>(
        title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FeatherSectionHeader(title, detail: detail)
            FeatherSurface { content() }
        }
    }

    private func menuRow(
        title: String,
        detail: String,
        icon: String,
        selection: Binding<String>,
        values: [(String, String)],
        identifier: String
    ) -> some View {
        HStack(spacing: 14) {
            settingIcon(icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(FeatherColor.secondary(scheme))
            }
            Spacer(minLength: 10)
            Picker(title, selection: selection) {
                ForEach(values, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(FeatherColor.accent(scheme))
            .accessibilityIdentifier(identifier)
        }
        .foregroundStyle(FeatherColor.ink(scheme))
        .padding(16)
        .frame(minHeight: 68)
    }

    private func settingIcon(_ name: String) -> some View {
        FeatherIcon(name: name, size: 19)
            .foregroundStyle(FeatherColor.accent(scheme))
            .frame(width: 28, height: 28)
    }

    private var appearanceDetail: String {
        switch appearance {
        case "light": "始终使用浅色界面"
        case "dark": "始终使用深色界面"
        default: "跟随 iPhone 或 iPad 外观"
        }
    }

    private var recordingSummary: String {
        let resolutionTitle = ScreenResolutionPreset(rawValue: resolution)?.title ?? "设备屏幕"
        return "\(resolutionTitle) · \(frameRate) fps"
    }

    private var legalDocuments: [LegalDocument] {
        [.privacyRights, .userAgreement, .disclaimer, .ffmpeg]
    }

    private var syncStatusColor: Color {
        switch cloudSync.state {
        case .completed: FeatherColor.success
        case .failed, .unavailable: FeatherColor.warning
        case .idle, .syncing: FeatherColor.secondary(scheme)
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}

// MARK: - Onboarding

struct FeatherOnboardingFlow: View {
    private enum Stage { case welcome, permissions }

    private let needsPermissions: Bool
    private let welcomeCompleted: () -> Void
    private let completion: () -> Void
    @State private var stage: Stage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        needsWelcome: Bool,
        needsPermissions: Bool,
        welcomeCompleted: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        self.needsPermissions = needsPermissions
        self.welcomeCompleted = welcomeCompleted
        self.completion = completion
        _stage = State(initialValue: needsWelcome ? .welcome : .permissions)
    }

    var body: some View {
        ZStack {
            FeatherBackdrop()
            switch stage {
            case .welcome:
                FeatherWelcomeView(completion: finishWelcome)
                    .transition(.opacity)
            case .permissions:
                FeatherPermissionView(completion: completion)
                    .transition(.opacity)
            }
        }
        .interactiveDismissDisabled()
    }

    private func finishWelcome() {
        welcomeCompleted()
        guard needsPermissions else {
            completion()
            return
        }
        if reduceMotion {
            stage = .permissions
        } else {
            withAnimation(.easeInOut(duration: 0.20)) { stage = .permissions }
        }
    }
}

private struct FeatherWelcomeView: View {
    let completion: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 12) {
                    Image("mono-record")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)
                    Text("MonoFrame")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Text("本地优先")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FeatherColor.accent(scheme))
                        .padding(.horizontal, 11)
                        .frame(minHeight: 34)
                        .background(
                            FeatherColor.lagoonWash(scheme),
                            in: Capsule(style: .continuous)
                        )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("从录制到成片，\n都在一台设备里。")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(FeatherColor.ink(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("录屏、录音、逐帧编辑与格式转换，默认在设备本地完成。")
                        .font(.body)
                        .foregroundStyle(FeatherColor.secondary(scheme))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                FeatherWelcomeRibbon()

                HStack(alignment: .top, spacing: 18) {
                    welcomeCapability("录制", icon: "record.circle")
                    welcomeCapability("编辑", icon: "scissors")
                    welcomeCapability("导出", icon: "square.and.arrow.up")
                }

                FeatherInlineNotice(
                    message: "不要求账号，不含广告或跨 App 跟踪。你可以随时导出或删除本地作品。",
                    tone: .info
                )

                FeatherPrimaryButton(title: "开始使用", icon: "arrow.right", action: completion)
                    .accessibilityIdentifier("feather.onboarding.continue")
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(FeatherBackdrop())
    }

    private func welcomeCapability(_ title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FeatherIcon(name: icon, size: 21)
                .foregroundStyle(FeatherColor.accent(scheme))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FeatherColor.ink(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct FeatherWelcomeRibbon: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { context in
            GeometryReader { proxy in
                let progress = reduceMotion
                    ? 0.46
                    : context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 4) / 4

                ZStack(alignment: .leading) {
                    VStack(spacing: 12) {
                        ribbonTrack(color: FeatherColor.lagoon, widths: [0.28, 0.20, 0.34])
                        ribbonTrack(color: FeatherColor.coral, widths: [0.18, 0.31, 0.24])
                        FeatherWaveform(active: true, phase: context.date.timeIntervalSinceReferenceDate)
                            .frame(height: 34)
                    }

                    Rectangle()
                        .fill(FeatherColor.ink(scheme))
                        .frame(width: 1.5)
                        .overlay(alignment: .top) {
                            Circle().fill(FeatherColor.coral).frame(width: 8, height: 8)
                        }
                        .offset(x: max(0, proxy.size.width - 2) * progress)
                }
                .padding(18)
                .background(FeatherColor.surface(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .frame(height: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("录制、编辑和音频时间线示意")
    }

    private func ribbonTrack(color: Color, widths: [CGFloat]) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 7) {
                ForEach(Array(widths.enumerated()), id: \.offset) { index, width in
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color.opacity(index == 1 ? 0.42 : 0.78))
                        .frame(width: max(28, proxy.size.width * width))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 38)
    }
}

private struct FeatherPermissionView: View {
    let completion: () -> Void
    @StateObject private var permissions = PermissionCenter()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("只在需要时访问")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(FeatherColor.ink(scheme))
                        .accessibilityAddTraits(.isHeader)
                    Text("照片权限用于保存作品，麦克风权限用于录制声音。两项权限都可以稍后更改。")
                        .font(.body)
                        .foregroundStyle(FeatherColor.secondary(scheme))
                        .lineSpacing(3)
                }

                FeatherSurface {
                    VStack(spacing: 0) {
                        permissionRow(
                            title: "照片",
                            detail: "保存视频与 Live Photo",
                            icon: "photo.on.rectangle",
                            state: permissions.photo
                        )
                        FeatherRule().padding(.leading, 62)
                        permissionRow(
                            title: "麦克风",
                            detail: "录音与录屏时采集你的声音",
                            icon: "microphone",
                            state: permissions.microphone
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label("默认在设备上处理", systemImage: "lock.shield")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(FeatherColor.ink(scheme))
                    Text("只有当你主动使用分享、照片保存或文件导出时，内容才会交给系统中你选择的目标。")
                        .font(.subheadline)
                        .foregroundStyle(FeatherColor.secondary(scheme))
                        .lineSpacing(3)
                }
                .padding(.horizontal, 2)

                if permissions.hasDeniedAccess {
                    FeatherInlineNotice(
                        message: "有权限已关闭或仅允许有限访问。你可以前往系统设置重新选择。",
                        tone: .warning
                    )
                }

                FeatherPrimaryButton(
                    title: permissions.isRequesting ? "正在请求…" : primaryTitle,
                    icon: primaryIcon,
                    isEnabled: !permissions.isRequesting,
                    action: primaryAction
                )
                .accessibilityIdentifier("feather.permissions.primary")

                Button(secondaryTitle, action: completion)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FeatherColor.secondary(scheme))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(FeatherPressStyle())
                    .accessibilityIdentifier("feather.permissions.skip")
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(FeatherBackdrop())
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { permissions.refresh() }
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        icon: String,
        state: PermissionCenter.AccessState
    ) -> some View {
        HStack(spacing: 14) {
            FeatherIcon(name: icon, size: 21)
                .foregroundStyle(FeatherColor.accent(scheme))
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(FeatherColor.secondary(scheme))
            }
            Spacer(minLength: 12)
            Label(state.title, systemImage: state.symbol)
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .foregroundStyle(permissionColor(state))
                .accessibilityLabel("\(title)：\(state.title)")
        }
        .foregroundStyle(FeatherColor.ink(scheme))
        .padding(.horizontal, 16)
        .frame(minHeight: 76)
    }

    private func permissionColor(_ state: PermissionCenter.AccessState) -> Color {
        switch state {
        case .allowed: FeatherColor.success
        case .limited: FeatherColor.warning
        case .denied: FeatherColor.coral
        case .notDetermined: FeatherColor.secondary(scheme)
        }
    }

    private var primaryTitle: String {
        if permissions.hasDeniedAccess { return "打开系统设置" }
        if permissions.hasUndeterminedAccess { return "允许所需权限" }
        return "进入 MonoFrame"
    }

    private var primaryIcon: String {
        if permissions.hasDeniedAccess { return "gearshape" }
        if permissions.hasUndeterminedAccess { return "checkmark.shield" }
        return "arrow.right"
    }

    private var secondaryTitle: String {
        permissions.hasDeniedAccess ? "稍后处理" : "暂时跳过"
    }

    private func primaryAction() {
        if permissions.hasDeniedAccess {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(url)
        } else if permissions.hasUndeterminedAccess {
            Task { await permissions.requestAccess() }
        } else {
            completion()
        }
    }
}

// MARK: - Legal documents

struct FeatherLegalDocumentView: View {
    let document: LegalDocument
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                documentSummary

                ForEach(Array(document.sections.enumerated()), id: \.offset) { index, section in
                    legalSection(section, index: index)
                    if index < document.sections.count - 1 {
                        FeatherRule()
                    }
                }

                if !document.links.isEmpty {
                    externalLinks.padding(.top, 28)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .background(FeatherBackdrop())
        .featherNavigationTitle(document.title)
    }

    private var documentSummary: some View {
        HStack(alignment: .center, spacing: 14) {
            FeatherIcon(name: document.icon, size: 24)
                .foregroundStyle(FeatherColor.accent(scheme))
                .frame(width: 44, height: 44)
                .background(
                    FeatherColor.lagoonWash(scheme),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text("\(document.sections.count) 个章节")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FeatherColor.ink(scheme))
                Text("生效日期 2026.07.19 · 内容可选择复制")
                    .font(.caption)
                    .foregroundStyle(FeatherColor.secondary(scheme))
            }
        }
        .padding(.vertical, 18)
        .accessibilityElement(children: .combine)
    }

    private func legalSection(_ section: LegalSection, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(FeatherColor.ink(scheme))
                .accessibilityAddTraits(.isHeader)
            Text(section.body)
                .font(.body)
                .foregroundStyle(FeatherColor.secondary(scheme))
                .lineSpacing(5)
                .textSelection(.enabled)
        }
        .padding(.vertical, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feather.legal.\(document.rawValue).section.\(index)")
    }

    private var externalLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeatherSectionHeader("相关链接", detail: "将在浏览器中打开")

            FeatherSurface {
                VStack(spacing: 0) {
                    ForEach(Array(document.links.enumerated()), id: \.element.id) { index, item in
                        if let url = URL(string: item.url) {
                            Link(destination: url) {
                                HStack(spacing: 14) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(FeatherColor.ink(scheme))
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 12)
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(FeatherColor.accent(scheme))
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 58)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(FeatherPressStyle())
                            .accessibilityHint("在浏览器中打开")

                            if index < document.links.count - 1 {
                                FeatherRule().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }
}
