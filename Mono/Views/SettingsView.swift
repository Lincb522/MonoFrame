import SwiftUI
import UIKit

struct SettingsView: View {
    private enum Category: String, CaseIterable {
        case capture = "录屏"
        case audio = "音频"
        case appearance = "外观"
        case system = "系统"

        var icon: String {
            switch self {
            case .capture: "record.circle"
            case .audio: "waveform"
            case .appearance: "circle.lefthalf.filled"
            case .system: "gearshape"
            }
        }
    }

    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("audioQuality", store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var audioQuality = "high"
    @AppStorage("screenCodec", store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var screenCodec = "hevc"
    @AppStorage(ScreenRecordingPreferenceKey.resolution, store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var screenResolution = ScreenResolutionPreset.native.rawValue
    @AppStorage(ScreenRecordingPreferenceKey.frameRate, store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var screenFrameRate = 60
    @AppStorage(ScreenRecordingPreferenceKey.orientation, store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var screenOrientation = ScreenOrientationPreset.automatic.rawValue
    @AppStorage(ScreenRecordingPreferenceKey.bitratePreset, store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var screenBitratePreset = ScreenBitratePreset.highest.rawValue
    @State private var category: Category = .capture
    @State private var confirmCleanup = false
    @State private var cleanupResult: String?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                settingsNavigator
                activeSettings
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .background(Color.clear)
    }

    private var header: some View {
        MonoPageHeader("设置") {
            MonoIcon(category.icon, size: 22, weight: 2.1)
        }
    }

    private var categoryPicker: some View {
        HStack(spacing: 6) {
            ForEach(Category.allCases, id: \.self) { item in
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.92)) { category = item }
                } label: {
                    VStack(spacing: 7) {
                        MonoIcon(item.icon, size: 18, weight: category == item ? 2.2 : 1.8)
                            .foregroundStyle(category == item ? Color.white : MonoTheme.ink(scheme))
                            .frame(width: 46, height: 46)
                            .background(category == item ? MonoTheme.primary : MonoTheme.surface(scheme))
                            .clipShape(Circle())
                        Text(item.rawValue)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var settingsNavigator: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [MonoTheme.lavender.opacity(0.20), MonoTheme.cyan.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(MonoTheme.mint.opacity(0.18))
                .frame(width: 150, height: 150)
                .offset(x: 135, y: -52)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(categoryDetail(category).uppercased())
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(MonoTheme.primary)
                        Text(summaryTitle)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .tracking(-0.6)
                    }
                    Spacer()
                    MonoIcon(category.icon, size: 26, weight: 2)
                        .foregroundStyle(MonoTheme.primary)
                }

                HStack(spacing: 8) {
                    ForEach(Category.allCases, id: \.self) { item in
                        Button {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) { category = item }
                        } label: {
                            HStack(spacing: category == item ? 6 : 0) {
                                MonoIcon(item.icon, size: 16, weight: 2)
                                if category == item {
                                    Text(item.rawValue)
                                        .font(.system(.caption, design: .rounded, weight: .black))
                                }
                            }
                            .foregroundStyle(category == item ? .white : MonoTheme.ink(scheme))
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .glassEffect(
                                .regular.tint(category == item ? MonoTheme.primary : Color.clear).interactive(),
                                in: .capsule
                            )
                        }
                        .buttonStyle(MonoSpringPressStyle())
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, minHeight: 176)
        .glassEffect(.regular.tint(MonoTheme.primary.opacity(0.07)), in: .rect(cornerRadius: 32))
    }

    private func categoryDetail(_ item: Category) -> String {
        switch item {
        case .capture: "录制参数"
        case .audio: "声音处理"
        case .appearance: "显示主题"
        case .system: "存储与协议"
        }
    }

    private var activeSummary: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text(summaryTitle)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            MonoIcon(category.icon, size: 23, weight: 1.8)
        }
        .foregroundStyle(MonoTheme.ink(scheme))
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(
                    colors: [MonoTheme.lavender.opacity(0.18), MonoTheme.primary.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(MonoTheme.mint.opacity(0.20))
                    .frame(width: 120, height: 120)
                    .blur(radius: 40)
                    .offset(x: 150, y: -50)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(MonoTheme.primary.opacity(0.12), lineWidth: 1) }
    }

    @ViewBuilder
    private var activeSettings: some View {
        VStack(spacing: 0) {
            switch category {
            case .capture: captureSettings
            case .audio: audioSettings
            case .appearance: appearanceSettings
            case .system: systemSettings
            }
        }
        .padding(.horizontal, 16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var captureSettings: some View {
        Group {
            settingPicker(
                title: "分辨率", icon: "rectangle.expand.vertical",
                selection: $screenResolution,
                values: ScreenResolutionPreset.allCases.map { ($0.rawValue, $0.title) }
            )
            rowDivider
            VStack(spacing: 7) {
                HStack {
                    MonoLabel("帧率", icon: "speedometer", iconSize: 17)
                        .font(.system(.subheadline, design: .rounded, weight: .black))
                    Spacer()
                    Text("\(screenFrameRate) FPS")
                        .font(.system(.caption, design: .monospaced, weight: .black))
                }
                Slider(
                    value: Binding(
                        get: { Double(screenFrameRate) },
                        set: { screenFrameRate = Int($0.rounded()) }
                    ),
                    in: Double(ScreenFrameRateLimit.minimum)...Double(ScreenFrameRateLimit.maximum),
                    step: 1
                )
                .tint(MonoTheme.coral)
            }
            .frame(minHeight: 72)
            rowDivider
            settingPicker(
                title: "方向", icon: "rotate.right",
                selection: $screenOrientation,
                values: ScreenOrientationPreset.allCases.map { ($0.rawValue, $0.title) }
            )
            rowDivider
            settingPicker(
                title: "编码", icon: "cpu",
                selection: $screenCodec,
                values: [("hevc", "HEVC"), ("h264", "H.264")]
            )
            rowDivider
            settingPicker(
                title: "码率", icon: "gauge.with.dots.needle.67percent",
                selection: $screenBitratePreset,
                values: ScreenBitratePreset.allCases.map { ($0.rawValue, $0.title) }
            )
        }
    }

    private var audioSettings: some View {
        Group {
            settingPicker(
                title: "录音质量", icon: "waveform",
                selection: $audioQuality,
                values: [("standard", "128K"), ("high", "256K")]
            )
            rowDivider
            infoRow(title: "采样率", value: "48 KHZ", icon: "waveform.path")
            rowDivider
            infoRow(title: "输出格式", value: "AAC", icon: "doc.badge.gearshape")
            rowDivider
            infoRow(title: "伴奏混音", value: "可用", icon: "music.note.list")
        }
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("界面模式")
                .font(.system(.subheadline, design: .rounded, weight: .black))
            HStack(spacing: 8) {
                appearanceButton(value: "system", title: "自动", icon: "circle.lefthalf.filled")
                appearanceButton(value: "light", title: "浅色", icon: "sun.max.fill")
                appearanceButton(value: "dark", title: "深色", icon: "moon.fill")
            }
        }
        .frame(minHeight: 126)
    }

    private var systemSettings: some View {
        Group {
            Button { openSystemSettings() } label: {
                actionRow(title: "应用权限", value: "系统设置", icon: "hand.raised.fill")
            }
            .buttonStyle(.plain)
            rowDivider
            Button(role: .destructive) {
                withAnimation(.easeOut(duration: 0.18)) { confirmCleanup.toggle() }
            } label: {
                actionRow(
                    title: "清理转码缓存",
                    value: cleanupResult.map { "已清理 \($0) 项" } ?? "",
                    icon: "trash"
                )
                .foregroundStyle(MonoTheme.coral)
            }
            .buttonStyle(.plain)
            if confirmCleanup {
                rowDivider
                cleanupConfirmation
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            rowDivider
            legalLink(.ffmpeg)
            rowDivider
            legalLink(.userAgreement)
            rowDivider
            legalLink(.disclaimer)
            rowDivider
            legalLink(.privacyRights)
        }
    }

    private func settingPicker<Value: Hashable>(
        title: String,
        icon: String,
        selection: Binding<Value>,
        values: [(Value, String)]
    ) -> some View {
        MonoSelectionField(
            title: title,
            symbol: icon,
            selection: selection,
            options: values.map { value in
                MonoSelectionOption(value: value.0, title: value.1)
            }
        )
    }

    private var cleanupConfirmation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                MonoIcon("trash.fill", size: 15, weight: 2.1)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(MonoTheme.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("确认清理转码缓存？")
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                Spacer()
            }
            HStack(spacing: 8) {
                Button("取消") {
                    withAnimation(.easeOut(duration: 0.18)) { confirmCleanup = false }
                }
                .font(.system(.caption, design: .rounded, weight: .black))
                .foregroundStyle(MonoTheme.ink(scheme))
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(MonoTheme.background(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button("清理") {
                    confirmCleanup = false
                    cleanup()
                }
                .font(.system(.caption, design: .rounded, weight: .black))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(MonoTheme.coral)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    private func appearanceButton(value: String, title: String, icon: String) -> some View {
        Button { appearance = value } label: {
            VStack(spacing: 8) {
                MonoIcon(icon, size: 18, weight: 2.1)
                    .font(.system(size: 18, weight: .black))
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .black))
            }
            .frame(maxWidth: .infinity, minHeight: 70)
            .foregroundStyle(
                appearance == value ? MonoTheme.background(scheme) : MonoTheme.ink(scheme)
            )
            .background(appearance == value ? MonoTheme.ink(scheme) : MonoTheme.background(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func infoRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            MonoIcon(icon, size: 18, weight: 2.1)
                .font(.system(size: 15, weight: .black))
                .frame(width: 24)
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .black))
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced, weight: .black))
                .foregroundStyle(MonoTheme.muted(scheme))
        }
        .frame(minHeight: 58)
    }

    private func actionRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            MonoIcon(icon, size: 18, weight: 2.1)
                .font(.system(size: 15, weight: .black))
                .frame(width: 24)
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .black))
            Spacer()
            if !value.isEmpty {
                Text(value)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(MonoTheme.muted(scheme))
            }
            MonoIcon("arrow.up.right", size: 17, weight: 2.1)
                .font(.system(size: 11, weight: .black))
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }

    private func legalLink(_ document: LegalDocument) -> some View {
        NavigationLink {
            LegalDocumentView(document: document)
        } label: {
            HStack(spacing: 12) {
                MonoIcon(document.icon, size: 18, weight: 2.1)
                    .font(.system(size: 15, weight: .black))
                    .frame(width: 24)
                Text(document.title)
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                Spacer()
                MonoIcon("chevron.right", size: 15, weight: 2.2)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(MonoTheme.muted(scheme))
            }
            .foregroundStyle(MonoTheme.ink(scheme))
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Divider().overlay(MonoTheme.muted(scheme).opacity(0.18))
    }

    private var summaryTitle: String {
        switch category {
        case .capture:
            let resolution = ScreenResolutionPreset(rawValue: screenResolution)?.title ?? "设备屏幕"
            return "\(resolution) · \(screenFrameRate) FPS"
        case .audio: return audioQuality == "high" ? "48 KHZ · 256K" : "48 KHZ · 128K"
        case .appearance:
            return [("system", "跟随系统"), ("light", "浅色"), ("dark", "深色")]
                .first(where: { $0.0 == appearance })?.1 ?? "跟随系统"
        case .system: return "权限 · 存储 · 法律"
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func cleanup() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: SharedStorage.transcodeDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        urls.forEach { try? FileManager.default.removeItem(at: $0) }
        cleanupResult = "\(urls.count)"
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
