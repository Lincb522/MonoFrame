import ReplayKit
import SwiftUI
import UIKit

struct SignalCaptureView: View {
    let launchToken: Int
    let openAudio: () -> Void
    let openLibrary: () -> Void

    @AppStorage(ScreenRecordingPreferenceKey.resolution, store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var resolution = ScreenResolutionPreset.native.rawValue
    @AppStorage(ScreenRecordingPreferenceKey.frameRate, store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var frameRate = 60
    @State private var showsControls = false
    @State private var scheduledLaunchToken = 0
    @StateObject private var captions = LiveCaptionService()
    @StateObject private var scheduler = CaptureScheduler()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { timeline in
            let snapshot = ScreenRecordingSnapshot.read(at: timeline.date)
            ScrollView {
                VStack(spacing: SignalSpace.lg) {
                    SignalPageHeader(
                        title: snapshot.isActive ? "正在记录" : "开拍吧",
                        detail: snapshot.isActive ? "录制由系统广播扩展持续进行" : "打开控制中心也可以立即开始",
                        action: AnyView(
                            SignalStatus(text: snapshot.isActive ? "录制中" : "就绪", kind: snapshot.isActive ? .live : .ready)
                        )
                    )

                    stage(snapshot: snapshot, date: timeline.date)
                        .youthStageEntrance()
                    enhancementRail
                        .youthDelayedReveal(delay: 0.40)
                    settingsRail
                        .youthDelayedReveal(delay: 0.46)
                    quickActions
                        .youthDelayedReveal(delay: 0.52)
                }
                .signalPagePadding()
                .padding(.bottom, 124)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .onChange(of: scheduler.fireToken) { _, _ in
            scheduledLaunchToken &+= 1
        }
    }

    private func stage(snapshot: ScreenRecordingSnapshot, date: Date) -> some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(snapshot.isActive ? SignalColor.coral : Color.white.opacity(0.35)).frame(width: 8, height: 8)
                    Text(snapshot.isActive ? "REC" : "STANDBY")
                }
                Spacer()
                Text("\(currentResolution.title)  ·  \(frameRate) FPS")
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.70))
            .padding(.leading, SignalSpace.md)
            .padding(.trailing, 82)
            .frame(height: 44)

            SignalRule().opacity(0.45)

