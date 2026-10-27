import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

private enum ProfessionalAudioTool: String, CaseIterable, Identifiable {
    case cut = "剪切"
    case speed = "变速"
    case mix = "声音"
    case smart = "智能"
    case lyrics = "歌词"
    case export = "导出"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .cut: "scissors"
        case .speed: "speedometer"
        case .mix: "slider.vertical.3"
        case .smart: "waveform.badge.magnifyingglass"
        case .lyrics: "text.quote"
        case .export: "waveform.badge.plus"
        }
    }
}

struct AudioEditorView: View {
    let recording: AudioRecording
    @StateObject private var editor: AudioEditor
    @State private var player: AVPlayer
    @State private var isPlaying = false
    @State private var playhead: Double = 0
    @State private var timeObserver: Any?
    @State private var activeTool: ProfessionalAudioTool = .cut
    @State private var outputURL: URL?
    @State private var lyricOutputURL: URL?
    @State private var showLyricsImporter = false
    @State private var expandedLyricID: Int?
    @State private var silenceThreshold: Float = -45
    @State private var silenceMinimumDuration: Double = 0.45
    @State private var silencePadding: Double = 0.08
    @State private var message: String?
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    init(recording: AudioRecording) {
        self.recording = recording
        _editor = StateObject(wrappedValue: AudioEditor(
            sourceURL: recording.url,
            duration: recording.duration
        ))
        _player = State(initialValue: AVPlayer(url: recording.url))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                audioHero
                    .youthStageEntrance()
                toolSelector
                    .youthDelayedReveal(delay: 0.38)
                toolPanel
                    .youthDelayedReveal(delay: 0.44)
                exportButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .background { SignalPageBackground() }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { if let message { toast(message) } }
        .fileImporter(
            isPresented: $showLyricsImporter,
            allowedContentTypes: lyricContentTypes,
            allowsMultipleSelection: false
        ) { result in
            importLyrics(result)
        }
        .task { await editor.loadWaveform() }
        .onAppear { installTimeObserver() }
        .onDisappear {
            player.pause()
            removeTimeObserver()
        }
    }

    private var audioHero: some View {
        VStack(spacing: 12) {
            header
                .padding(9)
                .background(SignalColor.surface(scheme).opacity(0.58))
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
            preview
        }
        .padding(12)
        .background {
            SignalColor.stage
        }
        .clipShape(YouthNotchedPanelShape(cornerRadius: 34, notchWidth: 94, notchDepth: 62))
        .overlay(alignment: .topTrailing) {
            YouthStatusBubble(value: "\(editor.clips.count)", symbol: "waveform")
                .padding(.top, 78)
                .padding(.trailing, 8)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            iconButton("arrow.left") { dismiss() }
            VStack(alignment: .leading, spacing: 2) {
                Text("让声音更好")
                    .font(.system(.title2, design: .rounded, weight: .black))
                Text("\(editor.clips.count) 段  ·  \(format(editor.selectedDuration))")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(MonoTheme.muted(scheme))
            }
            Spacer(minLength: 4)
            iconButton("arrow.uturn.backward", disabled: !editor.canUndo) { editor.undo() }
            iconButton("arrow.uturn.forward", disabled: !editor.canRedo) { editor.redo() }
        }
        .foregroundStyle(MonoTheme.ink(scheme))
    }

