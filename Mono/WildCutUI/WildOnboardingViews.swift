import SwiftUI
import UIKit

struct WildOnboardingFlow: View {
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
                WildWelcomeView {
                    welcomeCompleted()
                    if needsPermissions { withAnimation(.easeOut(duration: 0.22)) { stage = .permissions } }
                    else { completion() }
                }
            case .permissions:
                WildPermissionView(completion: completion)
            }
        }
        .transition(.opacity)
    }
}

private struct WildWelcomeView: View {
    let completion: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WildBackground()
            VStack(spacing: 0) {
                HStack {
                    Text("MONOFRAME").font(.system(size: 12, weight: .black, design: .monospaced))
                    Spacer()
                    WildStamp(text: "LOCAL FIRST")
                }
                Spacer(minLength: 24)
                welcomeTrack
                VStack(alignment: .leading, spacing: 8) {
                    Text("开拍。拆解。\n重新组装。")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .tracking(-1.1)
                        .foregroundStyle(WildColor.ink(scheme))
                    Text("一台设备，就是你的录制间、剪辑台和转码站。")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(WildColor.secondary(scheme))
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
                .buttonStyle(WildActionStyle())
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
                    Text("MASTER TIMELINE").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(WildColor.stageSecondary(scheme))
                    Spacer(); Text("00:12:48").font(.caption.monospaced().bold()).foregroundStyle(WildColor.stageSecondary(scheme))
                }
                .padding(.horizontal, 17).frame(height: 54)
                ZStack {
                    VStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 9).fill(WildColor.blue).frame(height: 50).padding(.trailing, 42)
                        RoundedRectangle(cornerRadius: 9).fill(WildColor.orange.opacity(0.82)).frame(height: 38).padding(.leading, 72)
                        HStack(alignment: .center, spacing: 3) {
                            ForEach(0..<30, id: \.self) { index in
                                let level = abs(sin(Double(index) * 0.5 + phase * 9))
                                Capsule().fill(WildColor.stageSecondary(scheme).opacity(0.48)).frame(maxWidth: .infinity).frame(height: 4 + level * 34)
                            }
                        }.frame(height: 42)
                    }
                    Rectangle().fill(WildColor.stageInk(scheme)).frame(width: 2).overlay(alignment: .top) { Circle().fill(WildColor.orange).frame(width: 10, height: 10) }
                        .offset(x: -140 + phase * 280)
                }
                .padding(17)
                WildTimelineTicks(count: 24, tint: WildColor.orange).padding(.horizontal, 17).padding(.bottom, 16)
            }
            .background(WildColor.stage(scheme))
            .overlay { WildPanelShape(cut: 18).stroke(WildColor.rule(scheme), lineWidth: 1) }
            .clipShape(WildPanelShape(cut: 18))
        }
        .frame(minHeight: 270)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("MonoFrame 本地媒体工作台")
    }
}

