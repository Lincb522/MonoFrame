import ReplayKit
import SwiftUI
import UIKit

struct WildCaptureView: View {
    let launchToken: Int
    @AppStorage(ScreenRecordingPreferenceKey.resolution, store: UserDefaults(suiteName: SharedStorage.appGroup)) private var resolution = ScreenResolutionPreset.native.rawValue
    @AppStorage(ScreenRecordingPreferenceKey.frameRate, store: UserDefaults(suiteName: SharedStorage.appGroup)) private var frameRate = 60
    @State private var showsSetup = false
    @State private var scheduledLaunchToken = 0
    @StateObject private var captions = LiveCaptionService()
    @StateObject private var scheduler = CaptureScheduler()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                WildHeader("开拍", kicker: "CAPTURE 01") {
                    WildStamp(text: "READY", tint: WildColor.acid)
                }.wildEntrance()

                TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 20)) { timeline in
                    let snapshot = ScreenRecordingSnapshot.read(at: timeline.date)
                    hero(snapshot, timeline.date)
                }
                .wildEntrance(0.04)

                quickActions.wildEntrance(0.08)
                setupPanel.wildEntrance(0.12)
            }
            .wildPage().padding(.bottom, 120).frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .onChange(of: scheduler.fireToken) { _, _ in scheduledLaunchToken &+= 1 }
    }

    private func hero(_ snapshot: ScreenRecordingSnapshot, _ date: Date) -> some View {
        ZStack(alignment: .bottomLeading) {
            WildColor.stage(scheme)
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("SCREEN")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.5).foregroundStyle(WildColor.stageSecondary(scheme))
                    Spacer()
                    Text("\(currentResolution.title) · \(frameRate) FPS")
                        .font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(WildColor.stageSecondary(scheme))
                }
                Text(timecode(snapshot.elapsed(at: date)))
                    .font(.system(size: 38, weight: .bold, design: .monospaced)).tracking(-1.5)
                    .foregroundStyle(WildColor.stageInk(scheme)).contentTransition(.numericText())
                signal(active: snapshot.isActive, phase: date.timeIntervalSinceReferenceDate).frame(height: 66)
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(snapshot.isActive ? "触碰方块停止" : "触碰方块开始")
                            .font(.system(.caption, design: .rounded, weight: .black)).foregroundStyle(WildColor.stageInk(scheme))
                        if captions.isListening {
                            Text(captions.latestLine.isEmpty ? "字幕正在聆听" : captions.latestLine)
                                .font(.caption).foregroundStyle(WildColor.stageSecondary(scheme)).lineLimit(1)
                        }
                    }
                    Spacer()
                    ZStack {
                        WildTicketShape().stroke(WildColor.stageRule(scheme), lineWidth: 2).frame(width: 86, height: 86)
                        WildTicketShape().fill(WildColor.orange)
                            .frame(width: snapshot.isActive ? 44 : 60, height: snapshot.isActive ? 44 : 60)
                            .rotationEffect(.degrees(snapshot.isActive ? 0 : -4))
                            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.70), value: snapshot.isActive)
                        WildBroadcastPicker(extensionBundleIdentifier: "com.linchengbo.mono.screenaudio.broadcast", launchToken: launchToken &+ scheduledLaunchToken).opacity(0.01)
                    }.frame(width: 94, height: 94)
                }
            }.padding(18)
        }
        .frame(minHeight: 300).clipShape(WildPanelShape(cut: 22))
        .overlay { WildPanelShape(cut: 22).stroke(WildColor.rule(scheme), lineWidth: 1) }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            NavigationLink { WildAudioRecorderView() } label: {
                quickTile("录人声", "waveform", WildColor.orange, WildColor.onOrange)
            }.buttonStyle(WildPressStyle())
            Button {
                Task { captions.isListening ? captions.stop() : await captions.start() }
            } label: {
                quickTile(captions.isListening ? "字幕开" : "实时字幕", "captions.bubble", WildColor.blue, WildColor.onBlue)
            }.buttonStyle(WildPressStyle())
        }
    }

    private func quickTile(_ title: String, _ symbol: String, _ tint: Color, _ foreground: Color) -> some View {
        HStack(spacing: 10) {
            RailGlyph(systemName: symbol).font(.system(size: 17, weight: .black))
                .foregroundStyle(foreground).frame(width: 38, height: 38).background(tint).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(title).font(.system(.subheadline, design: .rounded, weight: .black))
            Spacer()
            RailGlyph(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(WildColor.secondary(scheme))
        }
        .foregroundStyle(WildColor.ink(scheme))
        .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 58)
        .background(WildColor.paper(scheme)).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(WildColor.rule(scheme), lineWidth: 1) }
    }

    private var setupPanel: some View {
        VStack(spacing: 10) {
            WildSectionLabel(index: "02", title: "拍摄参数", detail: scheduler.isArmed ? scheduler.countdownText : nil)
            WildSurface {
                VStack(spacing: 0) {
                    Button { withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.80)) { showsSetup.toggle() } } label: {
                        row("画面规格", "\(currentResolution.title) / \(frameRate) FPS", "dial.medium", showsSetup ? "收起" : "改")
                    }.buttonStyle(.plain)
                    if showsSetup {
                        VStack(spacing: 14) {
                            WildSegmented(values: [(ScreenResolutionPreset.p720.rawValue,"720"),(ScreenResolutionPreset.p1080.rawValue,"1080"),(ScreenResolutionPreset.p2K.rawValue,"2K"),(ScreenResolutionPreset.native.rawValue,"设备")], selection: $resolution)
                            HStack(spacing: 10) {
                                Text("15").font(.caption.monospaced().bold())
                                Slider(value: Binding(get: { Double(frameRate) }, set: { frameRate = Int($0.rounded()) }), in: 15...60, step: 1).tint(WildColor.blue)
                                Text("60").font(.caption.monospaced().bold())
                            }.foregroundStyle(WildColor.secondary(scheme))
                        }.padding(.horizontal, 16).padding(.bottom, 16).transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    WildRule().padding(.leading, 58)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            RailGlyph(systemName: "timer").foregroundStyle(WildColor.blue).frame(width: 28)
                            Text("定时开拍").font(.system(.body, design: .rounded, weight: .black))
                            Spacer()
                            if scheduler.isArmed { Button("取消") { scheduler.cancel() }.font(.caption.bold()).foregroundStyle(WildColor.signalInk(scheme)) }
                        }
                        if !scheduler.isArmed {
                            HStack(spacing: 8) { schedule("5秒",5); schedule("30秒",30); schedule("1分钟",60) }
                        }
                    }.padding(16).foregroundStyle(WildColor.ink(scheme))
                }
            }
        }
    }

    private func row(_ title: String, _ detail: String, _ symbol: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            RailGlyph(systemName: symbol).font(.system(size: 17, weight: .black)).foregroundStyle(WildColor.onBlue)
                .frame(width: 40, height: 40).background(WildColor.blue).clipShape(WildTicketShape())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.body, design: .rounded, weight: .black))
                Text(detail).font(.caption).foregroundStyle(WildColor.secondary(scheme))
            }
            Spacer(); WildStamp(text: value, tint: WildColor.acid)
        }.foregroundStyle(WildColor.ink(scheme)).padding(14).contentShape(Rectangle())
    }

    private func schedule(_ title: String, _ seconds: TimeInterval) -> some View {
        Button { Task { await scheduler.arm(after: seconds) } } label: {
            Text(title).font(.system(.caption, design: .rounded, weight: .black)).foregroundStyle(WildColor.ink(scheme))
                .frame(maxWidth: .infinity, minHeight: 40).background(WildColor.raised(scheme)).clipShape(WildTicketShape())
        }.buttonStyle(WildPressStyle())
    }

    private func signal(active: Bool, phase: TimeInterval) -> some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<32, id: \.self) { i in
                let level = active ? abs(sin(phase * 2.6 + Double(i) * 0.58)) : 0.12 + Double((i * 7) % 5) / 28
                Rectangle().fill(i.isMultiple(of: 7) ? WildColor.orange : WildColor.stageSecondary(scheme).opacity(0.46))
                    .frame(maxWidth: .infinity).frame(height: 5 + CGFloat(level) * 54)
            }
        }
    }

    private func timecode(_ seconds: TimeInterval) -> String {
        let v = max(0, Int(seconds.rounded(.down))); return String(format: "%02d:%02d:%02d", v / 3600, v / 60 % 60, v % 60)
    }
    private var currentResolution: ScreenResolutionPreset { ScreenResolutionPreset(rawValue: resolution) ?? .native }
}

private struct WildBroadcastPicker: UIViewRepresentable {
    let extensionBundleIdentifier: String
    let launchToken: Int
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = WildFullSizeBroadcastPicker(); picker.preferredExtension = extensionBundleIdentifier; picker.showsMicrophoneButton = true; return picker
    }
    func updateUIView(_ view: RPSystemBroadcastPickerView, context: Context) {
        view.preferredExtension = extensionBundleIdentifier
        guard launchToken > 0, context.coordinator.lastToken != launchToken else { return }
        context.coordinator.lastToken = launchToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { (view as? WildFullSizeBroadcastPicker)?.trigger() }
    }
    final class Coordinator { var lastToken = 0 }
}
private final class WildFullSizeBroadcastPicker: RPSystemBroadcastPickerView {
    override func layoutSubviews() { super.layoutSubviews(); subviews.compactMap { $0 as? UIButton }.forEach { $0.frame = bounds; $0.autoresizingMask = [.flexibleWidth, .flexibleHeight] } }
    func trigger() { subviews.compactMap { $0 as? UIButton }.first?.sendActions(for: .touchUpInside) }
}
