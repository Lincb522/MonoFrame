import Foundation
import ReplayKit
import SwiftUI

struct RecordView: View {
    let broadcastLaunchToken: Int
    let openStudio: () -> Void
    let openLibrary: () -> Void

    @AppStorage("screenCodec", store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var screenCodec = "hevc"
    @AppStorage(ScreenRecordingPreferenceKey.resolution, store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var screenResolution = ScreenResolutionPreset.native.rawValue
    @AppStorage(ScreenRecordingPreferenceKey.frameRate, store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var screenFrameRate = 60
    @AppStorage(ScreenRecordingPreferenceKey.orientation, store: UserDefaults(suiteName: SharedStorage.appGroup))
    private var screenOrientation = ScreenOrientationPreset.automatic.rawValue
    @State private var deckExpanded = ProcessInfo.processInfo.environment["MONO_SCREENSHOT_EXPANDED_CONTROLS"] == "1"
    @GestureState private var deckDrag: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let snapshot = ScreenRecordingSnapshot.read(at: timeline.date)
            GeometryReader { proxy in
                let compact = proxy.size.height < 720
                ZStack {
                    recordingAtmosphere(snapshot: snapshot)
                    VStack(spacing: compact ? 10 : 16) {
                    header(snapshot: snapshot)
                        captureStage(snapshot: snapshot, date: timeline.date, compact: compact)
                            .frame(maxHeight: .infinity)
                        commandDeck(snapshot: snapshot)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
            }
            .background(Color.clear)
        }
    }

    private func header(snapshot: ScreenRecordingSnapshot) -> some View {
        MonoPageHeader("MonoFrame") {
            MonoStatusBadge(
                title: snapshot.isActive ? "录制中" : "就绪",
                symbol: snapshot.isActive ? "record.circle.fill" : "circle.dotted",
                active: snapshot.isActive
            )
        }
    }

    private func captureStage(
        snapshot: ScreenRecordingSnapshot,
        date: Date,
        compact: Bool
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.clear)

            Circle()
                .fill(MonoTheme.primary.opacity(0.13))
                .frame(width: 210, height: 210)
                .offset(x: 150, y: -105)
                .blur(radius: 6)

            RoundedRectangle(cornerRadius: 55, style: .continuous)
                .fill(MonoTheme.cyan.opacity(0.10))
                .frame(width: 180, height: 90)
                .rotationEffect(.degrees(-18))
                .offset(x: -135, y: 130)

            VStack(spacing: compact ? 10 : 15) {
                VStack(spacing: 5) {
                    Text(snapshot.isActive ? "正在录制" : "屏幕录制")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(MonoTheme.muted(scheme))

                    Text(snapshot.isActive ? elapsed(snapshot.elapsed(at: date)) : "00:00:00")
                        .font(.system(size: compact ? 36 : 43, weight: .bold, design: .monospaced))
                        .tracking(-2)
                        .contentTransition(.numericText())
                }

                RecordingSignal(
                    isActive: snapshot.isActive,
                    phase: reduceMotion ? 0 : date.timeIntervalSinceReferenceDate
                )
                .frame(maxWidth: 260)
                .frame(height: compact ? 34 : 44)

                ZStack {
                    Circle()
                        .stroke(MonoTheme.recording.opacity(snapshot.isActive ? 0.30 : 0.13), lineWidth: 1)
                        .frame(width: compact ? 126 : 150, height: compact ? 126 : 150)
                        .scaleEffect(snapshot.isActive && !reduceMotion ? 1.06 : 1)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: snapshot.isActive)
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: compact ? 105 : 124, height: compact ? 105 : 124)
                        .glassEffect(.regular.tint(MonoTheme.primary.opacity(0.14)).interactive(), in: .circle)
                        .shadow(color: MonoTheme.recording.opacity(0.14), radius: 24, y: 10)
                    if snapshot.isActive {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(MonoTheme.recording)
                            .frame(width: 46, height: 46)
                    } else {
                        MonoIcon("record.circle", size: compact ? 65 : 76, weight: 2.1)
                    }
                    SystemBroadcastPicker(
                        extensionBundleIdentifier: "com.linchengbo.mono.screenaudio.broadcast",
                        launchToken: broadcastLaunchToken
                    )
                    .opacity(0.012)
                    .frame(width: compact ? 120 : 140, height: compact ? 120 : 140)
                    .contentShape(Rectangle())
                    .accessibilityLabel(snapshot.isActive ? "停止屏幕录制" : "开始屏幕录制")
                }

                Text(snapshot.isActive ? "轻触结束录制" : "轻触开始·离开 App 后继续")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(MonoTheme.muted(scheme))
            }
            .padding(compact ? 20 : 24)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 245 : 310)
        .glassEffect(.regular.tint(MonoTheme.primary.opacity(0.08)), in: .rect(cornerRadius: 34))
        .foregroundStyle(MonoTheme.ink(scheme))
        .accessibilityElement(children: .contain)
    }

    private func commandDeck(snapshot: ScreenRecordingSnapshot) -> some View {
        VStack(spacing: 14) {
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 0.86)) {
                    deckExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(deckExpanded ? "收起录制控制" : "快速调整录制")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                    Spacer()
                    MonoIcon("chevron.up", size: 13, weight: 2.2)
                        .rotationEffect(.degrees(deckExpanded ? 180 : 0))
                }
                .foregroundStyle(MonoTheme.muted(scheme))
                .contentShape(Rectangle())
            }
            .buttonStyle(MonoSpringPressStyle())

            HStack(spacing: 0) {
                stageValue((ScreenResolutionPreset(rawValue: screenResolution) ?? .native).title, label: "画质")
                stageValue("\(screenFrameRate)", label: "FPS")
                stageValue(screenCodec.uppercased(), label: "编码")
                stageValue((ScreenOrientationPreset(rawValue: screenOrientation) ?? .automatic).title, label: "方向")
            }

            if deckExpanded {
                quickPresetPanel
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.97, anchor: .bottom)),
                                removal: .opacity.combined(with: .move(edge: .bottom))
                            )
                    )
            }

            HStack(spacing: 8) {
            NavigationLink {
                AudioRecorderView()
            } label: {
                    tool(label: "录音", icon: "waveform")
            }
            .buttonStyle(.plain)
            Button(action: openStudio) {
                    tool(label: "剪辑", icon: "timeline.selection")
            }
            .buttonStyle(.plain)
            Button(action: openLibrary) {
                    tool(label: "作品", icon: "rectangle.stack")
            }
            .buttonStyle(.plain)
            }

            latestStatus(snapshot: snapshot)
        }
        .padding(14)
        .foregroundStyle(MonoTheme.ink(scheme))
        .monoPanel()
        .offset(y: max(0, deckDrag * 0.16))
        .gesture(
            DragGesture(minimumDistance: 10)
                .updating($deckDrag) { value, state, _ in state = value.translation.height }
                .onEnded { value in
                    let shouldExpand = value.predictedEndTranslation.height < -34
                    let shouldCollapse = value.predictedEndTranslation.height > 34
                    guard shouldExpand || shouldCollapse else { return }
                    withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.34, dampingFraction: 0.84)) {
                        deckExpanded = shouldExpand
                    }
                }
        )
        .sensoryFeedback(.selection, trigger: deckExpanded)
    }

    private var quickPresetPanel: some View {
        VStack(spacing: 10) {
            quickChoiceRow(
                title: "画质",
                values: ScreenResolutionPreset.allCases.map { ($0.rawValue, $0.title) },
                selection: $screenResolution
            )
            quickChoiceRow(
                title: "帧率",
                values: [("30", "30"), ("60", "60")],
                selection: Binding(
                    get: { String(screenFrameRate) },
                    set: { screenFrameRate = Int($0) ?? 60 }
                )
            )
            quickChoiceRow(
                title: "方向",
                values: ScreenOrientationPreset.allCases.map { ($0.rawValue, $0.title) },
                selection: $screenOrientation
            )
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func quickChoiceRow(
        title: String,
        values: [(String, String)],
        selection: Binding<String>
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(MonoTheme.muted(scheme))
                .frame(width: 30, alignment: .leading)
            ForEach(values, id: \.0) { value, label in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { selection.wrappedValue = value }
                } label: {
                    Text(label)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(selection.wrappedValue == value ? MonoTheme.primary.opacity(0.13) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(MonoSpringPressStyle())
            }
        }
    }

    private func stageValue(_ value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(MonoTheme.muted(scheme))
        }
        .frame(maxWidth: .infinity, minHeight: 38)
    }

    private func tool(label: String, icon: String) -> some View {
        VStack(spacing: 5) {
            MonoIcon(icon, size: 20, weight: 2.1)
                .foregroundStyle(MonoTheme.primary)
                .frame(width: 42, height: 42)
                .background(MonoTheme.primary.opacity(0.10))
                .clipShape(Circle())
            Text(label).font(.system(.caption, design: .rounded, weight: .bold))
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .contentShape(Rectangle())
    }

    private func recordingAtmosphere(snapshot: ScreenRecordingSnapshot) -> some View {
        ZStack {
            Circle()
                .fill(MonoTheme.recording.opacity(snapshot.isActive ? 0.18 : 0.06))
                .frame(width: 430, height: 430)
                .blur(radius: 110)
                .offset(y: -30)
            Circle()
                .fill(MonoTheme.electric.opacity(0.12))
                .frame(width: 360, height: 360)
                .blur(radius: 105)
                .offset(x: -190, y: 210)
        }
        .allowsHitTesting(false)
    }

    private func stageValue(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.62))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
    }

    private var stageDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: 14)
    }

    @ViewBuilder
    private func latestStatus(snapshot: ScreenRecordingSnapshot) -> some View {
        if snapshot.isActive {
            HStack(spacing: 10) {
                MonoIcon("iphone.gen3.radiowaves.left.and.right", size: 21, weight: 2)
                    .foregroundStyle(MonoTheme.recording)
                Text("录屏正在后台运行")
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                Spacer()
                Text("LIVE")
                    .font(.system(.caption2, design: .monospaced, weight: .black))
                    .foregroundStyle(MonoTheme.recording)
            }
            .foregroundStyle(MonoTheme.ink(scheme))
            .frame(minHeight: 44)
        } else if let completed = snapshot.lastCompletedAt {
            HStack(spacing: 10) {
                MonoIcon("checkmark.circle.fill", size: 20, weight: 2.1)
                    .foregroundStyle(MonoTheme.success)
                Text("最近完成")
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                Spacer()
                Text(completed.formatted(date: .omitted, time: .shortened))
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(MonoTheme.muted(scheme))
            }
            .foregroundStyle(MonoTheme.ink(scheme))
            .frame(minHeight: 44)
        }
    }

    private var recordingSummary: String {
        let resolution = ScreenResolutionPreset(rawValue: screenResolution) ?? .native
        let orientation = ScreenOrientationPreset(rawValue: screenOrientation) ?? .automatic
        return "\(screenCodec.uppercased()) · \(screenFrameRate) · \(resolution.title) · \(orientation.title)"
    }

    private func elapsed(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60)
    }
}

