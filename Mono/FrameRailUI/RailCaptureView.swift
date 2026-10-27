import ReplayKit
import SwiftUI
import UIKit

struct RailCaptureView: View {
    let launchToken: Int

    @AppStorage(ScreenRecordingPreferenceKey.resolution, store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var resolution = ScreenResolutionPreset.native.rawValue
    @AppStorage(ScreenRecordingPreferenceKey.frameRate, store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var frameRate = 60
    @State private var expanded = false
    @State private var scheduledLaunchToken = 0
    @StateObject private var captions = LiveCaptionService()
    @StateObject private var scheduler = CaptureScheduler()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { timeline in
            let snapshot = ScreenRecordingSnapshot.read(at: timeline.date)
            ScrollView {
                VStack(spacing: 26) {
                    RailPageHeader(title: snapshot.isActive ? "正在录制" : "准备开拍")
                    .railEntrance()

                    transportStage(snapshot: snapshot, date: timeline.date)
                        .railEntrance(delay: 0.05)

                    audioEntry
                        .railEntrance(delay: 0.10)

                    captureOptions
                        .railEntrance(delay: 0.15)
                }
                .railPagePadding()
                .padding(.bottom, 116)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .onChange(of: scheduler.fireToken) { _, _ in scheduledLaunchToken &+= 1 }
    }

    private func transportStage(snapshot: ScreenRecordingSnapshot, date: Date) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("屏幕轨")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(currentResolution.title)  /  \(frameRate) FPS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.64))
            }
            .padding(.horizontal, 18)
            .frame(height: 64)

            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 15) {
                    timecode(snapshot.elapsed(at: date))
                    RailTimelineTicks(count: 22, tint: RailColor.coral)
                    animatedTrack(active: snapshot.isActive, phase: date.timeIntervalSinceReferenceDate)
                        .frame(height: 58)
                    if captions.isListening {
                        RailLabel(
                            captions.latestLine.isEmpty ? "正在聆听…" : captions.latestLine,
                            systemImage: "captions.bubble.fill"
                        )
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(2)
                        .transition(.opacity)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle().fill(.white.opacity(0.12)).frame(width: 1).padding(.vertical, 18)

                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.16), lineWidth: 10)
                        .frame(width: 112, height: 112)
                    Circle()
                        .trim(from: 0, to: snapshot.isActive ? 0.78 : 0.18)
                        .stroke(RailColor.coral, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 112, height: 112)
                    RoundedRectangle(cornerRadius: snapshot.isActive ? 12 : 34, style: .continuous)
                        .fill(RailColor.coral)
                        .frame(width: snapshot.isActive ? 44 : 68, height: snapshot.isActive ? 44 : 68)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: snapshot.isActive)
                    RailBroadcastPicker(
                        extensionBundleIdentifier: "com.linchengbo.mono.screenaudio.broadcast",
                        launchToken: launchToken &+ scheduledLaunchToken
                    )
                    .opacity(0.01)
                }
                .frame(width: 148)
                .accessibilityLabel(snapshot.isActive ? "停止屏幕录制" : "开始屏幕录制")
            }
            .frame(minHeight: 250)
        }
        .background(Color(red: 0.055, green: 0.06, blue: 0.075))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(RailColor.coral)
                .frame(height: 3)
        }
    }

    private func timecode(_ seconds: TimeInterval) -> some View {
        let value = max(0, Int(seconds.rounded(.down)))
        return Text(String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60))
            .font(.system(size: 40, weight: .semibold, design: .monospaced))
            .tracking(-1.5)
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .accessibilityLabel("已录制 \(value) 秒")
    }

    private func animatedTrack(active: Bool, phase: TimeInterval) -> some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<28, id: \.self) { index in
                let level = active ? abs(sin(phase * 2.5 + Double(index) * 0.61)) : 0.14 + Double((index * 7) % 5) / 30
                Capsule()
                    .fill(index.isMultiple(of: 8) ? RailColor.coral : Color.white.opacity(0.30))
                    .frame(maxWidth: .infinity)
                    .frame(height: 5 + CGFloat(level) * 43)
            }
        }
    }

    private var audioEntry: some View {
        NavigationLink { RailAudioRecorderView() } label: {
            HStack(spacing: 13) {
                RailGlyph(systemName: "waveform")
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(RailColor.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("录音")
                        .font(.system(.body, design: .rounded, weight: .bold))
                    Text("采集人声或边听边录")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(RailColor.secondary(scheme))
                }
                Spacer()
                RailGlyph(systemName: "arrow.right")
                    .foregroundStyle(RailColor.secondary(scheme))
            }
            .foregroundStyle(RailColor.ink(scheme))
            .padding(.horizontal, 14)
            .frame(minHeight: 66)
            .background(RailColor.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(RailPressStyle())
    }

    private var captureOptions: some View {
        VStack(spacing: 12) {
            RailSectionTitle(title: "选项", detail: scheduler.isArmed ? scheduler.countdownText : nil)
            RailSurface {
                VStack(spacing: 0) {
                    Button {
                        Task {
                            if captions.isListening { captions.stop() }
                            else { await captions.start() }
                        }
                    } label: {
                        optionRow(
                            "实时字幕",
                            detail: captions.isListening ? "识别中，停止后保存 SRT" : "设备端识别麦克风内容",
                            symbol: "captions.bubble",
                            value: captions.isListening ? "ON" : "OFF",
                            active: captions.isListening
                        )
                    }
                    .buttonStyle(.plain)
                    RailHairline().padding(.leading, 62)

                    VStack(spacing: 12) {
                        Button {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { expanded.toggle() }
                        } label: {
                            optionRow(
                                "画面参数",
                                detail: "调整分辨率与帧率",
                                symbol: "dial.medium",
                                value: expanded ? "收起" : "调整",
                                active: false
                            )
                        }
                        .buttonStyle(.plain)

                        if expanded {
                            VStack(spacing: 14) {
                                RailSegmented(
                                    values: [
                                        (ScreenResolutionPreset.p720.rawValue, "720p"),
                                        (ScreenResolutionPreset.p1080.rawValue, "1080p"),
                                        (ScreenResolutionPreset.p2K.rawValue, "2K"),
                                        (ScreenResolutionPreset.native.rawValue, "设备")
                                    ],
                                    selection: $resolution
                                )
                                HStack {
                                    Text("15").font(.caption.monospaced())
                                    Slider(
                                        value: Binding(get: { Double(frameRate) }, set: { frameRate = Int($0.rounded()) }),
                                        in: 15...60,
                                        step: 1
                                    )
                                    .tint(RailColor.coral)
                                    Text("60").font(.caption.monospaced())
                                }
                                .foregroundStyle(RailColor.secondary(scheme))
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    RailHairline().padding(.leading, 62)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            RailLabel("定时开始", systemImage: "timer")
                                .font(.system(.body, design: .rounded, weight: .bold))
                            Spacer()
                            if scheduler.isArmed {
                                Button("取消") { scheduler.cancel() }
                                    .font(.caption.bold())
                                    .foregroundStyle(RailColor.coral)
                            }
                        }
                        if !scheduler.isArmed {
                            HStack(spacing: 8) {
                                scheduleButton("5 秒", 5)
                                scheduleButton("30 秒", 30)
                                scheduleButton("1 分钟", 60)
                            }
                        }
                    }
                    .padding(16)
                    .foregroundStyle(RailColor.ink(scheme))
                }
            }
        }
    }

    private func optionRow(
        _ title: String,
        detail: String,
        symbol: String,
        value: String,
        active: Bool
    ) -> some View {
        HStack(spacing: 14) {
            RailGlyph(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(active ? .white : RailColor.coral)
                .frame(width: 38, height: 38)
                .background(active ? RailColor.coral : RailColor.coral.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(.body, design: .rounded, weight: .bold))
                Text(detail).font(.system(.caption, design: .rounded)).foregroundStyle(RailColor.secondary(scheme))
            }
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(active ? RailColor.coral : RailColor.secondary(scheme))
        }
        .foregroundStyle(RailColor.ink(scheme))
        .padding(.horizontal, 14)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
    }

    private func scheduleButton(_ title: String, _ seconds: TimeInterval) -> some View {
        Button { Task { await scheduler.arm(after: seconds) } } label: {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(RailColor.ink(scheme))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(RailColor.raised(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(RailPressStyle())
    }

    private var currentResolution: ScreenResolutionPreset {
        ScreenResolutionPreset(rawValue: resolution) ?? .native
    }
}

private struct RailBroadcastPicker: UIViewRepresentable {
    let extensionBundleIdentifier: String
    let launchToken: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RailFullSizeBroadcastPicker()
        picker.preferredExtension = extensionBundleIdentifier
        picker.showsMicrophoneButton = true
        return picker
    }

    func updateUIView(_ view: RPSystemBroadcastPickerView, context: Context) {
        view.preferredExtension = extensionBundleIdentifier
        guard launchToken > 0, context.coordinator.lastToken != launchToken else { return }
        context.coordinator.lastToken = launchToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            (view as? RailFullSizeBroadcastPicker)?.trigger()
        }
    }

    final class Coordinator { var lastToken = 0 }
}

private final class RailFullSizeBroadcastPicker: RPSystemBroadcastPickerView {
    override func layoutSubviews() {
        super.layoutSubviews()
        subviews.compactMap { $0 as? UIButton }.forEach {
            $0.frame = bounds
            $0.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
    }

    func trigger() { subviews.compactMap { $0 as? UIButton }.first?.sendActions(for: .touchUpInside) }
}