private struct WildPermissionView: View {
    let completion: () -> Void
    @StateObject private var permissions = PermissionCenter()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            WildBackground()
            VStack(spacing: 22) {
                WildHeader("权限接线", kicker: "SETUP 02") {
                    WildStamp(text: "2 ITEMS", tint: WildColor.blue, foreground: .white)
                }

                VStack(spacing: 0) {
                    permissionLane("照片", detail: "保存视频与 Live Photo", symbol: "photo.on.rectangle", state: permissions.photo, tint: WildColor.blue, foreground: WildColor.onBlue)
                    WildRule().padding(.leading, 72)
                    permissionLane("麦克风", detail: "录制你的声音", symbol: "mic", state: permissions.microphone, tint: WildColor.orange, foreground: WildColor.onOrange)
                }
                .background(WildColor.paper(scheme))
                .clipShape(WildPanelShape(cut: 18))

                VStack(alignment: .leading, spacing: 12) {
                    Text("PRIVACY ROUTE").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(WildColor.stageSecondary(scheme))
                    HStack(spacing: 8) {
                        routeNode("输入", "iphone")
                        routeLine
                        routeNode("本地处理", "cpu")
                        routeLine
                        routeNode("你的文件", "folder")
                    }
                }
                .padding(18)
                .background(WildColor.stage(scheme))
                .overlay { WildPanelShape(cut: 18).stroke(WildColor.rule(scheme), lineWidth: 1) }
                .clipShape(WildPanelShape(cut: 18))

                Spacer()

                Button { primaryAction() } label: {
                    Group { if permissions.isRequesting { ProgressView().tint(.white) } else { Text(primaryTitle) } }
                        .font(.system(.headline, design: .rounded, weight: .bold)).frame(maxWidth: .infinity, minHeight: 58)
                }
                .buttonStyle(WildActionStyle())
                .disabled(permissions.isRequesting)

                Button(permissions.hasDeniedAccess ? "完成" : "稍后") { completion() }
                    .font(.system(.subheadline, design: .rounded, weight: .bold)).foregroundStyle(WildColor.secondary(scheme)).frame(minHeight: 44)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 18)
            .frame(maxWidth: 760)
        }
        .interactiveDismissDisabled()
        .onChange(of: scenePhase) { _, phase in if phase == .active { permissions.refresh() } }
    }

    private func permissionLane(_ title: String, detail: String, symbol: String, state: PermissionCenter.AccessState, tint: Color, foreground: Color) -> some View {
        HStack(spacing: 14) {
            RailGlyph(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(foreground).frame(width: 44, height: 44).background(tint).clipShape(RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(.headline, design: .rounded, weight: .bold)); Text(detail).font(.caption).foregroundStyle(WildColor.secondary(scheme)) }
            Spacer()
            RailLabel(state.title, systemImage: state.symbol).labelStyle(.iconOnly).font(.system(size: 20, weight: .bold)).foregroundStyle(state == .allowed ? WildColor.successInk(scheme) : WildColor.secondary(scheme))
        }
        .foregroundStyle(WildColor.ink(scheme)).padding(.horizontal, 14).frame(minHeight: 76)
    }

    private func routeNode(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 7) { RailGlyph(systemName: symbol).font(.system(size: 18, weight: .bold)); Text(title).font(.system(size: 10, weight: .bold, design: .rounded)) }
            .foregroundStyle(WildColor.stageInk(scheme)).frame(width: 72)
    }

    private var routeLine: some View { Rectangle().fill(WildColor.orange).frame(maxWidth: .infinity, minHeight: 2, maxHeight: 2) }
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

struct WildLegalDocumentView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            WildBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        WildIconButton(symbol: "xmark", tint: WildColor.acid) { dismiss() }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.title).font(.system(.title2, design: .rounded, weight: .heavy))
                            Text("MONOFRAME DOCUMENT").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(WildColor.secondary(scheme))
                        }
                    }
                    documentIndex
                    ForEach(Array(document.sections.enumerated()), id: \.offset) { index, section in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(String(format: "%02d", index + 1)).font(.caption.monospaced().bold()).foregroundStyle(WildColor.signalInk(scheme))
                                Text(section.title).font(.system(.headline, design: .rounded, weight: .bold))
                            }
                            Text(section.body)
                                .font(.system(.body, design: .default)).foregroundStyle(WildColor.secondary(scheme)).lineSpacing(5).textSelection(.enabled)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WildColor.paper(scheme))
                        .clipShape(WildPanelShape(cut: 14))
                    }
                    if !document.links.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(document.links.enumerated()), id: \.element.id) { index, link in
                                if let url = URL(string: link.url) {
                                    Link(destination: url) {
                                        HStack { Text(link.title).font(.system(.body, design: .rounded, weight: .bold)); Spacer(); RailGlyph(systemName: "arrow.up.right").foregroundStyle(WildColor.orange) }
                                            .foregroundStyle(WildColor.ink(scheme)).padding(.horizontal, 15).frame(minHeight: 60)
                                    }
                                }
                                if index < document.links.count - 1 { WildRule().padding(.leading, 15) }
                            }
                        }
                        .background(WildColor.paper(scheme)).clipShape(RoundedRectangle(cornerRadius: 14))
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
            RailGlyph(systemName: document.icon).font(.system(size: 24, weight: .bold)).foregroundStyle(WildColor.onOrange).frame(width: 54, height: 54).background(WildColor.orange).clipShape(RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) { Text("\(document.sections.count) 个章节").font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(WildColor.stageInk(scheme)); Text("内容可选择与复制").font(.caption).foregroundStyle(WildColor.stageSecondary(scheme)) }
            Spacer(); WildStamp(text: "LOCAL")
        }
        .padding(16).background(WildColor.stage(scheme)).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(WildColor.rule(scheme), lineWidth: 1) }
    }
}