private struct SignalStageCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 17
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}

private struct RecordingSignal: View {
    let isActive: Bool
    let phase: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 5) {
                ForEach(0..<23, id: \.self) { index in
                    let wave = sin(phase * 4 + Double(index) * 0.72)
                    let idle = 10 + CGFloat((index * 13) % 26)
                    let live = 15 + CGFloat(abs(wave)) * 58
                    Capsule()
                        .fill(
                            isActive
                                ? MonoTheme.recording.opacity(index.isMultiple(of: 4) ? 0.90 : 0.42)
                                : MonoTheme.primary.opacity(index.isMultiple(of: 4) ? 0.62 : 0.24)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: isActive ? live : idle)
                        .animation(.easeOut(duration: 0.18), value: live)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

private struct SystemBroadcastPicker: UIViewRepresentable {
    let extensionBundleIdentifier: String
    let launchToken: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = FullSizeBroadcastPicker()
        picker.preferredExtension = extensionBundleIdentifier
        picker.showsMicrophoneButton = true
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        uiView.preferredExtension = extensionBundleIdentifier
        guard launchToken > 0, launchToken != context.coordinator.lastLaunchToken else { return }
        context.coordinator.lastLaunchToken = launchToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            (uiView as? FullSizeBroadcastPicker)?.trigger()
        }
    }

    final class Coordinator {
        var lastLaunchToken = 0
    }
}

private final class FullSizeBroadcastPicker: RPSystemBroadcastPickerView {
    override func layoutSubviews() {
        super.layoutSubviews()
        buttons.forEach { button in
            button.frame = bounds
            button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
    }

    func trigger() {
        buttons.first?.sendActions(for: .touchUpInside)
    }

    private var buttons: [UIButton] {
        subviews.compactMap { $0 as? UIButton }
    }
}
