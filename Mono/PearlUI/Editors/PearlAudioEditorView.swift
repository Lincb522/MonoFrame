import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct PearlAudioEditorView: View {
    private enum Tool: String, CaseIterable, Identifiable {
        case clips = "剪切"
        case tone = "均衡"
        case cleanup = "降噪"
        case lyrics = "歌词"

        var id: String { rawValue }
        var glyph: PearlGlyphName {
            switch self {
            case .clips: .trim
            case .tone: .waveform
            case .cleanup: .refresh
            case .lyrics: .document
            }
        }
    }

    @StateObject private var editor: AudioEditor
    @StateObject private var playback: PearlPlaybackController
    @State private var selectedTool: Tool = .tone
    @State private var showingExport = false
    @State private var showingLyrics = false
    @State private var fileExport: PearlExportItem?
    private let recording: AudioRecording
    @State private var importingLyrics = false
    @State private var outputURL: URL?
    @State private var notice: PearlEditorNotice?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    init(recording: AudioRecording) {
        self.recording = recording
        _editor = StateObject(wrappedValue: AudioEditor(sourceURL: recording.url, duration: recording.duration))
        _playback = StateObject(wrappedValue: PearlPlaybackController(url: recording.url))
    }

    var body: some View {
        VStack(spacing: 0) {
            PearlSecondaryHeader(title: recording.title) {
                Button("导出") { showingExport = true }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(PearlColor.onAccent(scheme))
                    .padding(.horizontal, 17).frame(minHeight: 44)
                    .background(PearlColor.action(scheme), in: Capsule())
                    .accessibilityIdentifier("pearl.audioEditor.openExport")
            }
            PearlPage(maxWidth: 850) {
                VStack(spacing: 22) {
                    PearlAudioSelection(samples: editor.waveform, duration: editor.duration,
                        start: Binding(get: { editor.trimStart }, set: { editor.setTrimStart($0) }),
                        end: Binding(get: { editor.trimEnd }, set: { editor.setTrimEnd($0) }),
                        position: Binding(get: { playback.time }, set: { playback.seek(to: $0) }))
                        .padding(.top, 10)
                    if let error = editor.waveformError {
                        PearlInlineNotice(message: error, tone: .error)
                        Button("重新加载波形") { Task { await editor.loadWaveform() } }
                    }
                    HStack {
                        Text(audioTimecode(playback.time)).font(.title2.monospacedDigit().weight(.bold)).foregroundStyle(PearlColor.accent(scheme))
                        Text("/ \(audioTimecode(editor.duration))").font(.caption.monospacedDigit()).foregroundStyle(PearlColor.secondary(scheme))
                        Spacer(minLength: 5)
                        PearlSurface {
                            Button { playback.toggle(range: editor.trimStart...editor.trimEnd) } label: {
                                PearlGlyph(playback.isPlaying ? .pause : .play, size: 22).frame(width: 76, height: 48)
                            }.buttonStyle(PearlPressStyle()).accessibilityLabel(playback.isPlaying ? "暂停" : "播放")
                                .accessibilityIdentifier("pearl.audioEditor.play")
                        }
                    }
                    if editor.clips.count > 1 {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(Array(editor.clips.enumerated()), id: \.element.id) { index, clip in
                                    PearlChoiceChip("\(index + 1) · \(audioTimecode(clip.duration))", selected: clip.id == editor.selectedClipID) { editor.selectClip(clip.id) }
                                }
                            }
                        }.scrollIndicators(.hidden)
                    }
                    audioToolStrip
                    activeAudioTool
                    HStack {
                        PearlIconButton(title: "撤销", glyph: .undo) { editor.undo() }.disabled(!editor.canUndo)
                        PearlIconButton(title: "重做", glyph: .redo) { editor.redo() }.disabled(!editor.canRedo)
                        Spacer()
                    }
                    audioNotice
                }
            }
        }
        .background(PearlBackdrop()).toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingExport) {
            PearlSecondaryLayout(title: "导出音频") { PearlPage(maxWidth: 660) { VStack(spacing: 18) { audioExportTools; audioNotice } } }
                .interactiveDismissDisabled(editor.isExporting)
                .sheet(item: $fileExport) { PearlFileExporter(url: $0.url) }
        }
        .sheet(isPresented: $showingLyrics) {
            PearlLyricReadingView(lines: editor.lyrics.enumerated().map { index, line in
                PearlLyricReadingLine(id: index, time: line.time, text: line.text)
            }, currentIndex: editor.lyrics.lastIndex(where: { ($0.time ?? 0) <= playback.time }))
        }
        .fileImporter(isPresented: $importingLyrics, allowedContentTypes: lyricTypes, allowsMultipleSelection: false, onCompletion: receiveLyrics)
        .task { await editor.loadWaveform() }
        .onChange(of: editor.selectedClipID) { _, _ in playback.seek(to: editor.trimStart) }
        .onDisappear { playback.pause() }

    }

    private var audioToolStrip: some View {
        HStack(spacing: 0) {
            ForEach(Tool.allCases) { tool in
                Button { selectedTool = tool } label: {
                    Text(tool.rawValue).font(.subheadline.weight(selectedTool == tool ? .semibold : .regular))
                        .foregroundStyle(selectedTool == tool ? PearlColor.accent(scheme) : PearlColor.secondary(scheme))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(alignment: .bottom) { if selectedTool == tool { Capsule().fill(PearlColor.accent(scheme)).frame(height: 2) } }
                }.buttonStyle(PearlPressStyle()).accessibilityAddTraits(selectedTool == tool ? .isSelected : [])
            }
        }.overlay(alignment: .bottom) { PearlHairline().zIndex(-1) }
    }

    @ViewBuilder private var activeAudioTool: some View {
        switch selectedTool {
        case .clips: audioClipTools
        case .tone: audioToneTools
        case .cleanup: audioCleanupTools
        case .lyrics: audioLyricsTools
        }
    }

    private var audioClipTools: some View {
        PearlEditorSection(title: "片段", detail: "\(editor.clips.count) 段") {
            PearlEditorSlider(
                title: "入点",
                value: Binding(get: { editor.trimStart }, set: { editor.setTrimStart($0) }),
                range: 0...max(editor.duration, 0.1),
                valueText: audioTimecode(editor.trimStart)
            )
            PearlHairline()
            PearlEditorSlider(
                title: "出点",
                value: Binding(get: { editor.trimEnd }, set: { editor.setTrimEnd($0) }),
                range: 0...max(editor.duration, 0.1),
                valueText: audioTimecode(editor.trimEnd)
            )
            PearlHairline()
            PearlEditorSlider(
                title: "速度",
                value: $editor.speed,
                range: 0.25...4,
                valueText: String(format: "%.2f×", editor.speed)
            )
            PearlHairline()
            PearlEditorSlider(
                title: "音量",
                value: $editor.volume,
                range: 0...2,
                valueText: "\(Int(editor.volume * 100))%"
            )
            PearlHairline()
            PearlEditorActionGrid {
                PearlEditorAction(title: "分割", glyph: .trim) {
                    if !editor.split(at: playback.time) { showAudioNotice("当前位置无法分割。", error: true) }
                }
                PearlEditorAction(title: "复制", glyph: .plus) { editor.duplicateSelectedClip() }
                PearlEditorAction(title: "删除", glyph: .trash, destructive: true) { editor.deleteSelectedClip() }
                    .disabled(!editor.canDeleteClip)
            }
        }
    }

    private var audioToneTools: some View {
        PearlEditorSection(title: "音色", detail: editor.hasAudioEffects ? "已调整" : "原声") {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(AudioEQPreset.allCases) { preset in
                        PearlChoiceChip(preset.rawValue, selected: false) { editor.applyEQPreset(preset) }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.vertical, 10)
            PearlHairline()
            let faderLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 20)) : AnyLayout(HStackLayout(spacing: 24))
            faderLayout {
                PearlEqualizerFader(title: "低频", value: $editor.bassGain)
                PearlEqualizerFader(title: "中频", value: $editor.midGain)
                PearlEqualizerFader(title: "高频", value: $editor.trebleGain)
            }.frame(maxWidth: .infinity).padding(.vertical, 14)
            PearlHairline()
            PearlEditorSlider(
                title: "音高",
                value: $editor.pitchSemitones,
                range: -12...12,
                valueText: String(format: "%+.0f", editor.pitchSemitones)
            )
            PearlHairline()
            PearlEditorAction(title: editor.isRenderingPreview ? "正在生成试听" : "试听处理效果", glyph: .play) {
                Task { await previewAudioEffects() }
            }
            .disabled(editor.isRenderingPreview)
        }
    }

    private var audioCleanupTools: some View {
        PearlEditorSection(title: "降噪", detail: "保留人声细节") {
            PearlEditorSlider(
                title: "降噪强度",
                value: $editor.noiseReduction,
                range: 0...1,
                valueText: "\(Int(editor.noiseReduction * 100))%"
            )
            PearlHairline()
            PearlEditorAction(
                title: editor.isAnalyzingNoise ? "正在识别噪声" : "自动匹配降噪",
                glyph: .refresh
            ) { Task { await editor.autoTuneNoiseReduction() } }
            .disabled(editor.isAnalyzingNoise)
            PearlHairline()
            PearlEditorAction(
                title: editor.isAnalyzingSilence ? "正在分析静音" : "检测静音片段",
                glyph: .waveform
            ) { Task { await editor.analyzeSilence() } }
            .disabled(editor.isAnalyzingSilence)
            PearlHairline()
            PearlEditorAction(
                title: editor.silenceRegions.isEmpty
                    ? "移除静音片段"
                    : String(format: "移除静音，可缩短 %.1f 秒", editor.detectedSilenceDuration),
                glyph: .trash,
                destructive: true
            ) {
                if editor.applySilenceRemoval() { showAudioNotice("静音片段已移除。") }
            }
            .disabled(editor.silenceRegions.isEmpty)

            if let error = editor.silenceAnalysisError ?? editor.noiseAnalysisError {
                PearlInlineNotice(message: error, tone: .warning).padding(.top, 8)
            }
        }
    }

    private var audioLyricsTools: some View {
        PearlEditorSection(
            title: "歌词",
            detail: editor.lyrics.isEmpty ? "未导入" : "\(editor.lyrics.count) 行"
        ) {
            if !editor.lyrics.isEmpty {
                PearlEditorAction(title: "全屏预览", glyph: .captions) { showingLyrics = true }
                PearlHairline()
            }
            PearlEditorAction(title: "导入歌词", glyph: .plus) { importingLyrics = true }
            PearlHairline()
            PearlEditorAction(title: "在 \(audioTimecode(playback.time)) 添加一行", glyph: .document) {
                _ = editor.addLyric(at: playback.time)
            }
            ForEach(editor.lyrics) { line in
                PearlHairline()
                VStack(spacing: 8) {
                    HStack {
                        Button(audioTimecode(line.time ?? 0)) {
                            editor.setLyricTime(line.id, to: playback.time)
                        }
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(PearlColor.accent(scheme))
                        .frame(minWidth: 54, minHeight: 44)
                        .buttonStyle(PearlPressStyle())

                        TextField(
                            "歌词内容",
                            text: Binding(
                                get: { editor.lyrics.first(where: { $0.id == line.id })?.text ?? line.text },
                                set: { editor.updateLyric(line.id, text: $0) }
                            ), axis: .vertical
                        )
                        .textFieldStyle(.plain)

                        Button(role: .destructive) { editor.deleteLyric(line.id) } label: {
                            PearlGlyph(.trash, size: 18).frame(width: 44, height: 44)
                        }
                        .buttonStyle(PearlPressStyle())
                        .accessibilityLabel("删除歌词 \(line.text)")
                    }
                }
                .frame(minHeight: 52)
            }
            if !editor.lyrics.isEmpty {
                PearlHairline()
                PearlEditorAction(title: "保存歌词文件", glyph: .download) {
                    do {
                        _ = try editor.saveLyrics()
                        showAudioNotice("歌词已保存。")
                    } catch {
                        showAudioNotice(error.localizedDescription, error: true)
                    }
                }
            }
        }
    }

    private var audioExportTools: some View {
        PearlEditorSection(title: "导出", detail: outputURL == nil ? "音频文件" : "已生成") {
            Menu {
                ForEach(editor.availableFormats) { format in
                    Button(format.rawValue) { editor.exportFormat = format }
                }
            } label: {
                PearlPlainRow("格式", accessibilityValue: editor.exportFormat.rawValue) {
                    Text(editor.exportFormat.rawValue).foregroundStyle(PearlColor.tertiary(scheme))
                }
            }
            .buttonStyle(PearlPressStyle())
            PearlHairline()
            Menu {
                ForEach(AudioExportBitrate.allCases) { bitrate in
                    Button(bitrate.title) { editor.exportBitrate = bitrate }
                }
            } label: {
                PearlPlainRow("码率", accessibilityValue: editor.exportBitrate.title) {
                    Text(editor.exportBitrate.title).foregroundStyle(PearlColor.tertiary(scheme))
                }
            }
            .buttonStyle(PearlPressStyle())
            PearlHairline()
            Menu {
                ForEach([44_100, 48_000], id: \.self) { rate in
                    Button("\(rate / 1_000) kHz") { editor.exportSampleRate = rate }
                }
            } label: {
                PearlPlainRow("采样率", accessibilityValue: "\(editor.exportSampleRate / 1_000) 千赫兹") {
                    Text("\(editor.exportSampleRate / 1_000) kHz").foregroundStyle(PearlColor.tertiary(scheme))
                }
            }
            .buttonStyle(PearlPressStyle())
            PearlHairline()
            if editor.isExporting {
                VStack(spacing: 7) {
                    ProgressView(value: editor.exportProgress).tint(PearlColor.accent(scheme))
                    Text("正在生成 \(Int(editor.exportProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(PearlColor.tertiary(scheme))
                }
                .padding(.vertical, 10)
            }
            Button { Task { await exportAudio() } } label: {
                PearlExportLabel(
                    title: editor.isExporting ? "正在导出" : "导出音频",
                    active: editor.isExporting
                )
            }
            .buttonStyle(PearlPressStyle())
            .disabled(editor.isExporting)
            .accessibilityIdentifier("pearl.audioEditor.export")

            if let outputURL {
                Button { fileExport = PearlExportItem(url: outputURL) } label: {
                    PearlPrimaryLabel(title: "保存到文件", glyph: .export)
                }.buttonStyle(PearlPressStyle()).accessibilityIdentifier("pearl.audioEditor.saveFile")
                ShareLink(item: outputURL) {
                    PearlShareReadyLabel(fileName: outputURL.lastPathComponent)
                }
                .buttonStyle(PearlPressStyle())
                .accessibilityIdentifier("pearl.audioEditor.share")
            }
        }
    }

    @ViewBuilder private var audioNotice: some View {
        if let notice {
            PearlInlineNotice(message: notice.message, tone: notice.isError ? .error : .info)
                .id(notice.id)
                .transition(.opacity)
        }
    }

    private var lyricTypes: [UTType] {
        var values: [UTType] = [.plainText, .utf8PlainText]
        for fileExtension in LyricDocumentCodec.supportedFileExtensions where fileExtension != "txt" {
            if let type = UTType(filenameExtension: fileExtension), !values.contains(type) {
                values.append(type)
            }
        }
        return values
    }

    private func receiveLyrics(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try editor.importLyrics(from: url)
            showAudioNotice("已导入 \(editor.lyrics.count) 行歌词。")
        } catch {
            showAudioNotice(error.localizedDescription, error: true)
        }
    }

    @MainActor private func previewAudioEffects() async {
        do {
            let url = try await editor.renderEffectPreview()
            playback.replace(with: url)
            playback.play(range: 0...min(editor.selectedDuration, 12))
        } catch {
            showAudioNotice(error.localizedDescription, error: true)
        }
    }

    @MainActor private func exportAudio() async {
        do {
            outputURL = try await editor.export()
            showAudioNotice("音频已生成，可以分享或保存。")
        } catch {
            showAudioNotice(error.localizedDescription, error: true)
        }
    }

    private func showAudioNotice(_ message: String, error: Bool = false) {
        let next = PearlEditorNotice(message: message, isError: error)
        if reduceMotion { notice = next }
        else { withAnimation(.easeOut(duration: 0.16)) { notice = next } }
    }

    private func audioTimecode(_ time: Double) -> String {
        let value = max(0, Int(time.rounded(.down)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