            VStack(spacing: SignalSpace.lg) {
                SignalTimecode(seconds: snapshot.elapsed(at: date), size: 50)
                    .foregroundStyle(.white)

                SignalWaveform(
                    active: snapshot.isActive,
                    phase: date.timeIntervalSinceReferenceDate,
                    bars: 32,
                    tint: SignalColor.acid
                )
                .frame(maxWidth: .infinity)

                recordControl(snapshot, phase: date.timeIntervalSinceReferenceDate)

                Text(snapshot.isActive ? "轻触后在系统面板停止" : "轻触后在系统面板开始广播")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.54))
            }
            .padding(.horizontal, SignalSpace.lg)
            .padding(.vertical, SignalSpace.xl)
        }
        .background {
            ZStack(alignment: .topTrailing) {
                SignalColor.stage
                Circle()
                    .fill(SignalColor.acid.opacity(0.15))
                    .frame(width: 180, height: 180)
                    .blur(radius: 52)
                    .offset(x: 38, y: -60)
            }
        }
        .clipShape(YouthNotchedPanelShape(cornerRadius: 34, notchWidth: 92, notchDepth: 62))
        .overlay(alignment: .topTrailing) {
            YouthStatusBubble(
                value: snapshot.isActive ? "LIVE" : "\(frameRate)",
                symbol: snapshot.isActive ? "waveform" : "bolt.fill"
            )
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
        .overlay(alignment: .bottom) {
            if captions.isListening {
                HStack(spacing: 9) {
                    Image(systemName: "captions.bubble.fill")
                        .foregroundStyle(SignalColor.coral)
                    Text(captions.latestLine.isEmpty ? "正在聆听…" : captions.latestLine)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 13)
                .frame(minHeight: 48)
                .background(SignalColor.stageRaised.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func recordControl(_ snapshot: ScreenRecordingSnapshot, phase: TimeInterval) -> some View {
        ZStack {
            SignalCaptureOrb(active: snapshot.isActive, phase: phase)

            SignalBroadcastPicker(
                extensionBundleIdentifier: "com.linchengbo.mono.screenaudio.broadcast",
                launchToken: launchToken &+ scheduledLaunchToken
            )
            .opacity(0.01)
        }
        .frame(width: 148, height: 148)
        .contentShape(Circle())
        .accessibilityLabel(snapshot.isActive ? "停止屏幕录制" : "开始屏幕录制")
        .accessibilityHint("打开系统广播面板")
    }

    private var enhancementRail: some View {
        SignalPanel {
            VStack(spacing: 0) {
                Button {
                    Task {
                        if captions.isListening { captions.stop() }
                        else { await captions.start() }
                    }
                } label: {
                    HStack(spacing: SignalSpace.sm) {
                        Image(systemName: captions.isListening ? "captions.bubble.fill" : "captions.bubble")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(captions.isListening ? SignalColor.coral : SignalColor.ink(scheme))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("实时悬浮字幕")
                                .font(.system(.body, design: .rounded, weight: .bold))
                            Text(captionStatusText)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(SignalColor.secondary(scheme))
                        }
                        Spacer()
                        Text(captions.isListening ? "ON" : "OFF")
                            .font(.system(.caption2, design: .monospaced, weight: .black))
                            .foregroundStyle(captions.isListening ? SignalColor.coral : SignalColor.secondary(scheme))
                    }
                    .foregroundStyle(SignalColor.ink(scheme))
                    .padding(.horizontal, SignalSpace.md)
                    .frame(minHeight: 64)
                }
                .buttonStyle(.plain)

                SignalRule()

                VStack(alignment: .leading, spacing: SignalSpace.sm) {
                    HStack {
                        Label("定时录制", systemImage: "timer")
                            .font(.system(.body, design: .rounded, weight: .bold))
                        Spacer()
                        if scheduler.isArmed {
                            Text(scheduler.countdownText)
                                .font(.system(.body, design: .monospaced, weight: .bold))
                                .foregroundStyle(SignalColor.coral)
                                .contentTransition(.numericText())
                        }
                    }

                    if scheduler.isArmed {
                        Button("取消倒计时") { scheduler.cancel() }
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(SignalColor.coral)
                    } else {
                        HStack(spacing: 8) {
                            scheduleButton("测试 5s", seconds: 5)
                            scheduleButton("30s", seconds: 30)
                            scheduleButton("1 min", seconds: 60)
                            scheduleButton("5 min", seconds: 300)
                        }
                    }
                }
                .padding(SignalSpace.md)
            }
        }
    }

    private func scheduleButton(_ title: String, seconds: TimeInterval) -> some View {
        Button { Task { await scheduler.arm(after: seconds) } } label: {
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(SignalColor.ink(scheme))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(SignalColor.raised(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(SignalPressStyle())
    }

    private var captionStatusText: String {
        switch captions.state {
        case .idle:
            if let url = captions.savedTranscriptURL { return "已保存 \(url.lastPathComponent)" }
            return "识别麦克风并保存 SRT"
        case .requestingPermission: return "正在请求语音识别权限"
        case .listening: return "轻触停止并保存字幕"
        case let .failed(message): return message
        }
    }

    private var settingsRail: some View {
        SignalPanel {
            VStack(spacing: 0) {
                Button {
                    if reduceMotion { showsControls.toggle() }
                    else { withAnimation(.easeOut(duration: 0.18)) { showsControls.toggle() } }
                } label: {
                    HStack(spacing: SignalSpace.sm) {
                        Image(systemName: "dial.low")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("录制参数").font(.system(.body, design: .rounded, weight: .bold))
                            Text("\(currentResolution.title) · \(frameRate) FPS")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(SignalColor.secondary(scheme))
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.bold())
                            .rotationEffect(.degrees(showsControls ? 180 : 0))
                    }
                    .foregroundStyle(SignalColor.ink(scheme))
                    .padding(.horizontal, SignalSpace.md)
                    .frame(minHeight: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .light), trigger: showsControls)

                if showsControls {
                    SignalRule()
                    VStack(alignment: .leading, spacing: SignalSpace.md) {
                        Text("画质").font(.system(.caption, design: .rounded, weight: .bold))
                        SignalSegmentedControl(
                            values: [
                                (ScreenResolutionPreset.p720.rawValue, "720p"),
                                (ScreenResolutionPreset.p1080.rawValue, "1080p"),
                                (ScreenResolutionPreset.p2K.rawValue, "2K"),
                                (ScreenResolutionPreset.native.rawValue, "设备")
                            ],
                            selection: $resolution
                        )
                        HStack {
                            Text("帧率").font(.system(.caption, design: .rounded, weight: .bold))
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
                        .accessibilityValue("每秒 \(frameRate) 帧")
                    }
                    .padding(SignalSpace.md)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 0) {
            NavigationLink { AudioRecorderView() } label: {
                quickAction("录音", symbol: "waveform")
            }
            .buttonStyle(SignalPressStyle())

            Rectangle().fill(SignalColor.rule(scheme)).frame(width: 1).padding(.vertical, 14)

            Button(action: openAudio) { quickAction("创作", symbol: "scissors") }
                .buttonStyle(SignalPressStyle())

            Rectangle().fill(SignalColor.rule(scheme)).frame(width: 1).padding(.vertical, 14)

            Button(action: openLibrary) { quickAction("作品", symbol: "rectangle.stack") }
                .buttonStyle(SignalPressStyle())
        }
        .background(SignalColor.surface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(SignalColor.rule(scheme), lineWidth: 1) }
    }

    private func quickAction(_ title: String, symbol: String) -> some View {
        VStack(spacing: SignalSpace.xs) {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold))
            Text(title).font(.system(.caption, design: .rounded, weight: .bold))
        }
        .foregroundStyle(SignalColor.ink(scheme))
        .frame(maxWidth: .infinity, minHeight: 72)
    }

    private var currentResolution: ScreenResolutionPreset {
        ScreenResolutionPreset(rawValue: resolution) ?? .native
    }
}

private struct SignalCaptureOrb: View {
    let active: Bool
    let phase: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pulse = reduceMotion ? 1 : 1 + CGFloat(sin(phase * (active ? 3.2 : 1.7))) * (active ? 0.05 : 0.025)
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                .frame(width: 146, height: 146)
                .scaleEffect(pulse)

            Circle()
                .trim(from: 0.04, to: active ? 0.90 : 0.74)
                .stroke(
                    active ? SignalColor.coral : Color.white.opacity(0.72),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 124, height: 124)
                .rotationEffect(.degrees(reduceMotion ? -30 : phase * (active ? 42 : 10)))

            Circle()
                .fill(SignalColor.coral.opacity(0.16))
                .frame(width: 92, height: 92)
                .scaleEffect(pulse)

            Group {
                if active {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SignalColor.coral)
                        .frame(width: 42, height: 42)
                } else {
                    Circle().fill(SignalColor.coral).frame(width: 76, height: 76)
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.84), value: active)
        }
        .accessibilityHidden(true)
    }
}

private struct SignalBroadcastPicker: UIViewRepresentable {
    let extensionBundleIdentifier: String
    let launchToken: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = SignalFullSizeBroadcastPicker()
        picker.preferredExtension = extensionBundleIdentifier
        picker.showsMicrophoneButton = true
        return picker
    }

    func updateUIView(_ view: RPSystemBroadcastPickerView, context: Context) {
        view.preferredExtension = extensionBundleIdentifier
        guard launchToken > 0, context.coordinator.lastLaunchToken != launchToken else { return }
        context.coordinator.lastLaunchToken = launchToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            (view as? SignalFullSizeBroadcastPicker)?.trigger()
        }
    }

    final class Coordinator { var lastLaunchToken = 0 }
}

private final class SignalFullSizeBroadcastPicker: RPSystemBroadcastPickerView {
    override func layoutSubviews() {
        super.layoutSubviews()
        buttons.forEach { $0.frame = bounds; $0.autoresizingMask = [.flexibleWidth, .flexibleHeight] }
    }

    func trigger() { buttons.first?.sendActions(for: .touchUpInside) }
    private var buttons: [UIButton] { subviews.compactMap { $0 as? UIButton } }
}