    private func iconButton(
        _ symbol: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            MonoIcon(symbol, size: 17, weight: 2.1)
                .frame(width: 42, height: 42)
                .signalControlSurface(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }

    private var preview: some View {
        VStack(spacing: 14) {
            AudioWaveformTimeline(
                samples: editor.waveform,
                duration: recording.duration,
                playhead: playhead,
                onSeek: seek
            )
            .frame(height: 124)

            AudioClipStrip(
                clips: editor.clips,
                selectedID: editor.selectedClipID,
                onSelect: { clip in
                    editor.selectClip(clip.id)
                    seek(clip.start)
                }
            )

            HStack {
                Text(recording.formatText)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                Spacer()
                Button { togglePlayback() } label: {
                    MonoIcon(isPlaying ? "pause.fill" : "play.fill", size: 20, weight: 2.2)
                        .foregroundStyle(MonoTheme.background(scheme))
                        .frame(width: 52, height: 52)
                        .background(MonoTheme.ink(scheme))
                        .clipShape(Circle())
                }
                Spacer()
                Text(preciseTime(playhead))
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.62))
        }
        .padding(15)
        .background(SignalColor.stageRaised)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var toolSelector: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ProfessionalAudioTool.allCases) { tool in
                    Button { activeTool = tool } label: {
                        VStack(spacing: 6) {
                            MonoIcon(tool.symbol, size: 17, weight: 2)
                            Text(tool.rawValue)
                        }
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(activeTool == tool ? SignalColor.acid : MonoTheme.ink(scheme))
                        .frame(width: 70, height: 58)
                        .background(
                            activeTool == tool ? SignalColor.stage : MonoTheme.surface(scheme)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var toolPanel: some View {
        switch activeTool {
        case .cut: cutPanel
        case .speed: speedPanel
        case .mix: mixPanel
        case .smart: smartSilencePanel
        case .lyrics: lyricsPanel
        case .export: exportPanel
        }
    }

    private var cutPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            panelTitle("片段 \((editor.selectedClipIndex ?? 0) + 1)", detail: editor.selectedClip.map { preciseTime($0.duration) })
            HStack(spacing: 7) {
                actionButton("分割", symbol: "scissors", accent: true) {
                    if editor.split(at: playhead) { show("已在播放头分割") }
                    else { show("播放头需要位于片段内部") }
                }
                actionButton("复制", symbol: "plus.square.on.square") { editor.duplicateSelectedClip() }
                actionButton("删除", symbol: "trash", disabled: !editor.canDeleteClip) {
                    editor.deleteSelectedClip()
                }
            }
            HStack(spacing: 7) {
                actionButton("前移", symbol: "arrow.left", disabled: editor.selectedClipIndex == 0) {
                    editor.moveSelected(by: -1)
                }
                actionButton(
                    "后移",
                    symbol: "arrow.right",
                    disabled: editor.selectedClipIndex == editor.clips.count - 1
                ) { editor.moveSelected(by: 1) }
            }

            Divider().overlay(MonoTheme.muted(scheme).opacity(0.22))
            AudioRangeControl(
                lower: Binding(get: { editor.trimStart }, set: { editor.setTrimStart($0) }),
                upper: Binding(get: { editor.trimEnd }, set: { editor.setTrimEnd($0) }),
                range: 0...max(recording.duration, 0.1)
            )
            HStack {
                Button("入点  \(preciseTime(editor.trimStart))") {
                    editor.setTrimStart(playhead)
                }
                Spacer()
                Button("出点  \(preciseTime(editor.trimEnd))") {
                    editor.setTrimEnd(playhead)
                }
            }
            .font(.system(.caption2, design: .monospaced, weight: .black))
            .foregroundStyle(MonoTheme.ink(scheme))
        }
        .padding(15)
        .monoPanel()
    }

    private var speedPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelTitle("音频变速", detail: speedLabel(editor.speed))
            Slider(value: $editor.speed, in: 0.5...2, step: 0.05)
                .tint(MonoTheme.coral)
            HStack(spacing: 7) {
                ForEach([0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { value in
                    choiceChip(speedLabel(value), selected: abs(editor.speed - value) < 0.01) {
                        editor.speed = value
                    }
                }
            }
            Text("成片时长  \(format(editor.selectedDuration))")
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(MonoTheme.muted(scheme))
        }
        .padding(15)
        .monoPanel()
    }

    private var mixPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelTitle("声音", detail: "\(Int(editor.volume * 100))%")
            controlSlider("音量", value: $editor.volume, range: 0...2, text: "\(Int(editor.volume * 100))%")
            controlSlider("淡入", value: $editor.fadeIn, range: 0...8, text: String(format: "%.1fs", editor.fadeIn))
            controlSlider("淡出", value: $editor.fadeOut, range: 0...8, text: String(format: "%.1fs", editor.fadeOut))

            Divider().overlay(MonoTheme.muted(scheme).opacity(0.22))
            panelTitle("人声降噪", detail: editor.noiseReduction < 0.1 ? "关闭" : "\(Int(editor.noiseReduction)) dB")
            Button {
                Task {
                    await editor.autoTuneNoiseReduction()
                    if let floor = editor.detectedNoiseFloor {
                        show(String(format: "噪声底 %.1f dB，已自动设置", floor))
                    } else if let error = editor.noiseAnalysisError {
                        show(error)
                    }
                }
            } label: {
                HStack(spacing: 9) {
                    if editor.isAnalyzingNoise { ProgressView().controlSize(.small) }
                    Image(systemName: "waveform.badge.magnifyingglass")
                    Text(editor.isAnalyzingNoise ? "正在建立噪声指纹" : "智能分析并自动降噪")
                    Spacer()
                    if let floor = editor.detectedNoiseFloor {
                        Text(String(format: "%.1f dB", floor))
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                    }
                }
                .font(.system(.caption, design: .rounded, weight: .black))
                .foregroundStyle(MonoTheme.ink(scheme))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(MonoTheme.background(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(editor.isAnalyzingNoise || editor.isExporting)
            HStack(spacing: 7) {
                ForEach([("关闭", 0.0), ("轻", 8.0), ("中", 16.0), ("强", 24.0)], id: \.0) { option in
                    choiceChip(option.0, selected: abs(editor.noiseReduction - option.1) < 0.1) {
                        editor.noiseReduction = option.1
                    }
                }
            }
            controlSlider(
                "强度",
                value: $editor.noiseReduction,
                range: 0...30,
                text: "\(Int(editor.noiseReduction)) dB"
            )

            Divider().overlay(MonoTheme.muted(scheme).opacity(0.22))
            panelTitle("三段均衡器", detail: "±12 dB")
            HStack(spacing: 7) {
                ForEach(AudioEQPreset.allCases) { preset in
                    choiceChip(preset.rawValue, selected: isEQPresetSelected(preset)) {
                        editor.applyEQPreset(preset)
                    }
                }
            }
            controlSlider("低频", value: $editor.bassGain, range: -12...12, text: dbText(editor.bassGain))
            controlSlider("中频", value: $editor.midGain, range: -12...12, text: dbText(editor.midGain))
            controlSlider("高频", value: $editor.trebleGain, range: -12...12, text: dbText(editor.trebleGain))

            Divider().overlay(MonoTheme.muted(scheme).opacity(0.22))
            panelTitle("音高", detail: semitoneText(editor.pitchSemitones))
            Slider(value: $editor.pitchSemitones, in: -6...6, step: 0.1)
                .tint(MonoTheme.coral)
            HStack(spacing: 7) {
                ForEach([-4.0, -2.0, 0.0, 2.0, 4.0], id: \.self) { value in
                    choiceChip(semitoneText(value), selected: abs(editor.pitchSemitones - value) < 0.05) {
                        editor.pitchSemitones = value
                    }
                }
            }

            HStack(spacing: 7) {
                actionButton("重置效果", symbol: "arrow.counterclockwise") {
                    editor.noiseReduction = 0
                    editor.applyEQPreset(.flat)
                    editor.pitchSemitones = 0
                }
                actionButton(
                    editor.isRenderingPreview ? "处理中" : "生成试听",
                    symbol: "headphones",
                    accent: true,
                    disabled: editor.isRenderingPreview
                ) {
                    Task { await prepareEffectPreview() }
                }
            }
        }
        .padding(15)
        .monoPanel()
    }

    private var smartSilencePanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            panelTitle("智能静音剪辑", detail: editor.silenceRegions.isEmpty ? nil : "\(editor.silenceRegions.count) 段")

            Text("检测停顿并保留自然呼吸，不改变有人声的部分。")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(MonoTheme.muted(scheme))

            HStack(spacing: 7) {
                ForEach([("宽松", Float(-38)), ("均衡", Float(-45)), ("严格", Float(-52))], id: \.0) { item in
                    choiceChip(item.0, selected: abs(silenceThreshold - item.1) < 0.1) {
                        silenceThreshold = item.1
                    }
                }
            }

            HStack {
                Text("最短停顿")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                Slider(value: $silenceMinimumDuration, in: 0.25...1.5, step: 0.05)
                    .tint(MonoTheme.primary)
                Text(String(format: "%.2fs", silenceMinimumDuration))
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .frame(width: 48, alignment: .trailing)
            }

            Button {
                Task { await editor.analyzeSilence(threshold: silenceThreshold, minimumDuration: silenceMinimumDuration) }
            } label: {
                MonoPrimaryButtonLabel(
                    title: editor.isAnalyzingSilence ? "正在分析" : "分析静音",
                    detail: "本地",
                    symbol: "waveform.badge.magnifyingglass",
                    isLoading: editor.isAnalyzingSilence
                )
            }
            .buttonStyle(MonoSpringPressStyle())
            .disabled(editor.isAnalyzingSilence)

            if let error = editor.silenceAnalysisError {
                Text(error)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(MonoTheme.coral)
            }

            if !editor.silenceRegions.isEmpty {
                silenceMap

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("可缩短 \(format(editor.detectedSilenceDuration))")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                        Text("每段两侧保留 \(Int(silencePadding * 1_000)) ms")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(MonoTheme.muted(scheme))
                    }
                    Spacer()
                    Stepper("", value: $silencePadding, in: 0...0.3, step: 0.02)
                        .labelsHidden()
                }

                Button {
                    if editor.applySilenceRemoval(padding: silencePadding) {
                        show("已生成 \(editor.clips.count) 段连续剪辑")
                    } else {
                        show("没有可移除的静音")
                    }
                } label: {
                    MonoPrimaryButtonLabel(title: "应用到时间线", symbol: "timeline.selection")
                }
                .buttonStyle(MonoSpringPressStyle())
            }
        }
        .padding(15)
        .monoPanel()
        .animation(.spring(response: 0.38, dampingFraction: 0.9), value: editor.silenceRegions)
        .sensoryFeedback(.success, trigger: editor.silenceRegions.count)
    }

    private var silenceMap: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(MonoTheme.primary.opacity(0.14))
                ForEach(editor.silenceRegions) { region in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(MonoTheme.coral.opacity(0.72))
                        .frame(
                            width: max(3, proxy.size.width * region.duration / max(editor.duration, 0.1)),
                            height: 28
                        )
                        .offset(x: proxy.size.width * region.start / max(editor.duration, 0.1))
                }
            }
        }
        .frame(height: 28)
        .clipShape(Capsule())
        .accessibilityLabel("静音分布")
    }

    private var lyricsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelTitle("歌词时间轴", detail: editor.hasLyrics ? "\(editor.lyrics.count) 句" : nil)

            HStack(spacing: 7) {
                actionButton(editor.hasLyrics ? "更换" : "导入", symbol: "doc.badge.plus") {
                    showLyricsImporter = true
                }
                actionButton("新建一句", symbol: "plus", accent: true) {
                    expandedLyricID = editor.addLyric(at: playhead)
                }
            }

            if editor.hasLyrics {
                HStack(spacing: 7) {
                    actionButton("整体延后 0.5s", symbol: "backward.end") {
                        editor.shiftLyrics(by: 0.5)
                    }
                    actionButton("整体提前 0.5s", symbol: "forward.end") {
                        editor.shiftLyrics(by: -0.5)
                    }
                }

                Divider().overlay(MonoTheme.muted(scheme).opacity(0.22))

                ForEach(editor.lyrics) { line in
                    lyricRow(line)
                }

                HStack(spacing: 7) {
                    actionButton("保存 LRC", symbol: "square.and.arrow.down", accent: true) {
                        do {
                            lyricOutputURL = try editor.saveLyrics()
                            show("歌词已保存")
                        } catch { show(error.localizedDescription) }
                    }
                    if let lyricOutputURL {
                        ShareLink(item: lyricOutputURL) {
                            MonoLabel("共享", icon: "square.and.arrow.up", iconSize: 15, spacing: 5)
                                .font(.system(.caption, design: .rounded, weight: .black))
                                .foregroundStyle(MonoTheme.ink(scheme))
                                .frame(maxWidth: .infinity, minHeight: 42)
                                .background(MonoTheme.background(scheme))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            } else {
                Text("导入 LRC / QLRC / MLRC / TXT，或在当前播放头新建第一句。")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(MonoTheme.muted(scheme))
            }
        }
        .padding(15)
        .monoPanel()
    }

    private func lyricRow(_ line: LyricLine) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Button {
                    expandedLyricID = expandedLyricID == line.id ? nil : line.id
                } label: {
                    Text(line.time.map(preciseTime) ?? "--:--.--")
                        .font(.system(.caption2, design: .monospaced, weight: .black))
                        .foregroundStyle(expandedLyricID == line.id ? .white : MonoTheme.ink(scheme))
                        .frame(width: 66, height: 34)
                        .background(expandedLyricID == line.id ? MonoTheme.coral : MonoTheme.background(scheme))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)

                TextField("歌词", text: Binding(
                    get: { line.text },
                    set: { editor.updateLyric(line.id, text: $0) }
                ))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .textFieldStyle(.plain)

                Button(role: .destructive) {
                    editor.deleteLyric(line.id)
                } label: {
                    MonoIcon("trash", size: 14, weight: 2)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }

            if expandedLyricID == line.id {
                Slider(
                    value: Binding(
                        get: { line.time ?? 0 },
                        set: { editor.updateLyric(line.id, time: $0) }
                    ),
                    in: 0...max(recording.duration, 0.1),
                    step: 0.01
                )
                .tint(MonoTheme.coral)

                HStack(spacing: 7) {
                    actionButton("−0.1s", symbol: "minus") {
                        editor.updateLyric(line.id, time: (line.time ?? 0) - 0.1)
                    }
                    actionButton("对齐播放头", symbol: "scope", accent: true) {
                        editor.setLyricTime(line.id, to: playhead)
                    }
                    actionButton("+0.1s", symbol: "plus") {
                        editor.updateLyric(line.id, time: (line.time ?? 0) + 0.1)
                    }
                }
            }
        }
        .padding(10)
        .background(MonoTheme.background(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var exportPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelTitle("FFmpeg 导出", detail: editor.exportFormat.rawValue)
            Text("格式").font(.system(.caption, design: .rounded, weight: .black))
            HStack(spacing: 7) {
                ForEach(editor.availableFormats) { format in
                    choiceChip(format.rawValue, selected: editor.exportFormat == format) {
                        editor.exportFormat = format
                    }
                }
            }

            if ![AudioExportFormat.flac, .wav].contains(editor.exportFormat) {
                Text("码率").font(.system(.caption, design: .rounded, weight: .black))
                HStack(spacing: 7) {
                    ForEach(AudioExportBitrate.allCases) { bitrate in
                        choiceChip(bitrate.title, selected: editor.exportBitrate == bitrate) {
                            editor.exportBitrate = bitrate
                        }
                    }
                }
            }

            Text("采样率").font(.system(.caption, design: .rounded, weight: .black))
            HStack(spacing: 7) {
                ForEach([44_100, 48_000, 96_000], id: \.self) { rate in
                    choiceChip(rate == 44_100 ? "44.1K" : "\(rate / 1_000)K", selected: editor.exportSampleRate == rate) {
                        editor.exportSampleRate = rate
                    }
                }
            }

            Text("声道").font(.system(.caption, design: .rounded, weight: .black))
            HStack(spacing: 7) {
                choiceChip("单声道", selected: editor.exportChannelCount == 1) { editor.exportChannelCount = 1 }
                choiceChip("立体声", selected: editor.exportChannelCount == 2) { editor.exportChannelCount = 2 }
            }

            if let outputURL {
                ShareLink(item: outputURL) {
                    MonoLabel("共享最近导出", icon: "square.and.arrow.up")
                        .font(.system(.subheadline, design: .rounded, weight: .black))
                        .foregroundStyle(MonoTheme.ink(scheme))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(MonoTheme.background(scheme))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
        .padding(15)
        .monoPanel()
    }

    private func panelTitle(_ title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.headline, design: .rounded, weight: .black))
            Spacer()
            if let detail {
                Text(detail)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(MonoTheme.muted(scheme))
            }
        }
    }

    private func actionButton(
        _ title: String,
        symbol: String,
        accent: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            MonoLabel(title, icon: symbol, iconSize: 15, spacing: 5)
                .font(.system(.caption, design: .rounded, weight: .black))
                .foregroundStyle(accent ? .white : MonoTheme.ink(scheme))
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(accent ? MonoTheme.coral : MonoTheme.background(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }

    private func choiceChip(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .black))
                .foregroundStyle(selected ? MonoTheme.background(scheme) : MonoTheme.ink(scheme))
                .frame(maxWidth: .infinity, minHeight: 38)
                .padding(.horizontal, 6)
                .background(selected ? MonoTheme.ink(scheme) : MonoTheme.background(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func controlSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        text: String
    ) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title).font(.system(.caption, design: .rounded, weight: .black))
                Spacer()
                Text(text)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(MonoTheme.muted(scheme))
            }
            Slider(value: value, in: range).tint(MonoTheme.coral)
        }
    }

    private var exportButton: some View {
        Button { Task { await export() } } label: {
            HStack(spacing: 10) {
                if editor.isExporting { ProgressView().tint(.white) }
                Text(editor.isExporting ? "正在处理" : "导出音频")
                Spacer()
                if editor.isExporting {
                    Text("\(Int(editor.exportProgress * 100))%")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                }
                MonoIcon("arrow.up.right", size: 18, weight: 2.2)
            }
            .font(.system(.body, design: .rounded, weight: .black))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(SignalColor.acid)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(editor.isExporting)
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if playhead < editor.trimStart || playhead >= editor.trimEnd { seek(editor.trimStart) }
            player.volume = Float(min(editor.volume, 1))
            player.playImmediately(atRate: Float(editor.speed))
            isPlaying = true
        }
    }

    private func seek(_ seconds: Double) {
        let value = min(max(seconds, 0), recording.duration)
        player.seek(
            to: CMTime(seconds: value, preferredTimescale: 60_000),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        playhead = value
    }

    private func installTimeObserver() {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 1 / 30, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            Task { @MainActor in
                playhead = max(0, time.seconds)
                if time.seconds >= editor.trimEnd {
                    player.pause()
                    isPlaying = false
                }
            }
        }
    }

    private func removeTimeObserver() {
        guard let timeObserver else { return }
        player.removeTimeObserver(timeObserver)
        self.timeObserver = nil
    }

    private func export() async {
        do {
            outputURL = try await editor.export()
            await library.reload()
            show("音频已导出")
        } catch { show(error.localizedDescription) }
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

    private func importLyrics(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try editor.importLyrics(from: url)
            lyricOutputURL = nil
            show("歌词已导入")
        } catch { show(error.localizedDescription) }
    }

    private func toast(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .rounded, weight: .bold))
            .foregroundStyle(MonoTheme.background(scheme))
            .padding(.horizontal, 16)
            .frame(minHeight: 42)
            .background(MonoTheme.ink(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.top, 12)
    }

    private func show(_ text: String) {
        withAnimation(.easeOut(duration: 0.18)) { message = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.18)) { message = nil }
        }
    }

    private func format(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func preciseTime(_ seconds: Double) -> String {
        let minutes = Int(max(0, seconds)) / 60
        let value = max(0, seconds) - Double(minutes * 60)
        return String(format: "%02d:%05.2f", minutes, value)
    }

    private func speedLabel(_ value: Double) -> String {
        value == floor(value) ? "\(Int(value))×" : "\(String(format: "%.2g", value))×"
    }

    private func dbText(_ value: Double) -> String {
        String(format: "%+.1f dB", value)
    }

    private func semitoneText(_ value: Double) -> String {
        abs(value) < 0.05 ? "0" : String(format: "%+.1f", value)
    }

    private func isEQPresetSelected(_ preset: AudioEQPreset) -> Bool {
        let values: (bass: Double, mid: Double, treble: Double)
        switch preset {
        case .flat:
            values = (0, 0, 0)
        case .vocal:
            values = (-1.5, 3.5, 1.5)
        case .warm:
            values = (3, 1, -1)
        case .bright:
            values = (-1, 1.5, 4)
        }
        return abs(editor.bassGain - values.bass) < 0.05
            && abs(editor.midGain - values.mid) < 0.05
            && abs(editor.trebleGain - values.treble) < 0.05
    }

    private func prepareEffectPreview() async {
        do {
            let url = try await editor.renderEffectPreview()
            player.pause()
            isPlaying = false
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            seek(0)
            show("试听已生成")
        } catch {
            show(error.localizedDescription)
        }
    }
}

