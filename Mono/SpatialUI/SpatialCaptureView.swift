import ReplayKit
import SwiftUI
import UIKit

struct SpatialCaptureView: View {
    let launchToken: Int
    @AppStorage(ScreenRecordingPreferenceKey.resolution, store: UserDefaults(suiteName: SharedStorage.appGroup)) private var resolution = ScreenResolutionPreset.native.rawValue
    @AppStorage(ScreenRecordingPreferenceKey.frameRate, store: UserDefaults(suiteName: SharedStorage.appGroup)) private var frameRate = 60
    @State private var controlsVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let snapshot = ScreenRecordingSnapshot.read(at: timeline.date)
            GeometryReader { proxy in
                ZStack {
                    Image("SpatialIceBackdrop")
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                    LinearGradient(
                        colors: [.white.opacity(0.18), .clear, SpatialColor.iceDeep.opacity(0.16)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            qualityControl
                        }
                        Spacer()
                        timer(snapshot, date: timeline.date)
                        Spacer(minLength: 36)
                        recordGesture(snapshot)
                        Text(snapshot.isActive ? "向下滑动停止" : "轻触开始")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 13)
                        Spacer()
                        audioRibbon
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
        }
    }

    private var qualityControl: some View {
            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 1)) { controlsVisible.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text((ScreenResolutionPreset(rawValue: resolution) ?? .native).title)
                    Image(systemName: "waveform")
                }
                .font(.system(.caption, design: .rounded, weight: .bold))
                .padding(.horizontal, 13)
                .frame(minHeight: 40)
                .spatialGlass(Capsule(), interactive: true)
            }
            .buttonStyle(SpatialGlassButtonStyle())
        .overlay(alignment: .topTrailing) {
            if controlsVisible {
                captureOptions
                    .offset(y: 48)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                    .zIndex(4)
            }
        }
    }

    private var captureOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("画质").font(.caption.bold()).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach([ScreenResolutionPreset.p720, .p1080, .p2K, .native]) { item in
                    Button(item.title) { resolution = item.rawValue }
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(resolution == item.rawValue ? .white : .primary)
                        .padding(.horizontal, 10).frame(height: 34)
                        .spatialGlass(Capsule(), tint: resolution == item.rawValue ? SpatialColor.seaDeep : nil, interactive: true)
                }
            }
            HStack { Text("帧率").font(.caption.bold()); Spacer(); Text("\(frameRate) FPS").font(.caption.monospaced()) }
            Slider(value: Binding(get: { Double(frameRate) }, set: { frameRate = Int($0.rounded()) }), in: 15...60, step: 1).tint(SpatialColor.sea)
        }
        .padding(14)
        .frame(width: 280)
        .spatialGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func timer(_ snapshot: ScreenRecordingSnapshot, date: Date) -> some View {
        VStack(spacing: 10) {
            Text(format(snapshot.elapsed(at: date)))
                .font(.system(size: 46, weight: .ultraLight, design: .rounded))
                .tracking(-2.6)
                .contentTransition(.numericText())
            Text(snapshot.isActive ? "录制中" : "准备")
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
            if snapshot.isActive {
                SpatialWave(active: true, phase: date.timeIntervalSinceReferenceDate, count: 7)
                    .frame(width: 48, height: 25)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
    }

    private func recordGesture(_ snapshot: ScreenRecordingSnapshot) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.76), lineWidth: 2).padding(5)
            Circle().trim(from: 0, to: snapshot.isActive ? 0.82 : 0.24)
                .stroke(SpatialColor.sea, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 1), value: snapshot.isActive)
            Circle().fill(Color.white.opacity(0.035)).padding(18)
                .spatialGlass(Circle(), interactive: true)
            if snapshot.isActive {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SpatialColor.sea)
                    .frame(width: 38, height: 38)
            } else {
                Circle()
                    .fill(SpatialColor.sea)
                    .frame(width: 52, height: 52)
            }
            SpatialBroadcastPicker(extensionBundleIdentifier: "com.linchengbo.mono.screenaudio.broadcast", launchToken: launchToken)
                .opacity(0.01)
        }
        .frame(width: 164, height: 164)
        .scaleEffect(snapshot.isActive && !reduceMotion ? 1.025 : 1)
        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: snapshot.isActive)
    }

    private var audioRibbon: some View {
        GlassEffectContainer(spacing: 9) {
            HStack(spacing: 9) {
                Button { } label: {
                    Image(systemName: "mic.slash")
                        .frame(width: 48, height: 48)
                        .spatialGlass(Circle(), interactive: true)
                }
                .buttonStyle(SpatialGlassButtonStyle())
                NavigationLink { AudioRecorderView() } label: {
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .foregroundStyle(SpatialColor.seaDeep)
                        .frame(width: 58, height: 48)
                        .spatialGlass(Capsule(), tint: SpatialColor.sea.opacity(0.12), interactive: true)
                }
                .buttonStyle(SpatialGlassButtonStyle())
                Button { } label: {
                    Image(systemName: "mic")
                        .frame(width: 48, height: 48)
                        .spatialGlass(Circle(), interactive: true)
                }
                .buttonStyle(SpatialGlassButtonStyle())
                Button { } label: {
                    Image(systemName: "camera")
                        .frame(width: 48, height: 48)
                        .spatialGlass(Circle(), interactive: true)
                }
                .buttonStyle(SpatialGlassButtonStyle())
            }
            .foregroundStyle(.primary)
            .padding(6)
        }
    }

    private func format(_ duration: TimeInterval) -> String {
        let value = max(0, Int(duration)); return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
}

private struct SpatialBroadcastPicker: UIViewRepresentable {
    let extensionBundleIdentifier: String
    let launchToken: Int
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = SpatialFullSizePicker()
        picker.preferredExtension = extensionBundleIdentifier
        picker.showsMicrophoneButton = true
        return picker
    }
    func updateUIView(_ view: RPSystemBroadcastPickerView, context: Context) {
        view.preferredExtension = extensionBundleIdentifier
        guard launchToken > 0, context.coordinator.token != launchToken else { return }
        context.coordinator.token = launchToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { (view as? SpatialFullSizePicker)?.trigger() }
    }
    final class Coordinator { var token = 0 }
}

private final class SpatialFullSizePicker: RPSystemBroadcastPickerView {
    override func layoutSubviews() { super.layoutSubviews(); buttons.forEach { $0.frame = bounds; $0.autoresizingMask = [.flexibleWidth, .flexibleHeight] } }
    func trigger() { buttons.first?.sendActions(for: .touchUpInside) }
    private var buttons: [UIButton] { subviews.compactMap { $0 as? UIButton } }
}
