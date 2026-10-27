import SwiftUI

struct PearlSettingsView: View {
    @AppStorage(PearlAppearance.storageKey) private var appearance = PearlAppearance.defaultValue
    @AppStorage("iCloudSyncEnabledV1") private var cloudEnabled = false
    @EnvironmentObject private var cloud: CloudSyncService
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        PearlSecondaryLayout(title: "设置") {
            PearlPage(maxWidth: 680) {
                VStack(alignment: .leading, spacing: 30) {
                    Text("偏好设置").font(.largeTitle.weight(.bold))
                    VStack(alignment: .leading, spacing: 14) {
                        Text("外观").font(.title2.weight(.bold))
                        HStack(spacing: 18) {
                            PearlAppearancePreview(dark: false)
                            PearlAppearancePreview(dark: true)
                        }.frame(maxWidth: .infinity).accessibilityHidden(true)
                        Picker("外观", selection: $appearance) {
                            ForEach(PearlAppearance.options, id: \.0) { value, title in Text(title).tag(value) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("pearl.settings.appearance")
                    }
                    Text("录制与存储").font(.title2.weight(.bold))
                    settingsGroup {
                        destination("录制参数", glyph: .video, route: .recordingSettings)
                        PearlHairline()
                        destination("权限", glyph: .shield, route: .permissions)
                        PearlHairline()
                        Toggle(isOn: $cloudEnabled) {
                            HStack(spacing: 13) {
                                PearlGlyph(.cloud)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("iCloud Drive")
                                    Text(cloudEnabled ? cloud.statusText : "未开启").font(.caption).foregroundStyle(PearlColor.secondary(scheme))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }.padding(.vertical, 12).tint(PearlColor.accent(scheme))
                        PearlHairline()
                        information("默认保存位置", glyph: .folder, value: "App 内素材库")
                        PearlHairline()
                        information("文件命名", glyph: .document, value: "日期时间")
                    }
                    Text("关于 MonoFrame").font(.title2.weight(.bold))
                    settingsGroup {
                        ForEach(Array([LegalDocument.privacyRights, .userAgreement, .disclaimer, .ffmpeg].enumerated()), id: \.element) { index, document in
                            destination(document.title, glyph: document == .ffmpeg ? .code : document == .privacyRights ? .shield : .document, route: .legal(document))
                            if index < 3 { PearlHairline() }
                        }
                    }
                    Text(version).font(.caption).foregroundStyle(PearlColor.secondary(scheme)).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .onChange(of: cloudEnabled) { _, enabled in if enabled { Task { await cloud.sync() } } }

    }
    private func destination(_ title: String, glyph: PearlGlyphName, route: PearlRoute) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 13) {
                PearlGlyph(glyph, size: 22)
                Text(title).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                PearlGlyph(.chevronRight, size: 15)
            }.frame(minHeight: typeSize.isAccessibilitySize ? 70 : 51).foregroundStyle(PearlColor.ink(scheme))
        }.buttonStyle(PearlPressStyle()).accessibilityIdentifier("pearl.settings.\(title)")
    }
    private func information(_ title: String, glyph: PearlGlyphName, value: String) -> some View {
        PearlPlainRow(title) { Text(value).font(.subheadline).foregroundStyle(PearlColor.secondary(scheme)) }
    }
    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
    }
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(v) (\(b))"
    }
}

private struct PearlAppearancePreview: View {
    let dark: Bool
    private var scheme: ColorScheme { dark ? .dark : .light }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(dark ? "深色" : "浅色").font(.subheadline.weight(.semibold)).foregroundStyle(PearlColor.ink(scheme))
            Text("00").font(.system(size: 52, weight: .bold)).foregroundStyle(PearlColor.display(scheme))
            PearlDotMatrix(progress: 0.35, columns: 6, rows: 2, active: true).frame(height: 44)
        }.padding(18).frame(maxWidth: .infinity)
            .background(PearlColor.background(scheme), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(PearlColor.hairline(scheme), lineWidth: 1) }
            .environment(\.colorScheme, scheme)
    }
}

struct PearlRecordingSettingsView: View {
    @AppStorage("screenCodec", store: UserDefaults(suiteName: SharedStorage.appGroup)) private var codec = "hevc"
    @AppStorage(ScreenRecordingPreferenceKey.resolution, store: UserDefaults(suiteName: SharedStorage.appGroup)) private var resolution = ScreenResolutionPreset.p1080.rawValue
    @AppStorage(ScreenRecordingPreferenceKey.frameRate, store: UserDefaults(suiteName: SharedStorage.appGroup)) private var frameRate = 60
    @AppStorage(ScreenRecordingPreferenceKey.orientation, store: UserDefaults(suiteName: SharedStorage.appGroup)) private var orientation = ScreenOrientationPreset.automatic.rawValue
    @AppStorage(ScreenRecordingPreferenceKey.bitratePreset, store: UserDefaults(suiteName: SharedStorage.appGroup)) private var bitrate = ScreenBitratePreset.highest.rawValue
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        PearlSecondaryLayout(title: "录制参数") {
            PearlPage(maxWidth: 680) {
                VStack(spacing: 0) {
                    menu("分辨率", selection: $resolution, options: [ScreenResolutionPreset.p720, .p1080, .p2K, .native].map { ($0.rawValue, $0.title) })
                    PearlHairline()
                    menu("帧率", selection: Binding(get: { String(frameRate) }, set: { frameRate = ScreenFrameRateLimit.clamp(Int($0) ?? 60) }), options: [("24", "24 fps"), ("30", "30 fps"), ("60", "60 fps")])
                    PearlHairline()
                    menu("编码", selection: $codec, options: [("hevc", "HEVC"), ("h264", "H.264")])
                    PearlHairline()
                    menu("方向", selection: $orientation, options: ScreenOrientationPreset.allCases.map { ($0.rawValue, $0.title) })
                    PearlHairline()
                    menu("码率", selection: $bitrate, options: ScreenBitratePreset.allCases.map { ($0.rawValue, $0.title) })
                    PearlHairline().padding(.vertical, 24)
                    PearlPlainRow("麦克风") { PearlRowValue(value: "跟随系统面板", navigates: false) }
                    Text("开始录屏后，在系统面板中开启麦克风。")
                        .font(.caption).foregroundStyle(PearlColor.secondary(scheme)).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 20)
                    PearlHairline()
                    PearlPlainRow("系统声音") { PearlRowValue(value: "开启", navigates: false) }
                    PearlInlineNotice(message: "修改将在下次录制时生效。").padding(.top, 38)
                }
            }
        }
    }
    private func menu(_ title: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        Menu {
            ForEach(options, id: \.0) { value, label in Button(label) { selection.wrappedValue = value } }
        } label: { PearlPlainRow(title) { PearlRowValue(value: options.first(where: { $0.0 == selection.wrappedValue })?.1 ?? "—") } }
            .buttonStyle(PearlPressStyle()).accessibilityLabel(title).accessibilityValue(options.first(where: { $0.0 == selection.wrappedValue })?.1 ?? "—")
    }
}