private struct AudioWaveformTimeline: View {
    let samples: [Float]
    let duration: Double
    let playhead: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let values = samples.isEmpty ? Array(repeating: Float(0.12), count: 96) : samples
            ZStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 1.5) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        let progress = Double(index) / Double(max(1, values.count - 1))
                        Capsule()
                            .fill(progress <= playhead / max(duration, 0.01) ? MonoTheme.coral : Color.secondary.opacity(0.35))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(3, CGFloat(value) * proxy.size.height))
                    }
                }
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2)
                    .offset(x: min(proxy.size.width - 2, proxy.size.width * playhead / max(duration, 0.01)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    onSeek(Double(min(max(value.location.x / proxy.size.width, 0), 1)) * duration)
                }
            )
        }
        .accessibilityLabel("音频波形时间线")
    }
}

private struct AudioClipStrip: View {
    let clips: [AudioClip]
    let selectedID: UUID
    let onSelect: (AudioClip) -> Void

    var body: some View {
        GeometryReader { proxy in
            let total = max(0.001, clips.reduce(0) { $0 + $1.duration })
            HStack(spacing: 3) {
                ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                    Button { onSelect(clip) } label: {
                        Text("A\(index + 1)")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(selectedID == clip.id ? .white : .black)
                            .frame(
                                width: max(30, (proxy.size.width - CGFloat(max(0, clips.count - 1)) * 3) * clip.duration / total),
                                height: 26
                            )
                            .background(selectedID == clip.id ? MonoTheme.coral : Color.white.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 26)
        .clipped()
    }
}

private struct AudioRangeControl: View {
    @Binding var lower: Double
    @Binding var upper: Double
    let range: ClosedRange<Double>
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let lowerX = x(for: lower, width: width)
            let upperX = x(for: upper, width: width)
            ZStack(alignment: .leading) {
                Capsule().fill(MonoTheme.muted(scheme).opacity(0.26)).frame(height: 8)
                Capsule().fill(MonoTheme.coral)
                    .frame(width: max(0, upperX - lowerX), height: 8)
                    .offset(x: lowerX)
                handle.offset(x: lowerX - 10).gesture(drag(width: width, isLower: true))
                handle.offset(x: upperX - 10).gesture(drag(width: width, isLower: false))
            }
            .frame(height: 44)
        }
        .frame(height: 44)
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(MonoTheme.ink(scheme))
            .frame(width: 20, height: 32)
    }

    private func drag(width: CGFloat, isLower: Bool) -> some Gesture {
        DragGesture().onChanged { value in
            let mapped = range.lowerBound
                + Double(min(max(value.location.x / width, 0), 1)) * (range.upperBound - range.lowerBound)
            if isLower { lower = min(upper - 0.01, mapped) }
            else { upper = max(lower + 0.01, mapped) }
        }
    }

    private func x(for value: Double, width: CGFloat) -> CGFloat {
        CGFloat((value - range.lowerBound) / max(range.upperBound - range.lowerBound, 0.001)) * width
    }
}
