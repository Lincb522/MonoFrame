import SwiftUI

struct PearlPermissionView: View {
    var completion: (() -> Void)? = nil
    @StateObject private var permissions = PermissionCenter()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        PearlSecondaryLayout(title: "权限") {
            PearlPage(maxWidth: 660) {
                VStack(alignment: .leading, spacing: 24) {
                    permissionRow("麦克风", detail: "用于录音及录屏收音", glyph: .microphone, state: permissions.microphone)
                    PearlHairline()
                    permissionRow("相册", detail: "用于保存视频与 Live Photo", glyph: .image, state: permissions.photo)
                    PearlHairline()
                    HStack(alignment: .top, spacing: 14) {
                        tile(.video)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text("屏幕录制").font(.headline); Spacer(); Text("每次确认").font(.caption).foregroundStyle(PearlColor.secondary(scheme)) }
                            Text("点击开始录屏后，在系统面板中确认。")
                                .font(.subheadline).foregroundStyle(PearlColor.secondary(scheme)).fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(.vertical, 12)
                    PearlHairline()
                    Text("权限由系统管理，可随时在设置中更改。")
                        .font(.caption).foregroundStyle(PearlColor.secondary(scheme)).fixedSize(horizontal: false, vertical: true)
                    if permissions.hasDeniedAccess { PearlInlineNotice(message: "有权限已关闭或为有限访问，请在系统设置中更改后重试。", tone: .warning) }
                    Button(action: permissionAction) {
                        PearlPrimaryLabel(title: permissions.isRequesting ? "正在请求权限" : permissions.hasUndeterminedAccess && !permissions.hasDeniedAccess ? "允许所需权限" : "打开系统设置", glyph: .settings, busy: permissions.isRequesting)
                    }.buttonStyle(PearlPressStyle()).disabled(permissions.isRequesting).padding(.top, 30)
                    if let completion {
                        Button(permissions.hasUndeterminedAccess || permissions.hasDeniedAccess ? "稍后设置" : "完成", action: completion)
                            .font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 48).buttonStyle(PearlPressStyle())
                            .accessibilityIdentifier("pearl.permissions.continue")
                    }
                }.padding(.top, 15)
            }
        }
        .onAppear(perform: permissions.refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { permissions.refresh() } }

    }
    private func permissionRow(_ title: String, detail: String, glyph: PearlGlyphName, state: PermissionCenter.AccessState) -> some View {
        HStack(alignment: .top, spacing: 14) {
            tile(glyph)
            VStack(alignment: .leading, spacing: 9) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(PearlColor.secondary(scheme)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 7) {
                    PearlGlyph(state == .allowed ? .check : state == .denied ? .close : .info, size: 16)
                    Text(state.title).font(.caption.weight(.medium))
                }.foregroundStyle(state == .denied ? PearlColor.danger(scheme) : PearlColor.accent(scheme))
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 10).accessibilityElement(children: .combine)
    }
    private func tile(_ glyph: PearlGlyphName) -> some View {
        PearlGlyph(glyph, size: 25).foregroundStyle(PearlColor.accent(scheme)).frame(width: 52, height: 52)
            .background(PearlColor.elevated(scheme), in: Circle())
    }
    private func permissionAction() {
        if permissions.hasUndeterminedAccess && !permissions.hasDeniedAccess { Task { await permissions.requestAccess() } }
        else if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

struct PearlOnboardingView: View {
    let needsWelcome: Bool
    let completeWelcome: () -> Void
    let completion: () -> Void
    @State private var showingPermissions = false
    @State private var document: LegalDocument?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Group {
            if showingPermissions || !needsWelcome { PearlPermissionView(completion: completion) }
            else {
                PearlPage(maxWidth: 520) {
                    VStack(alignment: .leading, spacing: 28) {
                        HStack(spacing: 12) {
                            PearlGlyph(.record, size: 27).foregroundStyle(PearlColor.onAccent(scheme)).frame(width: 53, height: 53)
                                .background(PearlColor.action(scheme), in: Circle())
                            Text("MonoFrame").font(.headline)
                        }.padding(.top, 20)
                        Text("开始使用 MonoFrame").font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                        PearlDotMatrix(progress: 0, columns: 7, rows: 3).aspectRatio(7.0 / 3.0, contentMode: .fit).accessibilityHidden(true)
                        VStack(spacing: 0) {
                            capability("录屏与录音", .video)
                            PearlHairline()
                            capability("视频与音频剪辑", .edit)
                            PearlHairline()
                            capability("格式转换与导出", .export)
                        }
                        Button { completeWelcome(); showingPermissions = true } label: { PearlPrimaryLabel(title: "开始使用", glyph: .chevronRight) }
                            .buttonStyle(PearlPressStyle()).accessibilityIdentifier("pearl.onboarding.start")
                        HStack(spacing: 18) {
                            Button("用户协议") { document = .userAgreement }
                            Button("隐私权利") { document = .privacyRights }
                        }.font(.caption).frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
        }
        .background(PearlBackdrop()).interactiveDismissDisabled()
        .sheet(item: $document) { PearlLegalView(document: $0) }

    }
    private func capability(_ title: String, _ glyph: PearlGlyphName) -> some View {
        HStack(spacing: 17) { PearlGlyph(glyph, size: 22); Text(title).font(.body.weight(.medium)); Spacer() }
            .frame(minHeight: 60).foregroundStyle(PearlColor.ink(scheme))
    }
}

struct PearlLegalView: View {
    let document: LegalDocument
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        PearlSecondaryLayout(title: document.title) {
            PearlPage(maxWidth: 660) {
                VStack(alignment: .leading, spacing: 32) {
                    ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(section.title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                            Text(section.body).font(.body).lineSpacing(7).foregroundStyle(PearlColor.secondary(scheme))
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                    }
                    ForEach(Array(document.links.enumerated()), id: \.offset) { _, link in
                        if let url = URL(string: link.url) {
                            Link(destination: url) {
                                HStack { Text(link.title).fixedSize(horizontal: false, vertical: true); Spacer(); PearlGlyph(.export, size: 18) }.frame(minHeight: 48)
                            }
                        }
                    }
                }.padding(.top, 20)
            }
        }
    }
}

struct PearlLyricReadingLine: Identifiable {
    let id: Int
    let time: TimeInterval?
    let text: String
}

struct PearlLyricReadingView: View {
    var title = "歌词"
    let lines: [PearlLyricReadingLine]
    var currentIndex: Int? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        PearlSecondaryLayout(title: title) {
            if lines.isEmpty { PearlEmptyState(glyph: .document, title: "还没有歌词", message: "导入歌词文件后，会在这里完整显示。") }
            else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 34) {
                            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                                Text(line.text).font(.title3.weight(index == currentIndex ? .semibold : .regular))
                                    .foregroundStyle(index == currentIndex ? PearlColor.accent(scheme) : PearlColor.secondary(scheme))
                                    .multilineTextAlignment(.center).lineSpacing(9).fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity).textSelection(.enabled).id(index)
                                    .accessibilityAddTraits(index == currentIndex ? .isSelected : [])
                                    .accessibilityIdentifier("pearl.lyrics.line.\(line.id)")
                            }
                        }.frame(maxWidth: 660).frame(maxWidth: .infinity).padding(.horizontal, 28).padding(.vertical, 80)
                    }.scrollIndicators(.hidden)
                        .onAppear { scroll(proxy) }.onChange(of: currentIndex) { _, _ in scroll(proxy) }
                }
            }
        }
    }
    private func scroll(_ proxy: ScrollViewProxy) {
        guard let currentIndex, lines.indices.contains(currentIndex) else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(currentIndex, anchor: .center) }
    }
}
