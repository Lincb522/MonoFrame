import SwiftUI
import UniformTypeIdentifiers

struct CanvasAudioRecorderView: View {
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
        let tone: CanvasInlineNotice.Tone
    }

    @StateObject private var recorder = AudioRecordingService()
    @State private var recordingMode: RecordingMode = .voice
    @State private var importingAccompaniment = false
    @State private var importingLyrics = false
    @State private var showingLyrics = false
    @State private var starting = false
    @State private var finishing = false
    @State private var notice: RecorderNotice?

    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 52

    var body: some View {
        CanvasPage(horizontalPadding: 22, topPadding: 0) {
            VStack(spacing: 0) {
                recordingStage
                modeSelector.padding(.top, 38)
                noticeArea.padding(.top, noticeMessage == nil ? 0 : 16)
                inputRows.padding(.top, 24)

                if recordingMode == .mix {
                    mixRows
                        .padding(.top, 28)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .navigationTitle("录音")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(recorder.isActive || finishing || isPostProcessing)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成", action: close)
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(starting || finishing || isPostProcessing)
                    .accessibilityIdentifier("canvas.audio.close")
            }
        }
        .fileImporter(
            isPresented: $importingAccompaniment,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false,
            onCompletion: receiveAccompaniment
        )
        .fileImporter(
            isPresented: $importingLyrics,
            allowedContentTypes: lyricTypes,
            allowsMultipleSelection: false,
            onCompletion: receiveLyrics
        )
        .sheet(isPresented: $showingLyrics) {
            CanvasLyricsReader(
                title: recorder.lyricsName,
                lines: recorder.lyricLines,
                currentIndex: recorder.currentLyricIndex
            )
        }
        .sensoryFeedback(.selection, trigger: recordingMode)
        .sensoryFeedback(.impact(weight: .medium), trigger: recorder.state)
        .accessibilityIdentifier("canvas.audio.page")
    }

    private var recordingStage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CanvasColor.secondary(scheme))
                Spacer(minLength: 12)
                Text(routeSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CanvasColor.tertiary(scheme))
                    .lineLimit(1)
            }
            .padding(.top, 34)

            Text(timecode(recorder.elapsed))
                .font(.system(size: timerSize, weight: .regular, design: .rounded))
                .monospacedDigit()
                .tracking(-1.6)
                .foregroundStyle(CanvasColor.ink(scheme))
                .contentTransition(reduceMotion ? .identity : .numericText())
                .padding(.top, 27)
                .accessibilityLabel("录音时长，\(spokenDuration(recorder.elapsed))")
                .accessibilityIdentifier("canvas.audio.elapsed")

            CanvasAudioLevelWaveform(
                samples: recorder.levels,
                active: recorder.state == .recording
            )
            .frame(height: 48)
            .padding(.horizontal, 6)
            .padding(.top, 34)
            .accessibilityIdentifier("canvas.audio.waveform")

            if recordingMode == .mix, recorder.hasLyrics {
                lyricPreview.padding(.top, 25)
            }

            transport.padding(.top, recorder.hasLyrics && recordingMode == .mix ? 28 : 48)
        }
        .accessibilityElement(children: .contain)
    }

    private var transport: some View {
        CanvasGlassSurface(cornerRadius: 34) {
            HStack(spacing: 0) {
                transportButton(
                    title: recorder.state == .paused ? "继续" : "暂停",
                    mark: recorder.state == .paused ? .play : .pause,
                    enabled: canTogglePause,
                    identifier: "canvas.audio.pause",
                    action: recorder.togglePause
                )

                Spacer(minLength: 8)

                Button(action: primaryAction) {
                    ZStack {
                        Circle()
                            .fill(CanvasColor.background(scheme))
                            .frame(width: 64, height: 64)
                        Circle()
                            .stroke(CanvasColor.coral.opacity(0.30), lineWidth: 2)
                            .frame(width: 58, height: 58)

                        if starting || finishing || isPostProcessing {
                            ProgressView()
                                .tint(CanvasColor.coral)
                        } else if recorder.isActive {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(CanvasColor.coral)
                                .frame(width: 27, height: 27)
                        } else {
                            Circle()
                                .fill(CanvasColor.coral)
                                .frame(width: 49, height: 49)
                        }
                    }
                    .frame(width: 76, height: 76)
                    .contentShape(Circle())
                }
                .buttonStyle(CanvasPressStyle())
                .disabled(starting || finishing || isPostProcessing)
                .accessibilityLabel(primaryAccessibilityLabel)
                .accessibilityHint(recorder.isActive ? "停止后自动保存到作品库" : recordingMode.accessibilityHint)
                .accessibilityIdentifier("canvas.audio.record")

                Spacer(minLength: 8)

                transportButton(
                    title: "歌词",
                    mark: .lyrics,
                    enabled: recorder.hasLyrics,
                    identifier: "canvas.audio.lyrics",
                    action: { showingLyrics = true }
                )
            }
            .padding(.horizontal, 10)
            .frame(width: 294, height: 72)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("canvas.audio.transport")
    }

    private func transportButton(
        title: String,
        mark: CanvasTransportMark.Kind,
        enabled: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                CanvasTransportMark(kind: mark)
                    .frame(width: 21, height: 21)
                Text(title)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(CanvasColor.secondary(scheme))
            .frame(width: 62)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(CanvasPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.34)
        .accessibilityIdentifier(identifier)
    }

    private var lyricPreview: some View {
        Button { showingLyrics = true } label: {
            VStack(spacing: 5) {
                Text(recorder.currentLyric?.text ?? "歌词已就绪")
                    .font(.body.weight(.medium))
                    .foregroundStyle(CanvasColor.ink(scheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(recorder.nextLyric?.text ?? "轻触查看全部歌词")
                    .font(.caption)
                    .foregroundStyle(CanvasColor.tertiary(scheme))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(CanvasPressStyle())
        .accessibilityLabel("打开歌词，当前歌词：\(recorder.currentLyric?.text ?? "尚未开始")")
        .accessibilityIdentifier("canvas.audio.lyrics.preview")
    }

    private var modeSelector: some View {
        HStack(spacing: 24) {
            ForEach(RecordingMode.allCases) { option in
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        recordingMode = option
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(option.rawValue)
                            .font(.body.weight(recordingMode == option ? .semibold : .regular))
                            .foregroundStyle(
                                recordingMode == option
                                    ? CanvasColor.ink(scheme)
                                    : CanvasColor.secondary(scheme)
                            )
                        Rectangle()
                            .fill(recordingMode == option ? CanvasColor.accent(scheme) : .clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(CanvasPressStyle())
                .disabled(recorder.isBusy || starting || finishing)
                .accessibilityLabel(option.rawValue)
                .accessibilityHint(option.accessibilityHint)
                .accessibilityAddTraits(recordingMode == option ? .isSelected : [])
                .accessibilityIdentifier("canvas.audio.mode.\(option == .voice ? "voice" : "mix")")
            }
        }
        .overlay(alignment: .bottom) { CanvasHairline() }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: recordingMode)
    }

    @ViewBuilder private var noticeArea: some View {
        if let noticeMessage {
            CanvasInlineNotice(message: noticeMessage.message, tone: noticeMessage.tone)
                .id(noticeMessage.id)
                .transition(.opacity)
                .accessibilityIdentifier("canvas.audio.notice")
        }
    }

    private var inputRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            CanvasSectionLabel("输入")
                .padding(.bottom, 7)

            Menu {
                ForEach(AudioCaptureMode.allCases) { mode in
                    Button(mode.rawValue) { recorder.captureMode = mode }
                }
            } label: {
                CanvasPlainRow("收音路径", accessibilityValue: recorder.captureMode.rawValue) {
                    rowValue(recorder.captureMode.rawValue)
                }
            }
            .buttonStyle(CanvasPressStyle())
            .disabled(recorder.isBusy || starting || finishing)
            .accessibilityIdentifier("canvas.audio.captureMode")

            CanvasHairline()

            if recorder.captureMode != .headphones {
                Menu {
                    ForEach(SpeakerProcessingStrength.allCases) { strength in
                        Button(strength.rawValue) { recorder.speakerProcessingStrength = strength }
                    }
                } label: {
                    CanvasPlainRow(
                        "扬声器人声优化",
                        accessibilityValue: recorder.speakerProcessingStrength.rawValue
                    ) {
                        rowValue(recorder.speakerProcessingStrength.rawValue)
                    }
                }
                .buttonStyle(CanvasPressStyle())
                .disabled(recorder.isBusy || starting || finishing)
                .accessibilityIdentifier("canvas.audio.speakerProcessing")

                CanvasHairline()
            }

            CanvasPlainRow("录制规格", accessibilityValue: "48 千赫兹") {
                Text("48 kHz")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(CanvasColor.tertiary(scheme))
            }
        }
    }

    private var mixRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            CanvasSectionLabel("混音素材")
                .padding(.bottom, 7)

            mediaRow(
                title: "伴奏",
                detail: recorder.accompanimentName ?? "选择音频文件",
                loaded: recorder.hasAccompaniment,
                importIdentifier: "canvas.audio.accompaniment.import",
                clearIdentifier: "canvas.audio.accompaniment.clear",
                importAction: { importingAccompaniment = true },
                clearAction: recorder.clearAccompaniment
            )

            CanvasHairline()

            mediaRow(
                title: "歌词",
                detail: recorder.lyricsName ?? "LRC、QLRC、MLRC 或 TXT",
                loaded: recorder.hasLyrics,
                importIdentifier: "canvas.audio.lyrics.import",
                clearIdentifier: "canvas.audio.lyrics.clear",
                importAction: { importingLyrics = true },
                clearAction: recorder.clearLyrics
            )

            if recorder.hasAccompaniment {
                CanvasHairline()
                levelRow(
                    title: "伴奏音量",
                    value: $recorder.accompanimentVolume,
                    identifier: "canvas.audio.accompaniment.volume"
                )
                CanvasHairline()
                levelRow(
                    title: "人声音量",
                    value: $recorder.vocalVolume,
                    identifier: "canvas.audio.vocal.volume"
                )
                CanvasHairline()
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
                            .foregroundStyle(CanvasColor.ink(scheme))
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(CanvasColor.tertiary(scheme))
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    }
                    Spacer(minLength: 8)
                    Text(loaded ? "更换" : "导入")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(CanvasColor.accent(scheme))
                }
                .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 70 : 58)
                .contentShape(Rectangle())
            }
            .buttonStyle(CanvasPressStyle())
            .accessibilityLabel("\(title)，\(detail)，\(loaded ? "更换" : "导入")")
            .accessibilityIdentifier(importIdentifier)

            if loaded {
                Button(action: clearAction) {
                    Text("移除")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CanvasColor.danger(scheme))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CanvasPressStyle())
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
                    .foregroundStyle(CanvasColor.ink(scheme))
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CanvasColor.tertiary(scheme))
            }
            Slider(value: value, in: 0...1)
                .tint(CanvasColor.accent(scheme))
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
                    .foregroundStyle(CanvasColor.ink(scheme))
                Spacer()
                Text(String(format: "%+.0f ms", recorder.vocalSyncAdjustmentMilliseconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CanvasColor.tertiary(scheme))
            }
            Slider(
                value: $recorder.vocalSyncAdjustmentMilliseconds,
                in: -500...500,
                step: 10
            )
            .tint(CanvasColor.accent(scheme))
            .frame(minHeight: 44)
            .accessibilityLabel("人声同步调整")
            .accessibilityValue(String(format: "%+.0f 毫秒", recorder.vocalSyncAdjustmentMilliseconds))
            .accessibilityIdentifier("canvas.audio.vocal.sync")
        }
        .padding(.vertical, 10)
    }

    private func rowValue(_ value: String) -> some View {
        Text(value)
            .font(.subheadline)
            .foregroundStyle(CanvasColor.tertiary(scheme))
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
        case .recording, .failed: CanvasColor.coral
        case .paused, .processing, .mixing: Color.orange
        case .idle: CanvasColor.accent(scheme)
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

        guard await recorder.stop() != nil else {
            showNotice("没有生成可保存的录音，请检查麦克风后重试。", tone: .error)
            return false
        }

        await library.reload()
        if case let .failed(message) = recorder.state {
            showNotice(message, tone: .warning)
        } else {
            showNotice("录音已保存到作品库。", tone: .info)
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

    private func showNotice(_ message: String, tone: CanvasInlineNotice.Tone) {
        let next = RecorderNotice(message: message, tone: tone)
        if reduceMotion {
            notice = next
        } else {
            withAnimation(.easeOut(duration: 0.16)) { notice = next }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.2))
            guard notice?.id == next.id else { return }
            if reduceMotion {
                notice = nil
            } else {
                withAnimation(.easeOut(duration: 0.16)) { notice = nil }
            }
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

private struct CanvasAudioLevelWaveform: View {
    let samples: [Float]
    let active: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwiftUI.Canvas { context, size in
            let values = normalizedSamples
            let gap = size.width / CGFloat(max(values.count - 1, 1))
            let midY = size.height / 2

            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: midY))
            baseline.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(
                baseline,
                with: .color(CanvasColor.secondary(scheme).opacity(0.20)),
                style: StrokeStyle(lineWidth: 1, dash: [1.3, 2.7])
            )

            for (index, sample) in values.enumerated() {
                let amplitude = max(1.8, min(1, CGFloat(abs(sample))) * size.height * 0.46)
                let x = CGFloat(index) * gap
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: midY - amplitude))
                tick.addLine(to: CGPoint(x: x, y: midY + amplitude))
                let isLead = active && index == values.count - 1
                context.stroke(
                    tick,
                    with: .color(
                        isLead
                            ? CanvasColor.coral
                            : CanvasColor.secondary(scheme).opacity(active ? 0.58 : 0.34)
                    ),
                    style: StrokeStyle(lineWidth: index.isMultiple(of: 8) ? 1.35 : 0.85, lineCap: .round)
                )
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: samples)
        .accessibilityHidden(true)
    }

    private var normalizedSamples: [Float] {
        if samples.isEmpty { return Array(repeating: 0.08, count: 64) }
        if samples.count >= 64 { return Array(samples.suffix(64)) }
        return Array(repeating: 0.08, count: 64 - samples.count) + samples
    }
}

