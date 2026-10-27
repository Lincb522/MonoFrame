import SwiftUI
import UIKit

struct RailOnboardingFlow: View {
    private enum Stage { case welcome, permissions }
    let needsPermissions: Bool
    let welcomeCompleted: () -> Void
    let completion: () -> Void
    @State private var stage: Stage

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
        Group {
            switch stage {
            case .welcome:
                RailWelcomeView {
                    welcomeCompleted()
                    if needsPermissions { withAnimation(.easeOut(duration: 0.22)) { stage = .permissions } }
                    else { completion() }
                }
            case .permissions:
                RailPermissionView(completion: completion)
            }
        }
        .transition(.opacity)
    }
}

private struct RailWelcomeView: View {
    let completion: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RailBackground()
            VStack(spacing: 0) {
                HStack {
                    Text("MONOFRAME").font(.system(size: 12, weight: .black, design: .monospaced))
                    Spacer()
                    RailStatus(text: "LOCAL FIRST")
                }
                Spacer(minLength: 24)
                welcomeTrack
                VStack(alignment: .leading, spacing: 8) {
                    Text("把每一帧，\n留在你的轨道上")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .tracking(-1.1)
                        .foregroundStyle(RailColor.ink(scheme))
                    Text("录屏、录音、逐帧剪辑与多格式转码，全部在设备端完成。")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(RailColor.secondary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 26)
                Spacer(minLength: 24)
                Button(action: completion) {
                    HStack { Text("进入工作台"); Spacer(); RailGlyph(systemName: "arrow.right") }
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .padding(.horizontal, 18).frame(maxWidth: .infinity, minHeight: 58)
                }
                .buttonStyle(RailPrimaryButtonStyle())
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 18)
            .frame(maxWidth: 760)
        }
        .interactiveDismissDisabled()
    }

    private var welcomeTrack: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { context in
            let phase = reduceMotion ? 0.45 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3
            VStack(spacing: 0) {
                HStack {
                    Text("MASTER TIMELINE").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.54))
                    Spacer(); Text("00:12:48").font(.caption.monospaced().bold()).foregroundStyle(.white.opacity(0.70))
                }
                .padding(.horizontal, 17).frame(height: 54)
                ZStack {
                    VStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 9).fill(RailColor.blue).frame(height: 50).padding(.trailing, 42)
                        RoundedRectangle(cornerRadius: 9).fill(RailColor.coral.opacity(0.82)).frame(height: 38).padding(.leading, 72)
                        HStack(alignment: .center, spacing: 3) {
                            ForEach(0..<30, id: \.self) { index in
                                let level = abs(sin(Double(index) * 0.5 + phase * 9))
                                Capsule().fill(.white.opacity(0.30)).frame(maxWidth: .infinity).frame(height: 4 + level * 34)
                            }
                        }.frame(height: 42)
                    }
                    Rectangle().fill(.white).frame(width: 2).overlay(alignment: .top) { Circle().fill(RailColor.coral).frame(width: 10, height: 10) }
                        .offset(x: -140 + phase * 280)
                }
                .padding(17)
                RailTimelineTicks(count: 24, tint: RailColor.coral).padding(.horizontal, 17).padding(.bottom, 16)
            }
            .background(Color(red: 0.055, green: 0.06, blue: 0.075))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(minHeight: 270)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("MonoFrame 本地媒体工作台")
    }
}

private struct RailPermissionView: View {
    let completion: () -> Void
    @StateObject private var permissions = PermissionCenter()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RailBackground()
            VStack(spacing: 22) {
                RailPageHeader(title: "只开启必要权限") {
                    RailStatus(text: "2 ITEMS", tint: RailColor.blue)
                }

                VStack(spacing: 0) {
                    permissionLane("照片", detail: "保存视频与 Live Photo", symbol: "photo.on.rectangle", state: permissions.photo, tint: RailColor.blue)
                    RailHairline().padding(.leading, 72)
                    permissionLane("麦克风", detail: "录制你的声音", symbol: "mic", state: permissions.microphone, tint: RailColor.coral)
                }
                .background(RailColor.surface(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("PRIVACY ROUTE").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.50))
                    HStack(spacing: 8) {
                        routeNode("输入", "iphone")
                        routeLine
                        routeNode("本地处理", "cpu")
                        routeLine
                        routeNode("你的文件", "folder")
                    }
                }
                .padding(18)
                .background(Color(red: 0.055, green: 0.06, blue: 0.075))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Spacer()

