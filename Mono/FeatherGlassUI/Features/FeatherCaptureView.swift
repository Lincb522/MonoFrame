import SwiftUI

struct FeatherCaptureView: View {
    let launchToken: Int

    @AppStorage(
        ScreenRecordingPreferenceKey.resolution,
        store: UserDefaults(suiteName: SharedStorage.appGroup)
    ) private var resolution = ScreenResolutionPreset.native.rawValue
    @AppStorage(
        ScreenRecordingPreferenceKey.frameRate,
        store: UserDefaults(suiteName: SharedStorage.appGroup)
    ) private var frameRate = 60
    @State private var scheduledLaunchToken = 0
    @State private var pickerError: String?
    @StateObject private var captions = LiveCaptionService()
    @StateObject private var scheduler = CaptureScheduler()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var timecodeSize: CGFloat = 46

    var body: some View {
        FeatherPage {
            VStack(spacing: 30) {
                TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 20)) { timeline in
                    let snapshot = ScreenRecordingSnapshot.read(at: timeline.date)
                    recordingStage(snapshot: snapshot, date: timeline.date)
                }

                noticeArea
                captureSettings
            }
        }
        .featherNavigationTitle("录制")
        .onChange(of: scheduler.fireToken) { _, _ in
            pickerError = nil
            scheduledLaunchToken &+= 1
        }
        .onChange(of: launchToken) { _, _ in pickerError = nil }
    }

    private func recordingStage(snapshot: ScreenRecordingSnapshot, date: Date) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 14) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(snapshot.isActive ? FeatherColor.coral : FeatherColor.secondary(scheme))
                        .frame(width: 7, height: 7)
                    Text(snapshot.isActive ? "正在录屏" : "准备录制")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FeatherColor.secondary(scheme))
                }

                Text(timecode(snapshot.elapsed(at: date)))
                    .font(.system(size: timecodeSize, weight: .regular, design: .monospaced))
                    .monospacedDigit()
                    .tracking(-1.6)
                    .foregroundStyle(FeatherColor.ink(scheme))
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .accessibilityLabel("录制时长 \(timecode(snapshot.elapsed(at: date)))")

                FeatherWaveform(
                    active: snapshot.isActive,
                    phase: date.timeIntervalSinceReferenceDate,
                    tint: FeatherColor.lagoon
                )
                .frame(height: 38)
                .padding(.horizontal, 8)
            }
            .padding(.top, 26)

            captureToolStrip(snapshot: snapshot)

            HStack(spacing: 8) {
                Text(currentResolution.title)
                Text("·")
                Text("\(frameRate) fps")
                if scheduler.isArmed {
                    Text("·")
                    Text(scheduler.countdownText)
                        .monospacedDigit()
                        .foregroundStyle(FeatherColor.danger(scheme))
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(FeatherColor.secondary(scheme))
        }
        .frame(maxWidth: .infinity, minHeight: 330)
        .accessibilityElement(children: .contain)
    }

    private func captureToolStrip(snapshot: ScreenRecordingSnapshot) -> some View {
        FeatherGlassControl(cornerRadius: 30) {
            HStack(spacing: 8) {
                NavigationLink {
                    FeatherAudioRecorderView()
                } label: {
                    toolAction(title: "录音", icon: "microphone")
                }
                .buttonStyle(FeatherPressStyle())
                .accessibilityIdentifier("feather.capture.audio")

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(FeatherColor.coral)
                        .frame(width: 70, height: 70)
                    RoundedRectangle(cornerRadius: snapshot.isActive ? 8 : 23, style: .continuous)
                        .fill(.white)
                        .frame(
                            width: snapshot.isActive ? 26 : 34,
                            height: snapshot.isActive ? 26 : 34
                        )
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.92),
                            value: snapshot.isActive
                        )
                        .allowsHitTesting(false)
                    FeatherBroadcastPicker(
                        extensionBundleIdentifier: "com.linchengbo.mono.screenaudio.broadcast",
                        launchToken: launchToken &+ scheduledLaunchToken,
                        accessibilityLabel: snapshot.isActive ? "停止屏幕录制" : "开始屏幕录制",
                        onFailure: { pickerError = $0 }
                    )
                    .frame(width: 70, height: 70)
                    .contentShape(Circle())
                }
                .frame(width: 82, height: 82)

                Spacer(minLength: 0)

                Button {
                    Task {
                        if captions.isListening { captions.stop() }
                        else { await captions.start() }
                    }
                } label: {
                    toolAction(title: captions.isListening ? "字幕开" : "字幕", icon: "captions.bubble")
                }
                .buttonStyle(FeatherPressStyle())
                .accessibilityLabel("实时字幕")
                .accessibilityValue(captions.isListening ? "已开启" : "已关闭")
                .accessibilityAddTraits(captions.isListening ? .isSelected : [])
                .accessibilityIdentifier("feather.capture.captions")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
    }

    private func toolAction(title: String, icon: String) -> some View {
        VStack(spacing: 5) {
            FeatherIcon(name: icon, size: 20)
            Text(title).font(.caption.weight(.medium))
        }
        .foregroundStyle(FeatherColor.ink(scheme))
        .frame(width: 68)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var noticeArea: some View {
        if let pickerError {
            FeatherInlineNotice(message: pickerError, tone: .error)
                .transition(.opacity)
        } else if let extensionError {
            FeatherInlineNotice(message: extensionError, tone: .error)
                .transition(.opacity)
        } else {
            switch captions.state {
            case let .failed(message):
                FeatherInlineNotice(message: message, tone: .warning)
            case .listening where !captions.latestLine.isEmpty:
                FeatherInlineNotice(message: captions.latestLine, tone: .info)
            default:
                EmptyView()
            }
        }
    }

    private var captureSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatherSectionHeader("录制设置")

            FeatherSurface {
                VStack(spacing: 0) {
                    settingRow(title: "分辨率", detail: "输出画面的长边尺寸") {
                        Picker("分辨率", selection: $resolution) {
                            ForEach(
                                [ScreenResolutionPreset.p720, .p1080, .p2K, .native],
                                id: \.rawValue
                            ) { preset in
                                Text(preset.title).tag(preset.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    FeatherRule().padding(.leading, 16)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("帧率").font(.body.weight(.medium))
                                Text("更高帧率会增加文件体积")
                                    .font(.caption)
                                    .foregroundStyle(FeatherColor.secondary(scheme))
                            }
                            Spacer()
                            Text("\(frameRate) fps")
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { Double(frameRate) },
                                set: { frameRate = ScreenFrameRateLimit.clamp(Int($0.rounded())) }
                            ),
                            in: 15...60,
                            step: 1
                        )
                        .tint(FeatherColor.accent(scheme))
                        .accessibilityLabel("录制帧率")
                        .accessibilityValue("\(frameRate) 帧每秒")
                        .accessibilityIdentifier("feather.capture.frameRate")
                    }
                    .padding(16)

                    FeatherRule().padding(.leading, 16)

                    settingRow(title: "倒计时", detail: scheduler.isArmed ? scheduler.countdownText : "关闭") {
                        if scheduler.isArmed {
                            Button("取消") { scheduler.cancel() }
                                .foregroundStyle(FeatherColor.danger(scheme))
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                                .buttonStyle(FeatherPressStyle())
                                .accessibilityLabel("取消倒计时")
                        } else {
                            Menu {
                                Button("5 秒") { Task { await scheduler.arm(after: 5) } }
                                Button("30 秒") { Task { await scheduler.arm(after: 30) } }
                                Button("1 分钟") { Task { await scheduler.arm(after: 60) } }
                            } label: {
                                Text("设置")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("设置倒计时")
                        }
                    }
                }
            }
        }
    }

    private func settingRow<Trailing: View>(
        title: String,
        detail: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    settingCopy(title: title, detail: detail)
                    trailing()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(spacing: 16) {
                    settingCopy(title: title, detail: detail)
                    Spacer(minLength: 12)
                    trailing()
                }
            }
        }
        .foregroundStyle(FeatherColor.ink(scheme))
        .padding(16)
    }

    private func settingCopy(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(FeatherColor.secondary(scheme))
        }
    }

    private var currentResolution: ScreenResolutionPreset {
        ScreenResolutionPreset(rawValue: resolution) ?? .native
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