private struct CanvasTransportMark: View {
    enum Kind { case pause, play, lyrics }

    let kind: Kind

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            switch kind {
            case .pause:
                HStack(spacing: size * 0.20) {
                    Capsule().frame(width: size * 0.18, height: size * 0.68)
                    Capsule().frame(width: size * 0.18, height: size * 0.68)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .play:
                CanvasPlayMark()
                    .padding(size * 0.18)
            case .lyrics:
                VStack(alignment: .leading, spacing: size * 0.13) {
                    Capsule().frame(width: size * 0.78, height: 1.5)
                    Capsule().frame(width: size * 0.58, height: 1.5)
                    Capsule().frame(width: size * 0.70, height: 1.5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CanvasPlayMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct CanvasLyricsReader: View {
    let title: String?
    let lines: [LyricLine]
    let currentIndex: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackdrop()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                                lyricRow(line, index: index)
                                    .id(index)
                                if index < lines.count - 1 { CanvasHairline() }
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear { scrollToCurrent(using: proxy) }
                    .onChange(of: currentIndex) { _, _ in scrollToCurrent(using: proxy) }
                }
            }
            .navigationTitle(title ?? "歌词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("\(lines.count) 行")
                        .font(.caption)
                        .foregroundStyle(CanvasColor.tertiary(scheme))
                        .accessibilityHidden(true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("canvas.audio.lyrics.dismiss")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(CanvasColor.background(scheme))
        .accessibilityIdentifier("canvas.audio.lyrics.sheet")
    }

    private func lyricRow(_ line: LyricLine, index: Int) -> some View {
        let selected = index == currentIndex
        return HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(timestamp(line.time))
                .font(.caption.monospacedDigit())
                .foregroundStyle(selected ? CanvasColor.accent(scheme) : CanvasColor.tertiary(scheme))
                .frame(minWidth: 46, alignment: .trailing)
            Text(line.text)
                .font(selected ? .body.weight(.semibold) : .body)
                .foregroundStyle(CanvasColor.ink(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(timestamp(line.time))，\(line.text)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("canvas.audio.lyrics.line.\(line.id)")
    }

    private func scrollToCurrent(using proxy: ScrollViewProxy) {
        guard let currentIndex, lines.indices.contains(currentIndex) else { return }
        if reduceMotion {
            proxy.scrollTo(currentIndex, anchor: .center)
        } else {
            withAnimation(.easeOut(duration: 0.20)) {
                proxy.scrollTo(currentIndex, anchor: .center)
            }
        }
    }

    private func timestamp(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "—" }
        let value = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
