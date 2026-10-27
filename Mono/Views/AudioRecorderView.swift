import SwiftUI
import UniformTypeIdentifiers

private enum AudioRecorderWorkspaceMode: String, CaseIterable, Identifiable {
    case voice = "普通录音"
    case accompaniment = "伴奏录音"

    var id: String { rawValue }
}

struct AudioRecorderView: View {
    @StateObject private var recorder = AudioRecordingService()
    @State private var workspaceMode: AudioRecorderWorkspaceMode = .voice
    @State private var message: String?
    @State private var isImporterPresented = false
    @State private var isLyricsImporterPresented = false
    @State private var isLyricsPresented = false
    @Namespace private var workspaceSelectionNamespace
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SignalPageBackground()
            ScrollView {
                VStack(spacing: SignalSpace.lg) {
                    header
                    workspaceModePicker
                    recordingStage(compact: false)
                        .youthStageEntrance()

                    if !recorder.isActive {
                        capturePanel(compact: false)
                            .youthDelayedReveal(delay: 0.40)
                        if workspaceMode == .accompaniment {
                            accompanimentPanel(compact: false)
                                .transition(
                                    reduceMotion
                                        ? .opacity
                                        : .opacity.combined(with: .move(edge: .trailing))
                                )
                        }
                    }
                }
                .signalPagePadding()
                .padding(.bottom, SignalSpace.xl)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            importAccompaniment(result)
        }
        .fileImporter(
            isPresented: $isLyricsImporterPresented,
            allowedContentTypes: lyricContentTypes,
            allowsMultipleSelection: false
        ) { result in
            importLyrics(result)
        }
        .sheet(isPresented: $isLyricsPresented) {
            LyricsReader(
                lines: recorder.lyricLines,
                currentIndex: recorder.currentLyricIndex
            )
            .presentationBackground(SignalColor.canvas(scheme))
            .presentationCornerRadius(24)
        }
        .overlay(alignment: .top) {
            if let message {
                Text(message)
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 42)
                    .background(SignalColor.stage)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .safeAreaPadding(.top, 12)
            }
        }
        .sensoryFeedback(.selection, trigger: workspaceMode)
        .sensoryFeedback(.impact(weight: .medium), trigger: recorder.isActive)
    }

    private func recordingStage(compact: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 7) {
                    Circle()
                        .fill(recorder.isActive ? SignalColor.coral : Color.white.opacity(0.40))
                        .frame(width: 8, height: 8)
                    Text(recorder.isActive ? "REC" : "READY")
                }
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(recorder.isActive ? SignalColor.coral : .white.opacity(0.58))
                Spacer()
                Text("48 KHZ  ·  \(recorder.captureMode.rawValue)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))
            }
            .padding(.leading, SignalSpace.md)
            .padding(.trailing, 82)
            .frame(height: 44)

            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

            VStack(spacing: SignalSpace.lg) {
                meter(compact: compact)

                Text(format(recorder.elapsed))
                    .font(.system(size: 54, weight: .medium, design: .monospaced))
                    .tracking(-2.4)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                if workspaceMode == .accompaniment, recorder.hasLyrics {
                    lyricStage
                } else {
                    stateLabel
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.white.opacity(0.48))
                }

                controls
            }
            .padding(.horizontal, SignalSpace.lg)
            .padding(.vertical, SignalSpace.xl)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
        .background {
            ZStack(alignment: .topTrailing) {
                SignalColor.stage
                Circle()
                    .fill(SignalColor.violet.opacity(0.24))
                    .frame(width: 180, height: 180)
                    .blur(radius: 52)
                    .offset(x: 50, y: -50)
            }
        }
        .clipShape(YouthNotchedPanelShape(cornerRadius: 34, notchWidth: 94, notchDepth: 62))
        .overlay(alignment: .topTrailing) {
            YouthStatusBubble(
                value: recorder.isActive ? "LIVE" : "48K",
                symbol: recorder.isActive ? "waveform" : "mic.fill"
            )
            .padding(8)
        }
    }

    private var workspaceModePicker: some View {
        SignalSegmentedControl(
            values: AudioRecorderWorkspaceMode.allCases.map { ($0, $0.rawValue) },
            selection: $workspaceMode
        )
        .disabled(recorder.isBusy)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 18)
                .onEnded { value in
                    guard abs(value.predictedEndTranslation.width) > abs(value.predictedEndTranslation.height),
                          abs(value.predictedEndTranslation.width) > 44 else { return }
                    let destination: AudioRecorderWorkspaceMode = value.predictedEndTranslation.width < 0 ? .accompaniment : .voice
                    withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.34, dampingFraction: 0.86)) {
                        workspaceMode = destination
                    }
                }
        )
    }

    private var header: some View {
        SignalPageHeader(
            title: "把声音留下",
            detail: workspaceMode == .voice ? "捕捉清晰、稳定的人声" : "伴奏、歌词与人声同步录制",
            action: AnyView(
                SignalIconButton(symbol: "xmark", label: "关闭") { close() }
                    .disabled(recorder.isBusy && !recorder.isActive)
            )
        )
    }

    private func capturePanel(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 12) {
            HStack(spacing: 10) {
                Text("收音")
                    .font(.system(.caption, design: .rounded, weight: .black))
                    .frame(width: 34, alignment: .leading)
                HStack(spacing: 6) {
                    ForEach(AudioCaptureMode.allCases) { mode in
                        modeChip(mode.rawValue, selected: recorder.captureMode == mode) {
                            recorder.captureMode = mode
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if recorder.captureMode != .headphones {
                HStack(spacing: 10) {
                    Text("优化")
                        .font(.system(.caption, design: .rounded, weight: .black))
                        .frame(width: 34, alignment: .leading)
                    HStack(spacing: 6) {
                        ForEach(SpeakerProcessingStrength.allCases) { strength in
                            modeChip(
                                strength.rawValue,
                                selected: recorder.speakerProcessingStrength == strength
                            ) {
                                recorder.speakerProcessingStrength = strength
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                Text("扬声器回声消除 · 残响抑制 · 人声稳定")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(MonoTheme.muted(scheme))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .foregroundStyle(SignalColor.ink(scheme))
        .padding(compact ? 10 : 12)
        .background(SignalColor.surface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(SignalColor.rule(scheme), lineWidth: 1) }
    }

    private func accompanimentPanel(compact: Bool) -> some View {
        VStack(spacing: compact ? 9 : 12) {
            HStack(spacing: 10) {
                sessionMediaButton(
                    title: "伴奏",
                    detail: accompanimentName,
                    icon: recorder.hasAccompaniment ? "music.note" : "plus",
                    active: recorder.hasAccompaniment,
                    clearAction: recorder.clearAccompaniment
                ) {
                    isImporterPresented = true
                }

                sessionMediaButton(
                    title: "歌词",
                    detail: recorder.lyricsName ?? "LRC / QLRC / MLRC / TXT",
                    icon: recorder.hasLyrics ? "text.quote" : "plus",
                    active: recorder.hasLyrics,
                    clearAction: recorder.clearLyrics
                ) {
                    isLyricsImporterPresented = true
                }
            }

            if recorder.hasAccompaniment {
                VStack(spacing: compact ? 5 : 8) {
                    volumeControl(
                        title: "伴奏",
                        icon: "music.note",
                        value: $recorder.accompanimentVolume
                    )
                    volumeControl(
                        title: "人声",
                        icon: "mic.fill",
                        value: $recorder.vocalVolume
                    )
                    vocalSyncControl
                }
            }
        }
        .foregroundStyle(SignalColor.ink(scheme))
        .padding(compact ? 10 : 12)
        .background(SignalColor.surface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(SignalColor.rule(scheme), lineWidth: 1) }
    }

    private var vocalSyncControl: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Text("人声同步")
                    .font(.system(.caption, design: .rounded, weight: .black))
                Spacer()
                Text(String(format: "%+.0f ms", recorder.vocalSyncAdjustmentMilliseconds))
                    .font(.system(.caption2, design: .monospaced, weight: .black))
                    .foregroundStyle(MonoTheme.coral)
                Button("归零") { recorder.vocalSyncAdjustmentMilliseconds = 0 }
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .buttonStyle(.plain)
                    .disabled(abs(recorder.vocalSyncAdjustmentMilliseconds) < 1 || recorder.isBusy)
            }
            Slider(
                value: $recorder.vocalSyncAdjustmentMilliseconds,
                in: -500...500,
                step: 10
            )
            .tint(MonoTheme.coral)
            .disabled(recorder.isBusy)
            HStack {
                Text("人声延后")
                Spacer()
                Text("自动 \(Int(recorder.automaticSyncCompensationMilliseconds.rounded())) ms")
                Spacer()
                Text("人声提前")
            }
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(MonoTheme.muted(scheme))
        }
        .padding(.top, 3)
    }

    private func sessionMediaButton(
        title: String,
        detail: String,
        icon: String,
        active: Bool,
        clearAction: @escaping () -> Void,
        action: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            Button(action: action) {
                HStack(spacing: 9) {
                    MonoIcon(icon, size: 15, weight: 2.1)
                        .frame(width: 32, height: 32)
                        .background(active ? MonoTheme.coral : MonoTheme.ink(scheme))
                        .foregroundStyle(MonoTheme.background(scheme))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(.caption, design: .rounded, weight: .black))
                        Text(detail)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(MonoTheme.muted(scheme))
                            .lineLimit(1)
                    }
                    Spacer(minLength: active ? 18 : 0)
                }
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(MonoTheme.background(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(recorder.isBusy)

            if active {
                Button(action: clearAction) {
                    MonoIcon("xmark", size: 10, weight: 2.1)
                        .frame(width: 24, height: 24)
                        .foregroundStyle(MonoTheme.muted(scheme))
                }
                .buttonStyle(.plain)
                .disabled(recorder.isBusy)
                .accessibilityLabel("移除\(title)")
            }
        }
    }

    private func modeChip(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .black))
                .multilineTextAlignment(.center)
                .foregroundStyle(selected ? SignalColor.acid : MonoTheme.ink(scheme))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(selected ? SignalColor.stage : MonoTheme.background(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(recorder.isBusy)
    }

    private func volumeControl(
        title: String,
        icon: String,
        value: Binding<Double>
    ) -> some View {
        HStack(spacing: 10) {
            MonoIcon(icon, size: 14, weight: 2)
                .frame(width: 18)
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .frame(width: 30, alignment: .leading)
            Slider(value: value, in: 0...1)
                .tint(MonoTheme.coral)
        }
        .disabled(recorder.isBusy)
    }

    private var accompanimentName: String {
        recorder.accompanimentName ?? "选择音频文件"
    }

    private func meter(compact: Bool) -> some View {
        let meterHeight: CGFloat = compact
            ? 70
            : (workspaceMode == .voice ? 138 : 92)
        return HStack(alignment: .center, spacing: 3) {
            ForEach(Array(recorder.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(recorder.isActive ? MonoTheme.coral : MonoTheme.muted(scheme).opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(5, CGFloat(level) * meterHeight))
            }
        }
        .frame(height: meterHeight)
        .padding(.horizontal, 12)
        .accessibilityHidden(true)
    }

    private var lyricStage: some View {
        HStack(spacing: 10) {
            Button { isLyricsPresented = true } label: {
                VStack(spacing: 5) {
                    if let current = recorder.currentLyric {
                        Text(current.text)
                            .font(.system(.headline, design: .rounded, weight: .black))
                            .foregroundStyle(.white)
                            .id(current.id)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else if recorder.lyricLines.allSatisfy({ $0.time == nil }) {
                        Text(recorder.lyricLines.first?.text ?? "歌词")
                            .font(.system(.headline, design: .rounded, weight: .black))
                            .foregroundStyle(.white)
                    } else {
                        Text("准备")
                            .font(.system(.headline, design: .rounded, weight: .black))
                            .foregroundStyle(.white)
                    }

                    Text(nextLyricText)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.44))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看全部歌词")

            if recorder.lyricLines.contains(where: { $0.time != nil }) {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        lyricOffsetButton("−") { recorder.lyricOffset -= 0.5 }
                        lyricOffsetButton("+") { recorder.lyricOffset += 0.5 }
                    }
                    Button {
                        recorder.lyricOffset = 0
                    } label: {
                        Text(String(format: "%+.1fs", recorder.lyricOffset))
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    .buttonStyle(.plain)
                    .disabled(abs(recorder.lyricOffset) < 0.01)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: recorder.currentLyricIndex)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 14)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height),
                          abs(value.translation.width) > 28 else { return }
                    let step = value.translation.width > 0 ? 0.1 : -0.1
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                        recorder.lyricOffset = min(10, max(-10, recorder.lyricOffset + step))
                    }
                }
        )
        .sensoryFeedback(.selection, trigger: Int((recorder.lyricOffset * 10).rounded()))
    }

    private func lyricOffsetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body, design: .rounded, weight: .black))
                .frame(width: 28, height: 28)
                .foregroundStyle(.white)
                .background(SignalColor.stageRaised)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var nextLyricText: String {
        if recorder.lyricLines.allSatisfy({ $0.time == nil }) {
            return recorder.lyricLines.dropFirst().first?.text ?? "点击查看全部"
        }
        return recorder.nextLyric?.text ?? "—"
    }

    private var lyricContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .utf8PlainText]
        for fileExtension in LyricDocumentCodec.supportedFileExtensions where fileExtension != "txt" {
            if let type = UTType(filenameExtension: fileExtension), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch recorder.state {
        case .idle: Text(idleStateText)
        case .recording: Text("录制中")
        case .paused: Text("已暂停")
        case .processing: Text("优化人声中")
        case .mixing: Text("混音中")
        case .failed(let error): Text(error)
        }
    }

    private var idleStateText: String {
        switch recorder.captureMode {
        case .automatic: "自动路由  ·  48 KHZ"
        case .speaker: "回声消除  ·  48 KHZ"
        case .headphones: "原声收音  ·  48 KHZ"
        }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button { recorder.togglePause() } label: {
                Image(systemName: recorder.state == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 52, height: 52)
                    .foregroundStyle(.white)
                    .background(SignalColor.stageRaised)
                    .clipShape(Circle())
            }
            .disabled(!recorder.isActive)

            Button {
                if recorder.isActive { finish() }
                else {
                    let includeSessionMedia = workspaceMode == .accompaniment
                    Task {
                        await recorder.start(includeSessionMedia: includeSessionMedia)
                    }
                }
            } label: {
                ZStack {
                    Circle().fill(Color.white.opacity(0.12)).frame(width: 92, height: 92)
                    Circle().stroke(Color.white.opacity(0.58), lineWidth: 2).frame(width: 78, height: 78)
                    if recorder.isBusy && !recorder.isActive {
                        ProgressView()
                            .tint(.white)
                    } else {
                        RoundedRectangle(
                            cornerRadius: recorder.isActive ? 8 : 31,
                            style: .continuous
                        )
                        .fill(SignalColor.coral)
                        .frame(width: recorder.isActive ? 42 : 62, height: recorder.isActive ? 42 : 62)
                    }
                }
            }
            .buttonStyle(MonoSpringPressStyle())
            .disabled(recorder.isBusy && !recorder.isActive)
            .accessibilityLabel(recorder.isActive ? "停止录音" : "开始录音")
            .animation(.spring(response: 0.34, dampingFraction: 0.78), value: recorder.isActive)

            Color.clear.frame(width: 52, height: 52)
        }
        .foregroundStyle(.white)
    }

    private func finish() {
        Task {
            guard await recorder.stop() != nil else { return }
            await library.reload()
            show("已保存")
        }
    }

    private func close() {
        Task {
            if recorder.isActive {
                _ = await recorder.stop()
                await library.reload()
            }
            dismiss()
        }
    }

    private func importAccompaniment(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try recorder.importAccompaniment(from: url)
        } catch {
            show(error.localizedDescription)
        }
    }

    private func importLyrics(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try recorder.importLyrics(from: url)
            show("歌词已导入")
        } catch {
            show(error.localizedDescription)
        }
    }

    private func show(_ text: String) {
        withAnimation(.easeOut(duration: 0.18)) { message = text }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.18)) { message = nil }
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

private struct LyricsReader: View {
    let lines: [LyricLine]
    let currentIndex: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 22) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                Text(timeText(line.time))
                                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                                    .foregroundStyle(SignalColor.secondary(scheme))
                                    .frame(width: 42, alignment: .trailing)
                                Text(line.text)
                                    .font(.system(
                                        index == currentIndex ? .title3 : .body,
                                        design: .rounded,
                                        weight: index == currentIndex ? .black : .semibold
                                    ))
                                    .foregroundStyle(index == currentIndex ? SignalColor.coral : SignalColor.ink(scheme).opacity(0.72))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
                }
                .onChange(of: currentIndex) { _, index in
                    guard let index else { return }
                    withAnimation(.easeOut(duration: 0.24)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
                .onAppear {
                    guard let currentIndex else { return }
                    proxy.scrollTo(currentIndex, anchor: .center)
                }
            }
            .background(SignalColor.canvas(scheme).ignoresSafeArea())
            .navigationTitle("歌词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(.body, design: .rounded, weight: .black))
                        .foregroundStyle(SignalColor.coral)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func timeText(_ time: TimeInterval?) -> String {
        guard let time else { return "" }
        let seconds = max(0, Int(time))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
