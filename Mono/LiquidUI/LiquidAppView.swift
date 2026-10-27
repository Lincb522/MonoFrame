import AVFoundation
import ReplayKit
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// Completely independent iOS 26 UI shell. No legacy Mono View is used for the five primary surfaces.
struct LiquidAppView: View {
    enum Destination: String, CaseIterable {
        case home = "录屏"
        case studio = "创作"
        case library = "作品"
        case transcode = "转码"
        case settings = "设置"

        var symbol: String {
            switch self {
            case .home: "record.circle"
            case .studio: "wand.and.stars"
            case .library: "square.stack.3d.up"
            case .transcode: "arrow.trianglehead.2.clockwise.rotate.90"
            case .settings: "slider.horizontal.3"
            }
        }
    }

    @State private var destination: Destination
    @State private var broadcastLaunchToken = 0
    @Namespace private var dockNamespace
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        let requested = ProcessInfo.processInfo.environment["MONO_SCREENSHOT_SECTION"]
        let initial: Destination
        switch requested {
        case "studio": initial = .studio
        case "library": initial = .library
        case "transcode": initial = .transcode
        case "settings": initial = .settings
        default: initial = .home
        }
        _destination = State(initialValue: initial)
        #else
        _destination = State(initialValue: .home)
        #endif
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackdrop()
                Group {
                    switch destination {
                    case .home: LiquidCaptureSurface(launchToken: broadcastLaunchToken)
                    case .studio: LiquidStudioSurface()
                    case .library: LiquidLibrarySurface()
                    case .transcode: LiquidTranscodeSurface()
                    case .settings: LiquidSettingsSurface()
                    }
                }
                .id(destination)
                .transition(.blurReplace)
                .safeAreaInset(edge: .bottom, spacing: 0) { dock }
                .toolbar(.hidden, for: .navigationBar)
            }
            .navigationDestination(for: Recording.self) { EditorView(recording: $0) }
            .navigationDestination(for: AudioRecording.self) { AudioEditorView(recording: $0) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await library.reload() } }
        }
        .sensoryFeedback(.selection, trigger: destination)
        .onOpenURL { url in
            guard url.scheme == "mono" else { return }
            if url.host == "capture" {
                destination = .home
                broadcastLaunchToken &+= 1
            }
        }
    }

    private var dock: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(Destination.allCases, id: \.self) { item in
                    Button {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { destination = item }
                    } label: {
                        HStack(spacing: destination == item ? 7 : 0) {
                            Image(systemName: item.symbol)
                                .font(.system(size: item == .home ? 21 : 17, weight: .semibold))
                            if destination == item {
                                Text(item.rawValue)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                            }
                        }
                        .foregroundStyle(destination == item ? .white : .primary)
                        .frame(minWidth: destination == item ? 68 : 42, minHeight: 46)
                        .glassEffect(
                            .regular.tint(destination == item ? LiquidPalette.indigo : .clear).interactive(),
                            in: .capsule
                        )
                        .glassEffectID(item, in: dockNamespace)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(7)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 5)
    }
}

enum LiquidPalette {
    static let indigo = Color(red: 0.36, green: 0.31, blue: 0.96)
    static let cyan = Color(red: 0.25, green: 0.78, blue: 0.91)
    static let mint = Color(red: 0.29, green: 0.82, blue: 0.65)
    static let coral = Color(red: 1.0, green: 0.43, blue: 0.46)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.28)
}

