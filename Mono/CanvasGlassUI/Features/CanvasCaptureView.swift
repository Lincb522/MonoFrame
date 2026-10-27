import SwiftUI
import UIKit

struct CanvasCaptureView: View {
    let launchToken: Int
    let openAudioRecorder: () -> Void

    @AppStorage(
        ScreenRecordingPreferenceKey.resolution,
        store: UserDefaults(suiteName: SharedStorage.appGroup)
    ) private var resolution = ScreenResolutionPreset.p1080.rawValue
    @AppStorage(
        ScreenRecordingPreferenceKey.frameRate,
        store: UserDefaults(suiteName: SharedStorage.appGroup)
    ) private var frameRate = 60

    @State private var pickerError: String?
    @StateObject private var captions = LiveCaptionService()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 49

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 20)) { timeline in
                    let snapshot = ScreenRecordingSnapshot.read(at: timeline.date)
                    stage(snapshot: snapshot, date: timeline.date)
                }

                notice
                    .padding(.top, noticeMessage == nil ? 0 : 12)

                settings
                    .padding(.top, 18)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.bottom, 108)
        }
        .scrollIndicators(.hidden)
        .background(CanvasBackdrop())
        .onChange(of: launchToken) { _, _ in pickerError = nil }
        .accessibilityIdentifier("canvas.capture.page")
    }

    private func stage(snapshot: ScreenRecordingSnapshot, date: Date) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle()
                    .fill(snapshot.isActive ? CanvasColor.coral : CanvasColor.coral.opacity(0.88))
                    .frame(width: 6, height: 6)
                Text(snapshot.isActive ? "正在录屏" : "开始录屏")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CanvasColor.secondary(scheme))
            }
            .padding(.top, 86)

            Text(timecode(snapshot.elapsed(at: date)))
                .font(.system(size: timerSize, weight: .regular, design: .rounded))
                .monospacedDigit()
                .tracking(-1.35)
                .foregroundStyle(CanvasColor.ink(scheme))
                .contentTransition(reduceMotion ? .identity : .numericText())
                .padding(.top, 10)
                .accessibilityLabel("录制时长 \(timecode(snapshot.elapsed(at: date)))")

            CanvasWaveform(
                active: snapshot.isActive,
                phase: date.timeIntervalSinceReferenceDate
            )
            .frame(height: 42)
            .padding(.horizontal, 8)
            .padding(.top, 42)

            transport(snapshot: snapshot)
                .padding(.top, 54)
        }
    }

    private func transport(snapshot: ScreenRecordingSnapshot) -> some View {
        ZStack {
            CanvasGlassSurface(cornerRadius: 30) {
                HStack {
                    Button(action: openAudioRecorder) {
                        transportAction(
                            title: "录音",
                            glyph: .microphone,
                            selected: false
                        )
                    }
                    .buttonStyle(CanvasPressStyle())
                    .accessibilityIdentifier("canvas.capture.openAudioRecorder")

                    Spacer(minLength: 88)

                    Button {
                        Task {
                            if captions.isListening { captions.stop() }
                            else { await captions.start() }
                        }
                    } label: {
                        transportAction(
                            title: captions.isListening ? "字幕开" : "字幕",
                            glyph: .captions,
                            selected: captions.isListening
                        )
                    }
                    .buttonStyle(CanvasPressStyle())
                    .accessibilityLabel("实时字幕")
                    .accessibilityValue(captions.isListening ? "已开启" : "已关闭")
                    .accessibilityAddTraits(captions.isListening ? .isSelected : [])
                    .accessibilityIdentifier("canvas.capture.captions")
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(maxWidth: 342, minHeight: 68)
            }

            CanvasBroadcastPicker(
                launchToken: launchToken,
                accessibilityLabel: snapshot.isActive ? "停止屏幕录制" : "开始屏幕录制",
                onResult: { result in
                    switch result {
                    case .success: pickerError = nil
                    case let .failure(error): pickerError = error.localizedDescription
                    }
                }
            ) {
                ZStack {
                    Circle()
                        .fill(CanvasColor.background(scheme))
                        .frame(width: 64, height: 64)
                    Circle()
                        .stroke(CanvasColor.coral.opacity(0.34), lineWidth: 2)
                        .frame(width: 58, height: 58)
                    Circle()
                        .fill(CanvasColor.coral)
                        .frame(width: snapshot.isActive ? 30 : 50, height: snapshot.isActive ? 30 : 50)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: snapshot.isActive ? 8 : 25,
                                style: .continuous
                            )
                        )
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.92),
                            value: snapshot.isActive
                        )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 88)
        .accessibilityIdentifier("canvas.capture.transport")
    }

    private func transportAction(
        title: String,
        glyph: CanvasGlyphName,
        selected: Bool
    ) -> some View {
        VStack(spacing: 4) {
            CanvasGlyph(glyph, size: 20)
            Text(title).font(.caption2.weight(.medium))
        }
        .foregroundStyle(selected ? CanvasColor.accent(scheme) : CanvasColor.secondary(scheme))
        .frame(width: 62)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var notice: some View {
        if let noticeMessage {
            CanvasInlineNotice(
                message: noticeMessage,
                tone: pickerError != nil ? .error : captionsTone
            )
            .transition(.opacity)
        }
    }

    private var noticeMessage: String? {
        if let pickerError { return pickerError }
        if let extensionError { return extensionError }
        switch captions.state {
        case let .failed(message): return message
        case .listening where !captions.latestLine.isEmpty: return captions.latestLine
        default: return nil
        }
    }

    private var captionsTone: CanvasInlineNotice.Tone {
        if case .failed = captions.state { return .warning }
        return .info
    }

    private var settings: some View {
        VStack(spacing: 0) {
            Menu {
                ForEach(
                    [ScreenResolutionPreset.p720, .p1080, .p2K, .native],
                    id: \.rawValue
                ) { preset in
                    Button(preset.title) { resolution = preset.rawValue }
                }
            } label: {
                CanvasPlainRow("分辨率", accessibilityValue: currentResolution.title) {
                    rowValue(currentResolution.title)
                }
            }
            .buttonStyle(CanvasPressStyle())
            .accessibilityIdentifier("canvas.capture.resolution")

            CanvasHairline()

            Menu {
                ForEach([24, 30, 60], id: \.self) { value in
                    Button("\(value) fps") { frameRate = value }
                }
            } label: {
                CanvasPlainRow("帧率", accessibilityValue: "\(frameRate) 帧每秒") {
                    rowValue("\(frameRate) fps")
                }
            }
            .buttonStyle(CanvasPressStyle())
            .accessibilityIdentifier("canvas.capture.frameRate")

            CanvasHairline()

            Menu {
                Button("打开麦克风权限设置") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
                Button("录屏时在系统面板中开启麦克风") {}
                    .disabled(true)
            } label: {
                CanvasPlainRow("麦克风", accessibilityValue: "跟随系统面板") {
                    rowValue("跟随系统")
                }
            }
            .buttonStyle(CanvasPressStyle())

            CanvasHairline()

            CanvasPlainRow("系统声音", accessibilityValue: "开启") {
                Text("开启")
                    .font(.subheadline)
                    .foregroundStyle(CanvasColor.tertiary(scheme))
            }
        }
    }

    private func rowValue(_ value: String) -> some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.subheadline)
                .foregroundStyle(CanvasColor.tertiary(scheme))
            CanvasGlyph(.chevronRight, size: 13, weight: 1.6)
                .foregroundStyle(CanvasColor.tertiary(scheme))
        }
    }

    private var currentResolution: ScreenResolutionPreset {
        ScreenResolutionPreset(rawValue: resolution) ?? .p1080
    }

    private var extensionError: String? {
        guard let defaults = UserDefaults(suiteName: SharedStorage.appGroup),
              let message = defaults.string(forKey: ScreenRecordingPreferenceKey.lastError),
              !message.isEmpty else { return nil }
        let timestamp = defaults.double(forKey: ScreenRecordingPreferenceKey.lastErrorAt)
        guard timestamp > 0, Date().timeIntervalSince1970 - timestamp < 600 else { return nil }
        return message
    }

    private func timecode(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", value / 3_600, value / 60 % 60, value % 60)
    }
}
