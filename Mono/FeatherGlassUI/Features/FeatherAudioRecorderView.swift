import SwiftUI
import UniformTypeIdentifiers

struct FeatherAudioRecorderView: View {
    private enum RecordingMode: String, CaseIterable, Identifiable {
        case voice = "纯人声"
        case session = "混音"

        var id: String { rawValue }

        var detail: String {
            switch self {
            case .voice: "只采集麦克风，适合旁白与口述"
            case .session: "同步播放伴奏，并可携带歌词"
            }
        }
    }

    private struct RecorderNotice: Identifiable {
        let id = UUID()
        let message: String
        let tone: FeatherInlineNotice.Tone
    }

    @StateObject private var recorder = AudioRecordingService()
    @State private var mode: RecordingMode = .voice
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
    @ScaledMetric(relativeTo: .largeTitle) private var timecodeSize: CGFloat = 48

    var body: some View {
        FeatherPage {
            VStack(spacing: 28) {
                recordingStage
                modeChooser
                noticeArea
                inputSection

                if mode == .session {
                    sessionSection
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .featherNavigationTitle("录音")
        .navigationBarBackButtonHidden(recorder.isActive || finishing)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成", action: close)
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(starting || finishing)
                    .accessibilityIdentifier("feather.audio.close")
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
            FeatherLyricsReader(
                title: recorder.lyricsName,
                lines: recorder.lyricLines,
                currentIndex: recorder.currentLyricIndex
            )
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: recorder.state)
        .accessibilityIdentifier("feather.audio.recorder")
    }

    private var recordingStage: some View {
        FeatherSurface(cornerRadius: 24) {
            VStack(spacing: 24) {
                HStack(spacing: 12) {
                    statusPill
                    Spacer(minLength: 12)
                    Text(routeSummary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(FeatherColor.secondary(scheme))
                        .lineLimit(1)
                }

                VStack(spacing: 13) {
                    Text(timecode(recorder.elapsed))
                        .font(.system(size: timecodeSize, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                        .tracking(-1.8)
                        .foregroundStyle(FeatherColor.ink(scheme))
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .accessibilityLabel("录音时长，\(spokenDuration(recorder.elapsed))")
                        .accessibilityIdentifier("feather.audio.elapsed")

                    FeatherRecorderWaveform(
                        samples: recorder.levels,
                        isLive: recorder.state == .recording
                    )
                    .frame(height: 70)
                    .accessibilityIdentifier("feather.audio.waveform")
                }

                if mode == .session, recorder.hasLyrics {
                    lyricPreview
                }

                transport
            }
            .padding(20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feather.audio.stage")
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusTitle)
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(FeatherColor.ink(scheme))
        .padding(.horizontal, 11)
        .frame(minHeight: 34)
        .background(
            statusColor.opacity(scheme == .dark ? 0.20 : 0.11),
            in: Capsule(style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feather.audio.status")
    }

    private var lyricPreview: some View {
        Button { showingLyrics = true } label: {
            HStack(spacing: 12) {
                FeatherIcon(name: "captions.bubble", size: 20)
                    .foregroundStyle(FeatherColor.accent(scheme))
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(recorder.currentLyric?.text ?? "歌词已就绪")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(FeatherColor.ink(scheme))
                        .lineLimit(1)
                    Text(recorder.nextLyric?.text ?? "轻触查看全部歌词")
                        .font(.caption)
                        .foregroundStyle(FeatherColor.secondary(scheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FeatherColor.secondary(scheme))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 62)
            .contentShape(Rectangle())
            .background(
                FeatherColor.lagoonWash(scheme),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
        }
        .buttonStyle(FeatherPressStyle())
        .accessibilityLabel("打开歌词，当前歌词：\(recorder.currentLyric?.text ?? "尚未开始")")
        .accessibilityIdentifier("feather.audio.lyrics.open")
    }

    private var transport: some View {
        FeatherGlassControl(cornerRadius: 34) {
            HStack(spacing: 8) {
                transportButton(
                    title: recorder.state == .paused ? "继续" : "暂停",
                    icon: recorder.state == .paused ? "play.fill" : "pause.fill",
                    identifier: "feather.audio.pause",
                    isEnabled: canTogglePause,
                    action: recorder.togglePause
                )

                Spacer(minLength: 0)

                Button { primaryAction() } label: {
                    ZStack {
                        Circle()
                            .fill(FeatherColor.coral)
                            .frame(width: 76, height: 76)

                        if starting || finishing || isPostProcessing {
                            ProgressView()
                                .tint(.white)
                                .controlSize(.regular)
                        } else if recorder.isActive {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(.white)
                                .frame(width: 28, height: 28)
                        } else {
                            Circle()
                                .fill(.white)
                                .frame(width: 36, height: 36)
                        }
                    }
                    .frame(width: 82, height: 82)
                    .contentShape(Circle())
                }
                .buttonStyle(FeatherPressStyle())
                .disabled(starting || finishing || isPostProcessing)
                .accessibilityLabel(primaryAccessibilityLabel)
                .accessibilityHint(recorder.isActive ? "停止后会自动保存到作品库" : mode.detail)
                .accessibilityIdentifier("feather.audio.record")

                Spacer(minLength: 0)

                transportButton(
                    title: "歌词",
                    icon: "captions.bubble",
                    identifier: "feather.audio.lyrics",
                    isEnabled: recorder.hasLyrics,
                    action: { showingLyrics = true }
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
    }

    private func transportButton(
        title: String,
        icon: String,
        identifier: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                FeatherIcon(name: icon, size: 20)
                Text(title).font(.caption.weight(.medium))
            }
            .foregroundStyle(FeatherColor.ink(scheme))
            .frame(width: 68)
            .padding(.vertical, 8)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(FeatherPressStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .accessibilityIdentifier(identifier)
    }

    private var modeChooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeatherSectionHeader("录制方式", detail: mode.detail)
            Picker("录制方式", selection: $mode) {
                ForEach(RecordingMode.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .disabled(recorder.isBusy || starting || finishing)
            .accessibilityIdentifier("feather.audio.mode")
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: mode)
    }

    @ViewBuilder private var noticeArea: some View {
        if case let .failed(message) = recorder.state {
            FeatherInlineNotice(message: message, tone: .error)
                .accessibilityIdentifier("feather.audio.error")
        } else if let notice {
            FeatherInlineNotice(message: notice.message, tone: notice.tone)
                .id(notice.id)
                .transition(.opacity)
                .accessibilityIdentifier("feather.audio.notice")
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatherSectionHeader("麦克风输入", detail: "48 kHz")
            FeatherSurface {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("监听路径")
                            .font(.body.weight(.medium))
                        Picker("监听路径", selection: $recorder.captureMode) {
                            ForEach(AudioCaptureMode.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("feather.audio.captureMode")
                    }

                    if recorder.captureMode != .headphones {
                        FeatherRule()
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text("扬声器人声优化")
                                    .font(.body.weight(.medium))
                                Spacer()
                                Text(recorder.speakerProcessingStrength.rawValue)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(FeatherColor.secondary(scheme))
                            }
                            Picker("扬声器人声优化", selection: $recorder.speakerProcessingStrength) {
                                ForEach(SpeakerProcessingStrength.allCases) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("feather.audio.speakerProcessing")
                        }
                    }
                }
                .foregroundStyle(FeatherColor.ink(scheme))
                .padding(16)
            }
            .disabled(recorder.isBusy || starting || finishing)
        }
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatherSectionHeader("混音素材", detail: sessionSummary)
            FeatherSurface {
                VStack(spacing: 0) {
                    mediaRow(
                        title: "伴奏",
                        detail: recorder.accompanimentName ?? "选择音频文件",
                        icon: "music.note",
                        isLoaded: recorder.hasAccompaniment,
                        importIdentifier: "feather.audio.accompaniment.import",
                        clearIdentifier: "feather.audio.accompaniment.clear",
                        importAction: { importingAccompaniment = true },
                        clearAction: recorder.clearAccompaniment
                    )

                    FeatherRule().padding(.leading, 64)

                    mediaRow(
                        title: "歌词",
                        detail: recorder.lyricsName ?? "LRC、QLRC 或 TXT",
                        icon: "document",
                        isLoaded: recorder.hasLyrics,
                        importIdentifier: "feather.audio.lyrics.import",
                        clearIdentifier: "feather.audio.lyrics.clear",
                        importAction: { importingLyrics = true },
                        clearAction: recorder.clearLyrics
                    )

                    if recorder.hasAccompaniment {
                        FeatherRule().padding(.leading, 16)
                        VStack(spacing: 16) {
                            levelControl(
                                title: "伴奏音量",
                                value: $recorder.accompanimentVolume,
                                identifier: "feather.audio.accompaniment.volume"
                            )
                            levelControl(
                                title: "人声音量",
                                value: $recorder.vocalVolume,
                                identifier: "feather.audio.vocal.volume"
                            )
                            syncControl
                        }
                        .padding(16)
                    }
                }
            }
            .disabled(recorder.isBusy || starting || finishing)
        }
    }

    private func mediaRow(
        title: String,
        detail: String,
        icon: String,
        isLoaded: Bool,
        importIdentifier: String,
        clearIdentifier: String,
        importAction: @escaping () -> Void,
        clearAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Button(action: importAction) {
                HStack(spacing: 12) {
                    FeatherIcon(name: icon, size: 21)
                        .foregroundStyle(isLoaded ? FeatherColor.accent(scheme) : FeatherColor.secondary(scheme))
                        .frame(width: 38, height: 38)
                        .background(
                            (isLoaded ? FeatherColor.lagoonWash(scheme) : FeatherColor.raised(scheme)),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(FeatherColor.ink(scheme))
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(FeatherColor.secondary(scheme))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(isLoaded ? "更换" : "选择")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FeatherColor.accent(scheme))
                }
                .padding(.leading, 14)
                .frame(maxWidth: .infinity, minHeight: 70)
                .contentShape(Rectangle())
            }
            .buttonStyle(FeatherPressStyle())
            .accessibilityIdentifier(importIdentifier)

            if isLoaded {
                Button(action: clearAction) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(FeatherColor.secondary(scheme))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FeatherPressStyle())
                .accessibilityLabel("移除\(title)")
                .accessibilityIdentifier(clearIdentifier)
            }
        }
        .padding(.trailing, 8)
    }

    private func levelControl(
        title: String,
        value: Binding<Double>,
        identifier: String
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(FeatherColor.secondary(scheme))
            }
            Slider(value: value, in: 0...1)
                .tint(FeatherColor.accent(scheme))
                .accessibilityLabel(title)
                .accessibilityValue("\(Int((value.wrappedValue * 100).rounded())) 百分比")
                .accessibilityIdentifier(identifier)
        }
    }

    private var syncControl: some View {
        VStack(spacing: 8) {
            HStack {
                Text("人声同步")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: "%+.0f ms", recorder.vocalSyncAdjustmentMilliseconds))
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(FeatherColor.secondary(scheme))
            }
            Slider(
                value: $recorder.vocalSyncAdjustmentMilliseconds,
                in: -500...500,
                step: 10
            )
            .tint(FeatherColor.accent(scheme))
            .accessibilityLabel("人声同步调整")
            .accessibilityValue(String(format: "%+.0f 毫秒", recorder.vocalSyncAdjustmentMilliseconds))
            .accessibilityIdentifier("feather.audio.vocal.sync")
        }
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
        case .recording: FeatherColor.coral
        case .paused, .processing, .mixing: FeatherColor.warning
        case .failed: FeatherColor.coral
        case .idle: FeatherColor.success
        }
    }

    private var routeSummary: String {
        let route = recorder.activeCaptureMode?.rawValue ?? recorder.captureMode.rawValue
        return "48 kHz · \(route)"
    }

    private var sessionSummary: String {
        var parts: [String] = []
        if recorder.hasAccompaniment { parts.append("伴奏") }
        if recorder.hasLyrics { parts.append("歌词") }
        return parts.isEmpty ? "尚未添加" : parts.joined(separator: " + ")
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
        await recorder.start(includeSessionMedia: mode == .session)
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
            showNotice("录音已保存到作品库。", tone: .success)
        }
        return true
    }

    private func close() {
        guard !starting, !finishing else { return }
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
            showNotice("伴奏已添加。", tone: .success)
        } catch {
            showNotice(error.localizedDescription, tone: .error)
        }
    }

    private func receiveLyrics(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try recorder.importLyrics(from: url)
            showNotice("已读取 \(recorder.lyricLines.count) 行歌词。", tone: .success)
        } catch {
            showNotice(error.localizedDescription, tone: .error)
        }
    }

    private func showNotice(_ message: String, tone: FeatherInlineNotice.Tone) {
        let next = RecorderNotice(message: message, tone: tone)
        if reduceMotion {
            notice = next
        } else {
            withAnimation(.easeOut(duration: 0.16)) { notice = next }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.2))
            guard notice?.id == next.id else { return }
            if reduceMotion { notice = nil }
            else { withAnimation(.easeOut(duration: 0.16)) { notice = nil } }
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

private struct FeatherRecorderWaveform: View {
    let samples: [Float]
    let isLive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let visible = normalizedSamples
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(visible.enumerated()), id: \.offset) { index, sample in
                    let amplitude = max(0.06, min(1, CGFloat(abs(sample))))
                    Capsule(style: .continuous)
                        .fill(
                            index == visible.count - 1 && isLive
                                ? FeatherColor.coral
                                : FeatherColor.lagoon.opacity(isLive ? 0.82 : 0.34)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: max(4, amplitude * proxy.size.height))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: visible)
        }
        .accessibilityHidden(true)
    }

    private var normalizedSamples: [Float] {
        if samples.isEmpty { return Array(repeating: 0.08, count: 48) }
        if samples.count == 48 { return samples }
        if samples.count > 48 { return Array(samples.suffix(48)) }
        return Array(repeating: 0.08, count: 48 - samples.count) + samples
    }
}

private struct FeatherLyricsReader: View {
    let title: String?
    let lines: [LyricLine]
    let currentIndex: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                FeatherBackdrop()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                                lyricRow(line, index: index)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
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
                        .font(.caption.weight(.medium))
                        .foregroundStyle(FeatherColor.secondary(scheme))
                        .accessibilityHidden(true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("feather.audio.lyrics.dismiss")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("feather.audio.lyrics.sheet")
    }

    private func lyricRow(_ line: LyricLine, index: Int) -> some View {
        let isCurrent = index == currentIndex
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(timestamp(line.time))
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(isCurrent ? FeatherColor.accent(scheme) : FeatherColor.secondary(scheme))
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 46, alignment: .trailing)
            Text(line.text)
                .font(isCurrent ? .body.weight(.semibold) : .body)
                .foregroundStyle(FeatherColor.ink(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(
            isCurrent ? FeatherColor.lagoonWash(scheme) : FeatherColor.surface(scheme),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(timestamp(line.time))，\(line.text)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("feather.audio.lyrics.line.\(line.id)")
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