struct LiquidBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(
                    colors: scheme == .dark
                        ? [Color(red: 0.03, green: 0.045, blue: 0.09), Color(red: 0.08, green: 0.05, blue: 0.16), Color(red: 0.03, green: 0.11, blue: 0.13)]
                        : [Color(red: 0.91, green: 0.96, blue: 1), Color(red: 0.96, green: 0.92, blue: 1), Color(red: 0.90, green: 1, blue: 0.97)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                blob(LiquidPalette.indigo, 330, x: 165 + sin(t * 0.14) * 28, y: -310 + cos(t * 0.12) * 22)
                blob(LiquidPalette.cyan, 300, x: -190 + cos(t * 0.12) * 26, y: 130 + sin(t * 0.11) * 36)
                blob(LiquidPalette.coral, 240, x: 190 + sin(t * 0.10) * 30, y: 310 + cos(t * 0.15) * 28)
                blob(LiquidPalette.mint, 260, x: -170 + cos(t * 0.09) * 34, y: -270 + sin(t * 0.13) * 24)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func blob(_ color: Color, _ size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(color.opacity(0.33)).frame(width: size, height: size).blur(radius: 82).offset(x: x, y: y)
    }
}

struct LiquidTitle: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased())
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(LiquidPalette.indigo)
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-1.2)
            Text(detail)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LiquidCaptureSurface: View {
    let launchToken: Int
    @EnvironmentObject private var library: RecordingLibrary

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let snapshot = ScreenRecordingSnapshot.read(at: timeline.date)
            GeometryReader { proxy in
                VStack(spacing: 18) {
                    LiquidTitle(
                        eyebrow: snapshot.isActive ? "LIVE" : "CAPTURE",
                        title: snapshot.isActive ? "正在录制" : "让画面开始流动",
                        detail: snapshot.isActive ? "录制会在后台持续" : "系统级高清录屏"
                    )

                    ZStack {
                        waveform(snapshot.isActive, phase: timeline.date.timeIntervalSinceReferenceDate)
                            .padding(.horizontal, 22)
                            .opacity(0.68)

                        VStack(spacing: 18) {
                            Text(time(snapshot.elapsed(at: timeline.date)))
                                .font(.system(size: 46, weight: .medium, design: .monospaced))
                                .contentTransition(.numericText())

                            ZStack {
                                Circle().stroke(.white.opacity(0.68), lineWidth: 1.5).padding(8)
                                Circle().fill(snapshot.isActive ? LiquidPalette.coral : LiquidPalette.indigo).frame(width: 72, height: 72)
                                Image(systemName: snapshot.isActive ? "stop.fill" : "record.circle")
                                    .font(.system(size: snapshot.isActive ? 26 : 39, weight: .semibold))
                                    .foregroundStyle(.white)
                                LiquidBroadcastPicker(extensionBundleIdentifier: "com.linchengbo.mono.screenaudio.broadcast", launchToken: launchToken)
                                    .opacity(0.01)
                            }
                            .frame(width: 132, height: 132)
                            .glassEffect(.regular.tint((snapshot.isActive ? LiquidPalette.coral : LiquidPalette.indigo).opacity(0.24)).interactive(), in: .circle)

                            Text(snapshot.isActive ? "轻触停止" : "轻触开始")
                                .font(.system(.caption, design: .rounded, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassEffect(.regular.tint(LiquidPalette.indigo.opacity(0.08)), in: .rect(cornerRadius: 42))

                    HStack(spacing: 10) {
                        NavigationLink { AudioRecorderView() } label: { quick("录音", "waveform", LiquidPalette.mint) }
                        quick("作品", "square.stack.3d.up", LiquidPalette.cyan)
                            .onTapGesture { }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("本地作品").font(.caption.bold())
                            Text("\(library.recordings.count + library.audioRecordings.count) 项").font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }
        }
    }

    private func quick(_ title: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(title).font(.caption.bold())
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .glassEffect(.regular.tint(tint.opacity(0.08)).interactive(), in: .rect(cornerRadius: 22))
    }

    private func waveform(_ active: Bool, phase: TimeInterval) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<34, id: \.self) { i in
                Capsule().fill(i.isMultiple(of: 5) ? LiquidPalette.coral : LiquidPalette.indigo)
                    .frame(maxWidth: .infinity)
                    .frame(height: active ? 10 + abs(sin(phase * 3 + Double(i) * 0.58)) * 72 : 8 + CGFloat((i * 17) % 28))
            }
        }.frame(height: 100)
    }

    private func time(_ duration: TimeInterval) -> String {
        let value = max(0, Int(duration)); return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
}

private struct LiquidBroadcastPicker: UIViewRepresentable {
    let extensionBundleIdentifier: String
    let launchToken: Int
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = LiquidFullSizePicker()
        picker.preferredExtension = extensionBundleIdentifier
        picker.showsMicrophoneButton = true
        return picker
    }
    func updateUIView(_ view: RPSystemBroadcastPickerView, context: Context) {
        view.preferredExtension = extensionBundleIdentifier
        guard launchToken > 0, context.coordinator.token != launchToken else { return }
        context.coordinator.token = launchToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { (view as? LiquidFullSizePicker)?.trigger() }
    }
    final class Coordinator { var token = 0 }
}

private final class LiquidFullSizePicker: RPSystemBroadcastPickerView {
    override func layoutSubviews() { super.layoutSubviews(); buttons.forEach { $0.frame = bounds } }
    func trigger() { buttons.first?.sendActions(for: .touchUpInside) }
    private var buttons: [UIButton] { subviews.compactMap { $0 as? UIButton } }
}
