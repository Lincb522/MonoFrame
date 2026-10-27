import SwiftUI

struct PearlCaptureView: View {
    let launchToken: Int
    let openAudio: () -> Void
    @AppStorage(ScreenRecordingPreferenceKey.resolution, store: UserDefaults(suiteName: SharedStorage.appGroup)) private var resolution = ScreenResolutionPreset.p1080.rawValue
    @AppStorage(ScreenRecordingPreferenceKey.frameRate, store: UserDefaults(suiteName: SharedStorage.appGroup)) private var frameRate = 60
    @AppStorage(ScreenRecordingPreferenceKey.orientation, store: UserDefaults(suiteName: SharedStorage.appGroup)) private var orientation = ScreenOrientationPreset.automatic.rawValue
    @StateObject private var captions = LiveCaptionService()
    @State private var pickerError: String?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { container in
            PearlPage(maxWidth: 1080) {
                VStack(alignment: .leading, spacing: 20) {
                    PearlRootHeader(title: "录制", brand: true) { PearlSettingsLink() }
                    modeControl
                    if container.size.width > 740 && !typeSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: 48) {
                            clockFace.frame(maxWidth: .infinity)
                            actionColumn.frame(width: 300).padding(.top, 45)
                        }
                    } else {
                        clockFace
                        actionColumn
                    }
                    if let message = pickerError { PearlInlineNotice(message: message, tone: .error) }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let message = extensionError(at: context.date) { PearlInlineNotice(message: message, tone: .error) }
                    }
                    captionStatus
                }
            }
        }
    }

    private var modeControl: some View {
        HStack(spacing: 25) {
            HStack(spacing: 8) {
                Circle().fill(PearlColor.action(scheme)).frame(width: 9, height: 9)
                Text("屏幕录制").font(.headline)
            }.frame(minHeight: 44).accessibilityAddTraits(.isSelected)
            Button(action: openAudio) {
                HStack(spacing: 7) { Text("录音"); PearlGlyph(.chevronRight, size: 14) }
                    .font(.headline).foregroundStyle(PearlColor.secondary(scheme)).frame(minHeight: 44)
            }.buttonStyle(PearlPressStyle()).accessibilityIdentifier("pearl.capture.openAudio")
            Spacer(minLength: 0)
        }.overlay(alignment: .bottom) { PearlHairline() }
    }

    private var clockFace: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let state = ScreenRecordingSnapshot.read(at: context.date)
            let seconds = max(0, Int(state.elapsed(at: context.date)))
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    clockText(seconds, size: typeSize.isAccessibilitySize ? 64 : 112)
                    clockText(seconds, size: 76)
                    clockText(seconds, size: 52)
                }.accessibilityLabel("录制时长，\(elapsed(Double(seconds)))")
                HStack(alignment: .firstTextBaseline) {
                    Text(state.isActive ? "正在录屏" : "准备就绪").font(.title2.weight(.bold))
                    Spacer(minLength: 8)
                    Text("当前屏幕").font(.subheadline).foregroundStyle(PearlColor.secondary(scheme))
                }
                if !typeSize.isAccessibilitySize {
                    PearlDotMatrix(progress: Double(seconds % 60) / 60, columns: 15, rows: 4, active: state.isActive)
                        .aspectRatio(15.0 / 4.0, contentMode: .fit)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func clockText(_ seconds: Int, size: CGFloat) -> some View {
        Text(seconds >= 3600 ? elapsed(Double(seconds)) : String(format: "%02d:%02d", seconds / 60, seconds % 60))
            .font(.system(size: size, weight: .bold)).monospacedDigit().tracking(-3)
            .foregroundStyle(PearlColor.display(scheme)).fixedSize()
    }

    private var actionColumn: some View {
        VStack(spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { parameterControls }
                VStack(spacing: 8) { parameterControls }
            }
            PearlBroadcastPicker(launchToken: launchToken, accessibilityLabel: "打开系统录屏面板") { result in
                if case let .failure(error) = result { pickerError = error.localizedDescription }
                else { pickerError = nil }
            } label: { PearlPrimaryLabel(title: "开始录屏", recording: true) }
                .frame(height: typeSize.isAccessibilitySize ? 100 : 74)
            Text("在系统面板中开始或停止录屏")
                .font(.caption).foregroundStyle(PearlColor.secondary(scheme))
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var parameterControls: some View {
        Menu {
            ForEach([ScreenResolutionPreset.p720, .p1080, .p2K, .native], id: \.rawValue) { preset in
                Button(preset.title) { resolution = preset.rawValue }
            }
        } label: { parameterLabel(.video, (ScreenResolutionPreset(rawValue: resolution) ?? .p1080).title) }
            .accessibilityLabel("分辨率").accessibilityIdentifier("pearl.capture.resolution")
        Menu {
            ForEach([24, 30, 60], id: \.self) { rate in Button("\(rate) fps") { frameRate = rate } }
        } label: { parameterLabel(.timer, "\(frameRate) fps") }
            .accessibilityLabel("帧率").accessibilityIdentifier("pearl.capture.frameRate")
        Menu {
            ForEach(ScreenOrientationPreset.allCases) { value in Button(value.title) { orientation = value.rawValue } }
        } label: { parameterLabel(.orientation, (ScreenOrientationPreset(rawValue: orientation) ?? .automatic).title + "方向") }
            .accessibilityLabel("录制方向")
    }

    private func parameterLabel(_ glyph: PearlGlyphName, _ title: String) -> some View {
        HStack(spacing: 5) {
            PearlGlyph(glyph, size: 19)
            Text(title).font(.caption.weight(.medium)).fixedSize()
            PearlGlyph(.chevronRight, size: 10).rotationEffect(.degrees(90))
        }
        .foregroundStyle(PearlColor.ink(scheme)).padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 48)
        .background(PearlColor.elevated(scheme), in: Capsule())
    }

    @ViewBuilder private var captionStatus: some View {
        if case let .failed(message) = captions.state {
            PearlInlineNotice(message: message, tone: .error).padding(.top, 12)
        }
        if !captions.latestLine.isEmpty {
            Text(captions.latestLine).font(.body).fixedSize(horizontal: false, vertical: true).padding(.top, 16)
        }
        Button {
            if captions.isListening { captions.stop() }
            else { Task { await captions.start() } }
        } label: {
            Label { Text(captions.isListening ? "停止实时字幕" : "实时字幕") } icon: { PearlGlyph(.captions, size: 18) }
                .font(.caption).frame(minHeight: 44)
        }.buttonStyle(PearlPressStyle()).padding(.top, 8)
    }

    private func extensionError(at date: Date) -> String? {
        guard let defaults = UserDefaults(suiteName: SharedStorage.appGroup),
              let message = defaults.string(forKey: ScreenRecordingPreferenceKey.lastError),
              !message.isEmpty else { return nil }
        let timestamp = defaults.double(forKey: ScreenRecordingPreferenceKey.lastErrorAt)
        guard timestamp > 0, date.timeIntervalSince1970 - timestamp < 600 else { return nil }
        return message
    }

    private func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}
