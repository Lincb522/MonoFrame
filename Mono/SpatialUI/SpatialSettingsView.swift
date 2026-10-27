import SwiftUI

struct SpatialSettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("screenCodec", store: UserDefaults(suiteName: SharedStorage.appGroup)) private var codec = "hevc"
    @AppStorage(ScreenRecordingPreferenceKey.resolution, store: UserDefaults(suiteName: SharedStorage.appGroup)) private var resolution = ScreenResolutionPreset.native.rawValue
    @AppStorage(ScreenRecordingPreferenceKey.frameRate, store: UserDefaults(suiteName: SharedStorage.appGroup)) private var frameRate = 60
    @AppStorage(ScreenRecordingPreferenceKey.orientation, store: UserDefaults(suiteName: SharedStorage.appGroup)) private var orientation = ScreenOrientationPreset.automatic.rawValue

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SpatialHeading(title: "设置", detail: "当前参数立即生效").padding(.bottom, 28)
                sectionTitle("录屏")
                inlineChoice("画质", values: ScreenResolutionPreset.allCases.map { ($0.rawValue, $0.title) }, selection: $resolution)
                hairline
                VStack(spacing: 10) {
                    HStack { Text("帧率").bold(); Spacer(); Text("\(frameRate) FPS").font(.caption.monospaced()).foregroundStyle(.secondary) }
                    Slider(value: Binding(get: { Double(frameRate) }, set: { frameRate = Int($0.rounded()) }), in: 15...60, step: 1).tint(SpatialColor.sea)
                }.padding(.vertical, 17)
                hairline
                inlineChoice("编码", values: [("hevc", "HEVC"), ("h264", "H.264")], selection: $codec)
                hairline
                inlineChoice("方向", values: ScreenOrientationPreset.allCases.map { ($0.rawValue, $0.title) }, selection: $orientation)

                sectionTitle("外观").padding(.top, 30)
                inlineChoice("模式", values: [("system", "自动"), ("light", "浅色"), ("dark", "深色")], selection: $appearance)

                sectionTitle("关于").padding(.top, 30)
                NavigationLink { LegalDocumentView(document: .privacyRights) } label: { linkRow("隐私权利", "hand.raised") }.buttonStyle(.plain)
                hairline
                NavigationLink { LegalDocumentView(document: .ffmpeg) } label: { linkRow("FFmpeg 开源协议", "doc.text") }.buttonStyle(.plain)
                hairline
                NavigationLink { LegalDocumentView(document: .userAgreement) } label: { linkRow("用户协议", "checkmark.shield") }.buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 34)
        }.scrollIndicators(.hidden)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(.title3, design: .rounded, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 10)
    }

    private func inlineChoice(_ title: String, values: [(String, String)], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(.subheadline, design: .rounded, weight: .bold))
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(values, id: \.0) { value, label in
                        Button { selection.wrappedValue = value } label: {
                            Text(label).font(.system(.caption, design: .rounded, weight: .bold)).lineLimit(1)
                                .foregroundStyle(selection.wrappedValue == value ? .white : .primary)
                                .padding(.horizontal, 15).frame(minHeight: 40)
                                .spatialGlass(Capsule(), tint: selection.wrappedValue == value ? SpatialColor.seaDeep : nil, interactive: true)
                        }.buttonStyle(SpatialGlassButtonStyle())
                    }
                }
            }.scrollIndicators(.hidden)
        }.padding(.vertical, 16)
    }

    private var hairline: some View { Divider().opacity(0.18) }
    private func linkRow(_ title: String, _ symbol: String) -> some View {
        HStack { Label(title, systemImage: symbol).font(.system(.body, design: .rounded, weight: .semibold)); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.secondary) }
            .foregroundStyle(.primary).frame(minHeight: 58).contentShape(Rectangle())
    }
}