                Button { primaryAction() } label: {
                    Group { if permissions.isRequesting { ProgressView().tint(.white) } else { Text(primaryTitle) } }
                        .font(.system(.headline, design: .rounded, weight: .bold)).frame(maxWidth: .infinity, minHeight: 58)
                }
                .buttonStyle(RailPrimaryButtonStyle())
                .disabled(permissions.isRequesting)

                Button(permissions.hasDeniedAccess ? "完成" : "稍后") { completion() }
                    .font(.system(.subheadline, design: .rounded, weight: .bold)).foregroundStyle(RailColor.secondary(scheme)).frame(minHeight: 44)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 18)
            .frame(maxWidth: 760)
        }
        .interactiveDismissDisabled()
        .onChange(of: scenePhase) { _, phase in if phase == .active { permissions.refresh() } }
    }

    private func permissionLane(_ title: String, detail: String, symbol: String, state: PermissionCenter.AccessState, tint: Color) -> some View {
        HStack(spacing: 14) {
            RailGlyph(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(.white).frame(width: 44, height: 44).background(tint).clipShape(RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(.headline, design: .rounded, weight: .bold)); Text(detail).font(.caption).foregroundStyle(RailColor.secondary(scheme)) }
            Spacer()
            RailLabel(state.title, systemImage: state.symbol).labelStyle(.iconOnly).font(.system(size: 20, weight: .bold)).foregroundStyle(state == .allowed ? RailColor.mint : RailColor.secondary(scheme))
        }
        .foregroundStyle(RailColor.ink(scheme)).padding(.horizontal, 14).frame(minHeight: 76)
    }

    private func routeNode(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 7) { RailGlyph(systemName: symbol).font(.system(size: 18, weight: .bold)); Text(title).font(.system(size: 10, weight: .bold, design: .rounded)) }
            .foregroundStyle(.white).frame(width: 72)
    }

    private var routeLine: some View { Rectangle().fill(RailColor.coral).frame(maxWidth: .infinity, minHeight: 2, maxHeight: 2) }
    private var primaryTitle: String { permissions.hasDeniedAccess ? "打开系统设置" : permissions.hasUndeterminedAccess ? "继续" : "进入 MonoFrame" }

    private func primaryAction() {
        if permissions.hasDeniedAccess {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        } else if !permissions.hasUndeterminedAccess { completion() }
        else {
            Task {
                await permissions.requestAccess()
                if !permissions.hasDeniedAccess && !permissions.hasUndeterminedAccess { completion() }
            }
        }
    }
}

struct RailLegalDocumentView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RailBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        RailIconButton(symbol: "xmark", title: nil) { dismiss() }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.title).font(.system(.title2, design: .rounded, weight: .heavy))
                            Text("MONOFRAME DOCUMENT").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(RailColor.secondary(scheme))
                        }
                    }
                    documentIndex
                    ForEach(Array(document.sections.enumerated()), id: \.offset) { index, section in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(String(format: "%02d", index + 1)).font(.caption.monospaced().bold()).foregroundStyle(RailColor.coral)
                                Text(section.title).font(.system(.headline, design: .rounded, weight: .bold))
                            }
                            Text(section.body)
                                .font(.system(.body, design: .default)).foregroundStyle(RailColor.secondary(scheme)).lineSpacing(5).textSelection(.enabled)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RailColor.surface(scheme))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    if !document.links.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(document.links.enumerated()), id: \.element.id) { index, link in
                                if let url = URL(string: link.url) {
                                    Link(destination: url) {
                                        HStack { Text(link.title).font(.system(.body, design: .rounded, weight: .bold)); Spacer(); RailGlyph(systemName: "arrow.up.right").foregroundStyle(RailColor.coral) }
                                            .foregroundStyle(RailColor.ink(scheme)).padding(.horizontal, 15).frame(minHeight: 60)
                                    }
                                }
                                if index < document.links.count - 1 { RailHairline().padding(.leading, 15) }
                            }
                        }
                        .background(RailColor.surface(scheme)).clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(18).padding(.bottom, 28).frame(maxWidth: 780).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var documentIndex: some View {
        HStack {
            RailGlyph(systemName: document.icon).font(.system(size: 24, weight: .bold)).foregroundStyle(.white).frame(width: 54, height: 54).background(RailColor.coral).clipShape(RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) { Text("\(document.sections.count) 个章节").font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(.white); Text("内容可选择与复制").font(.caption).foregroundStyle(.white.opacity(0.54)) }
            Spacer(); RailStatus(text: "LOCAL")
        }
        .padding(16).background(Color(red: 0.055, green: 0.06, blue: 0.075)).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
