import SwiftUI
import UniformTypeIdentifiers

struct PearlAudioRecorderView: View {
    private enum RecordingMode: String, CaseIterable, Identifiable {
        case voice = "纯人声"
        case mix = "混音"

        var id: String { rawValue }

        var accessibilityHint: String {
            switch self {
            case .voice: "只录制麦克风声音"
            case .mix: "录制人声并加入已选择的伴奏与歌词"
            }
        }
    }

    private struct RecorderNotice: Identifiable {
        let id = UUID()
        let message: String
        let tone: PearlInlineNotice.Tone
    }

    @StateObject private var recorder = AudioRecordingService()
    @State private var recordingMode: RecordingMode = .voice
    @State private var importingAccompaniment = false
    @State private var importingLyrics = false
    @State private var showingLyrics = false
    @State private var showingInputSettings = false
    @State private var savedURL: URL?
    @State private var exportItem: PearlExportItem?
    @State private var starting = false
    @State private var finishing = false
    @State private var notice: RecorderNotice?

    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 78

    var body: some View {
        VStack(spacing: 0) {
            PearlSecondaryHeader(title: "录音", onBack: close) {
                PearlIconButton(title: "录音设置", glyph: .settings) { showingInputSettings = true }
            }
            GeometryReader { container in
                PearlPage(maxWidth: 720) {
                    VStack(spacing: 24) {
                        modeSelector
                        VStack(alignment: .leading, spacing: 18) {
                            ViewThatFits(in: .horizontal) {
                                recordingClock(size: min(timerSize, 112))
                                recordingClock(size: 54)
                                recordingClock(size: 38)
                            }
                            HStack(spacing: 9) {
                                Circle().fill(statusColor).frame(width: 9, height: 9)
                                Text(statusTitle).font(.title3.weight(.semibold))
                                Spacer(minLength: 0)
                                if recorder.hasLyrics {
                                    PearlIconButton(title: "查看歌词", glyph: .document) { showingLyrics = true }
                                }
                            }
                            PearlHairline()
                            PearlWaveform(samples: recorder.isActive ? recorder.levels : [])
                                .frame(height: min(180, max(90, container.size.height * 0.22)))
                                .accessibilityIdentifier("pearl.audio.waveform")
                            PearlHairline()
                        }
                        HStack {
                            PearlGlyph(.microphone, size: 20)
                            Text(routeSummary).font(.subheadline)
                            Spacer()
                        }.foregroundStyle(PearlColor.secondary(scheme)).frame(minHeight: 36)
                        transport
                        if recordingMode == .mix, recorder.hasLyrics { lyricPreview }
                        noticeArea
                        if let savedURL {
                            HStack(spacing: 12) {
                                Button { exportItem = PearlExportItem(url: savedURL) } label: {
                                    Label { Text("导出录音") } icon: { PearlGlyph(.export, size: 18) }
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                }
                                ShareLink(item: savedURL) { Text("分享").frame(minWidth: 60, minHeight: 48) }
                            }.buttonStyle(PearlPressStyle())
                        }
                        if recordingMode == .mix { mixRows }
                    }
                }
            }
        }
        .background(PearlBackdrop()).interactiveDismissDisabled(recorder.isActive || starting || finishing || isPostProcessing)
        .fileImporter(isPresented: $importingAccompaniment, allowedContentTypes: [.audio], allowsMultipleSelection: false, onCompletion: receiveAccompaniment)
        .fileImporter(isPresented: $importingLyrics, allowedContentTypes: lyricTypes, allowsMultipleSelection: false, onCompletion: receiveLyrics)
        .sheet(isPresented: $showingLyrics) {
            PearlLyricReadingView(title: recorder.lyricsName ?? "歌词", lines: recorder.lyricLines.enumerated().map { PearlLyricReadingLine(id: $0.offset, time: $0.element.time, text: $0.element.text) }, currentIndex: recorder.currentLyricIndex)
        }
        .sheet(isPresented: $showingInputSettings) {
            PearlSecondaryLayout(title: "录音设置") { PearlPage { inputRows } }
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(item: $exportItem) { PearlFileExporter(url: $0.url) }
        .sensoryFeedback(.selection, trigger: recordingMode)
        .sensoryFeedback(.impact(weight: .medium), trigger: recorder.state)

    }

    private func recordingClock(size: CGFloat) -> some View {
        Text(timecode(recorder.elapsed))
            .font(.system(size: size, weight: .bold)).monospacedDigit().tracking(-2)
            .foregroundStyle(PearlColor.display(scheme)).fixedSize()
            .accessibilityLabel(spokenDuration(recorder.elapsed))
    }

    private var transport: some View {
        HStack(alignment: .top, spacing: 45) {
            VStack(spacing: 10) {
                Button { recorder.togglePause() } label: {
                    PearlGlyph(recorder.state == .paused ? .play : .pause, size: 28)
                        .foregroundStyle(PearlColor.ink(scheme)).frame(width: 82, height: 82)
                        .background(PearlColor.elevated(scheme), in: Circle())
                }.buttonStyle(PearlPressStyle()).disabled(!canTogglePause)
                    .accessibilityLabel(recorder.state == .paused ? "继续" : "暂停")
                    .accessibilityIdentifier("pearl.audio.pause")
                Text(recorder.state == .paused ? "继续" : "暂停").font(.subheadline)
            }
            VStack(spacing: 10) {
                Button(action: primaryAction) {
                    ZStack {
                        Circle().fill(PearlColor.action(scheme))
                        if starting || finishing || isPostProcessing { ProgressView().tint(PearlColor.onAccent(scheme)) }
                        else if recorder.isActive { RoundedRectangle(cornerRadius: 5).fill(PearlColor.onAccent(scheme)).frame(width: 25, height: 25) }
                        else { Circle().strokeBorder(PearlColor.onAccent(scheme), lineWidth: 2).frame(width: 33, height: 33) }
                    }.frame(width: 82, height: 82)
                }.buttonStyle(PearlPressStyle()).disabled(starting || finishing || isPostProcessing)
                    .accessibilityLabel(primaryAccessibilityLabel).accessibilityIdentifier("pearl.audio.record")
                Text(recorder.isActive ? "完成录音" : starting ? "准备中" : finishing || isPostProcessing ? "保存中" : "开始录音")
                    .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 8)
    }

    private var lyricPreview: some View {
        Button { showingLyrics = true } label: {
            Text(recorder.currentLyric?.text ?? "歌词已就绪").font(.title3.weight(.medium))
                .foregroundStyle(PearlColor.accent(scheme)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 52)
        }.buttonStyle(PearlPressStyle()).accessibilityLabel("查看歌词")
    }

    private var modeSelector: some View {
        Picker("录音模式", selection: $recordingMode) {
            ForEach(RecordingMode.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented).disabled(recorder.isBusy || starting || finishing)
    }

    @ViewBuilder private var noticeArea: some View {
        if let noticeMessage {
            PearlInlineNotice(message: noticeMessage.message, tone: noticeMessage.tone)
                .id(noticeMessage.id)
                .transition(.opacity)
                .accessibilityIdentifier("pearl.audio.notice")
        }
    }

    private var inputRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            PearlSectionLabel("输入")
                .padding(.bottom, 7)

            Menu {
                ForEach(AudioCaptureMode.allCases) { mode in
                    Button(mode.rawValue) { recorder.captureMode = mode }
                }
            } label: {
                PearlPlainRow("收音路径", accessibilityValue: recorder.captureMode.rawValue) {
                    rowValue(recorder.captureMode.rawValue)
                }
            }
            .buttonStyle(PearlPressStyle())
            .disabled(recorder.isBusy || starting || finishing)
            .accessibilityIdentifier("pearl.audio.captureMode")

            PearlHairline()

            if recorder.captureMode != .headphones {
                Menu {
                    ForEach(SpeakerProcessingStrength.allCases) { strength in
                        Button(strength.rawValue) { recorder.speakerProcessingStrength = strength }
                    }
                } label: {
                    PearlPlainRow(
                        "扬声器人声优化",
                        accessibilityValue: recorder.speakerProcessingStrength.rawValue
                    ) {
                        rowValue(recorder.speakerProcessingStrength.rawValue)
                    }
                }
                .buttonStyle(PearlPressStyle())
                .disabled(recorder.isBusy || starting || finishing)
                .accessibilityIdentifier("pearl.audio.speakerProcessing")

                PearlHairline()
            }

            PearlPlainRow("录制规格", accessibilityValue: "48 千赫兹") {
                Text("48 kHz")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(PearlColor.tertiary(scheme))
            }
        }
    }

    private var mixRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            PearlSectionLabel("混音素材")
                .padding(.bottom, 7)

            mediaRow(
                title: "伴奏",
                detail: recorder.accompanimentName ?? "选择音频文件",
                loaded: recorder.hasAccompaniment,
                importIdentifier: "pearl.audio.accompaniment.import",
                clearIdentifier: "pearl.audio.accompaniment.clear",
                importAction: { importingAccompaniment = true },
                clearAction: recorder.clearAccompaniment
            )

            PearlHairline()

            mediaRow(
                title: "歌词",
                detail: recorder.lyricsName ?? "LRC、QLRC、MLRC 或 TXT",
                loaded: recorder.hasLyrics,
                importIdentifier: "pearl.audio.lyrics.import",
                clearIdentifier: "pearl.audio.lyrics.clear",
                importAction: { importingLyrics = true },
                clearAction: recorder.clearLyrics
            )

            if recorder.hasAccompaniment {
                PearlHairline()
                levelRow(
                    title: "伴奏音量",
                    value: $recorder.accompanimentVolume,
                    identifier: "pearl.audio.accompaniment.volume"
                )
                PearlHairline()
                levelRow(
                    title: "人声音量",
                    value: $recorder.vocalVolume,
                    identifier: "pearl.audio.vocal.volume"
                )
                PearlHairline()
                syncRow
            }
        }
        .disabled(recorder.isBusy || starting || finishing)
    }

    private func mediaRow(
        title: String,
        detail: String,
        loaded: Bool,
        importIdentifier: String,
        clearIdentifier: String,
        importAction: @escaping () -> Void,
        clearAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Button(action: importAction) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.body)
                            .foregroundStyle(PearlColor.ink(scheme))
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(PearlColor.tertiary(scheme))
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    }
                    Spacer(minLength: 8)
                    Text(loaded ? "更换" : "导入")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PearlColor.accent(scheme))
                }
                .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 70 : 58)
                .contentShape(Rectangle())
            }
            .buttonStyle(PearlPressStyle())
            .accessibilityLabel("\(title)，\(detail)，\(loaded ? "更换" : "导入")")
            .accessibilityIdentifier(importIdentifier)

            if loaded {
                Button(action: clearAction) {
                    Text("移除")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PearlColor.danger(scheme))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PearlPressStyle())
                .accessibilityLabel("移除\(title)")
                .accessibilityIdentifier(clearIdentifier)
            }
        }
    }

    private func levelRow(
        title: String,
        value: Binding<Double>,
        identifier: String
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(PearlColor.ink(scheme))
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(PearlColor.tertiary(scheme))
            }
            Slider(value: value, in: 0...1)
                .tint(PearlColor.accent(scheme))
                .frame(minHeight: 44)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int((value.wrappedValue * 100).rounded())) 百分比")
                .accessibilityIdentifier(identifier)
        }
        .padding(.vertical, 10)
    }

    private var syncRow: some View {
        VStack(spacing: 8) {
            HStack {
                Text("人声同步")
                    .font(.subheadline)
                    .foregroundStyle(PearlColor.ink(scheme))
                Spacer()
                Text(String(format: "%+.0f ms", recorder.vocalSyncAdjustmentMilliseconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(PearlColor.tertiary(scheme))
            }
            Slider(
                value: $recorder.vocalSyncAdjustmentMilliseconds,
                in: -500...500,
                step: 10
            )
            .tint(PearlColor.accent(scheme))
            .frame(minHeight: 44)
            .accessibilityLabel("人声同步调整")
            .accessibilityValue(String(format: "%+.0f 毫秒", recorder.vocalSyncAdjustmentMilliseconds))
            .accessibilityIdentifier("pearl.audio.vocal.sync")
        }
        .padding(.vertical, 10)
    }

    private func rowValue(_ value: String) -> some View {
        Text(value)
            .font(.subheadline)
            .foregroundStyle(PearlColor.tertiary(scheme))
    }

    private var noticeMessage: RecorderNotice? {
        if case let .failed(message) = recorder.state {
            return RecorderNotice(message: message, tone: .error)
        }
        return notice
    }

    private var statusTitle: String {
        switch recorder.state {
        case .idle: "准备录音"
        case .recording: "正在录音"
        case .paused: "已暂停"
        case .processing: "正在优化"
        case .mixing: "正在混音"
        case .failed: "需要处理"
        }
    }

    private var statusColor: Color {
        switch recorder.state {
        case .recording, .failed: PearlColor.coral
        case .paused, .processing, .mixing: Color.orange
        case .idle: PearlColor.accent(scheme)
        }
    }

    private var routeSummary: String {
        let route = recorder.activeCaptureMode?.rawValue ?? recorder.captureMode.rawValue
        return "48 kHz · \(route)"
    }

    private var canTogglePause: Bool {
        recorder.state == .recording || recorder.state == .paused
    }

    private var isPostProcessing: Bool {
        recorder.state == .processing || recorder.state == .mixing
    }

    private var primaryAccessibilityLabel: String {
        if starting { return "正在准备录音" }
        if finishing || isPostProcessing { return "正在保存录音" }
        return recorder.isActive ? "停止并保存录音" : "开始录音"
    }

    private var lyricTypes: [UTType] {
        var types: [UTType] = [.plainText, .utf8PlainText]
        for fileExtension in LyricDocumentCodec.supportedFileExtensions where fileExtension != "txt" {
            if let type = UTType(filenameExtension: fileExtension), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }

    private func primaryAction() {
        if recorder.isActive {
            Task { _ = await finishRecording() }
        } else {
            Task { await startRecording() }
        }
    }

    @MainActor private func startRecording() async {
        guard !starting, !finishing, !recorder.isBusy else { return }
        starting = true
        notice = nil
        await recorder.start(includeSessionMedia: recordingMode == .mix)
        starting = false
    }

    @MainActor @discardableResult private func finishRecording() async -> Bool {
        guard !finishing, recorder.isActive else { return false }
        finishing = true
        defer { finishing = false }

        guard let file = await recorder.stop() else {
            showNotice("没有生成可保存的录音，请检查麦克风后重试。", tone: .error)
            return false
        }

        savedURL = file
        await library.reload()
        if case let .failed(message) = recorder.state {
            showNotice(message, tone: .warning)
        } else {
            showNotice("录音已保存到素材。", tone: .info)
        }
        return true
    }

    private func close() {
        guard !starting, !finishing, !isPostProcessing else { return }
        guard recorder.isActive else {
            dismiss()
            return
        }

        Task {
            if await finishRecording() { dismiss() }
        }
    }

    private func receiveAccompaniment(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try recorder.importAccompaniment(from: url)
            showNotice("伴奏已添加。", tone: .info)
        } catch {
            showNotice(error.localizedDescription, tone: .error)
        }
    }

    private func receiveLyrics(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try recorder.importLyrics(from: url)
            showNotice("已读取 \(recorder.lyricLines.count) 行歌词。", tone: .info)
        } catch {
            showNotice(error.localizedDescription, tone: .error)
        }
    }

    private func showNotice(_ message: String, tone: PearlInlineNotice.Tone) {
        let next = RecorderNotice(message: message, tone: tone)
        if reduceMotion {
            notice = next
        } else {
            withAnimation(.easeOut(duration: 0.16)) { notice = next }
        }

    }

    private func timecode(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func spokenDuration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        return "\(value / 60) 分 \(value % 60) 秒"
    }
}
