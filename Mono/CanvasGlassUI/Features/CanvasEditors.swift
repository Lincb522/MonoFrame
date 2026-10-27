import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Video editor

struct CanvasVideoEditorView: View {
    private enum Tool: String, CaseIterable, Identifiable {
        case clips = "片段"
        case look = "画面"
        case canvas = "构图"
        case captions = "字幕"
        case audio = "音轨"
        case export = "导出"

        var id: String { rawValue }
        var glyph: CanvasGlyphName {
            switch self {
            case .clips: .trim
            case .look: .image
            case .canvas: .edit
            case .captions: .captions
            case .audio: .audio
            case .export: .export
            }
        }
    }

    @StateObject private var editor: VideoEditor
    @StateObject private var playback: CanvasPlaybackController
    @State private var selectedTool: Tool = .clips
    @State private var captionDraft = ""
    @State private var captionDuration = 3.0
    @State private var importingAudio = false
    @State private var outputURL: URL?
    @State private var notice: CanvasEditorNotice?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(recording: Recording) {
        _editor = StateObject(wrappedValue: VideoEditor(sourceURL: recording.url, duration: recording.duration))
        _playback = StateObject(wrappedValue: CanvasPlaybackController(url: recording.url))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                mediaCanvas
                videoTimeline.padding(.top, 18)
                transport.padding(.top, 18)
                toolStrip.padding(.top, 24)
                noticeView.padding(.top, notice == nil ? 0 : 14)
                activeTool.padding(.top, 22)
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
        .background(CanvasBackdrop())
        .navigationTitle("视频编辑")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $importingAudio,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false,
            onCompletion: receiveBackgroundAudio
        )
        .task { await editor.loadFFmpegPreview() }
        .onChange(of: editor.selectedClipID) { _, _ in
            playback.replace(with: editor.selectedSourceURL)
            playback.seek(to: editor.trimStart)
        }
        .onDisappear { playback.pause() }
        .accessibilityIdentifier("canvas.videoEditor.page")
    }

    private var mediaCanvas: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black)

            VideoPlayer(player: playback.player)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .allowsHitTesting(false)

            if let caption = visibleCaption {
                Text(caption.text)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.72), radius: 4, y: 2)
                    .padding(.horizontal, 18)
                    .frame(maxHeight: .infinity, alignment: captionAlignment(caption.position))
                    .padding(.vertical, 22)
                    .allowsHitTesting(false)
            }

            if !editor.overlayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(editor.overlayText)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white.opacity(editor.overlayOpacity))
                    .shadow(color: .black.opacity(0.65), radius: 4, y: 2)
                    .padding(20)
                    .frame(maxHeight: .infinity, alignment: captionAlignment(editor.overlayPosition))
                    .allowsHitTesting(false)
            }
        }
        .aspectRatio(editor.canvasRatio.value ?? (16 / 9), contentMode: .fit)
        .frame(maxHeight: 330)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("视频预览")
        .accessibilityValue(editor.timecode(playback.time))
        .accessibilityIdentifier("canvas.videoEditor.preview")
    }

    private var videoTimeline: some View {
        VStack(spacing: 11) {
            HStack {
                Text(editor.timecode(playback.time))
                Spacer()
                Text(editor.timecode(editor.projectDuration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(CanvasColor.tertiary(scheme))

            ZStack {
                CanvasVideoFilmstrip(frames: editor.timelineFrames)
                    .frame(height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Rectangle()
                    .fill(CanvasColor.coral)
                    .frame(width: 1.5)
                    .allowsHitTesting(false)
            }

            Slider(
                value: Binding(
                    get: { playback.time },
                    set: { playback.seek(to: $0) }
                ),
                in: 0...max(editor.duration, 0.1),
                step: editor.frameDuration
            )
            .tint(CanvasColor.accent(scheme))
            .frame(minHeight: 44)
            .accessibilityLabel("播放位置")
            .accessibilityValue(editor.timecode(playback.time))

            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(Array(editor.clips.enumerated()), id: \.element.id) { index, clip in
                        Button {
                            editor.selectClip(clip.id)
                        } label: {
                            HStack(spacing: 6) {
                                Text("\(index + 1)")
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                Text(editor.timecode(clip.timelineDuration))
                                    .font(.caption2.monospacedDigit())
                            }
                            .foregroundStyle(
                                clip.id == editor.selectedClipID
                                    ? CanvasColor.background(scheme)
                                    : CanvasColor.ink(scheme)
                            )
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(
                                clip.id == editor.selectedClipID
                                    ? CanvasColor.accent(scheme)
                                    : CanvasColor.elevated(scheme),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(CanvasPressStyle())
                        .accessibilityLabel("片段 \(index + 1)，\(editor.timecode(clip.timelineDuration))")
                        .accessibilityAddTraits(clip.id == editor.selectedClipID ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas.videoEditor.timeline")
    }

    private var transport: some View {
        CanvasGlassSurface(cornerRadius: 28) {
            HStack(spacing: 0) {
                transportButton("撤销", glyph: .undo, enabled: editor.canUndo) { editor.undo() }
                Spacer(minLength: 8)
                Button {
                    playback.toggle(range: editor.trimStart...editor.trimEnd)
                } label: {
                    ZStack {
                        Circle()
                            .fill(CanvasColor.accent(scheme))
                            .frame(width: 52, height: 52)
                        CanvasGlyph(playback.isPlaying ? .pause : .play, size: 22, weight: 2)
                            .foregroundStyle(CanvasColor.background(scheme))
                    }
                    .frame(width: 60, height: 60)
                    .contentShape(Circle())
                }
                .buttonStyle(CanvasPressStyle())
                .accessibilityLabel(playback.isPlaying ? "暂停" : "播放")
                .accessibilityIdentifier("canvas.videoEditor.play")
                Spacer(minLength: 8)
                transportButton("重做", glyph: .redo, enabled: editor.canRedo) { editor.redo() }
            }
            .padding(.horizontal, 12)
            .frame(width: 264, height: 64)
        }
        .frame(maxWidth: .infinity)
    }

    private func transportButton(
        _ title: String,
        glyph: CanvasGlyphName,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                CanvasGlyph(glyph, size: 18)
                Text(title).font(.caption2.weight(.medium))
            }
            .foregroundStyle(CanvasColor.secondary(scheme))
            .frame(width: 58)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(CanvasPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }

    private var toolStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(Tool.allCases) { tool in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                            selectedTool = tool
                        }
                    } label: {
                        VStack(spacing: 5) {
                            CanvasGlyph(tool.glyph, size: 19)
                            Text(tool.rawValue).font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(
                            selectedTool == tool
                                ? CanvasColor.accent(scheme)
                                : CanvasColor.secondary(scheme)
                        )
                        .frame(width: 58)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CanvasPressStyle())
                    .accessibilityAddTraits(selectedTool == tool ? .isSelected : [])
                    .accessibilityIdentifier("canvas.videoEditor.tool.\(tool.rawValue)")
                }
            }
            .padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) { CanvasHairline() }
    }

    @ViewBuilder private var activeTool: some View {
        switch selectedTool {
        case .clips: videoClipTools
        case .look: videoLookTools
        case .canvas: videoCanvasTools
        case .captions: videoCaptionTools
        case .audio: videoAudioTools
        case .export: videoExportTools
        }
    }

    private var videoClipTools: some View {
        CanvasEditorSection(title: "片段", detail: "\(editor.clips.count) 段") {
            CanvasEditorSlider(
                title: "入点",
                value: Binding(get: { editor.trimStart }, set: { editor.setTrimStart($0) }),
                range: 0...max(editor.duration, 0.1),
                valueText: editor.timecode(editor.trimStart)
            )
            CanvasHairline()
            CanvasEditorSlider(
                title: "出点",
                value: Binding(get: { editor.trimEnd }, set: { editor.setTrimEnd($0) }),
                range: 0...max(editor.duration, 0.1),
                valueText: editor.timecode(editor.trimEnd)
            )
            CanvasHairline()
            CanvasEditorSlider(
                title: "速度",
                value: $editor.speed,
                range: 0.25...4,
                valueText: String(format: "%.2f×", editor.speed)
            )
            CanvasHairline()
            CanvasEditorActionGrid {
                CanvasEditorAction(title: "分割", glyph: .trim) {
                    if !editor.split(at: playback.time) {
                        showNotice("当前位置无法分割。", error: true)
                    }
                }
                CanvasEditorAction(title: "复制", glyph: .plus) { editor.duplicateSelectedClip() }
                CanvasEditorAction(title: "删除", glyph: .trash, destructive: true) { editor.deleteSelectedClip() }
                    .disabled(!editor.canDeleteClip)
            }
        }
    }

    private var videoLookTools: some View {
        CanvasEditorSection(title: "画面", detail: editor.look.rawValue) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(VideoLook.allCases) { look in
                        CanvasChoiceChip(look.rawValue, selected: editor.look == look) { editor.apply(look) }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.vertical, 10)
            CanvasHairline()
            CanvasEditorSlider(title: "亮度", value: $editor.brightness, range: -1...1)
            CanvasHairline()
            CanvasEditorSlider(title: "对比度", value: $editor.contrast, range: 0.5...1.5)
            CanvasHairline()
            CanvasEditorSlider(title: "饱和度", value: $editor.saturation, range: 0...2)
            CanvasHairline()
            CanvasEditorSlider(title: "色温", value: $editor.warmth, range: -1...1)
            CanvasHairline()
            CanvasEditorAction(title: "恢复原始画面", glyph: .refresh) { editor.resetVisualAdjustments() }
        }
    }

    private var videoCanvasTools: some View {
        CanvasEditorSection(title: "构图", detail: editor.canvasRatio.rawValue) {
            Menu {
                ForEach(VideoCanvasRatio.allCases) { ratio in
                    Button(ratio.rawValue) { editor.canvasRatio = ratio }
                }
            } label: {
                CanvasPlainRow("画布比例", accessibilityValue: editor.canvasRatio.rawValue) {
                    Text(editor.canvasRatio.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(CanvasColor.tertiary(scheme))
                }
            }
            .buttonStyle(CanvasPressStyle())
            CanvasHairline()
            CanvasEditorActionGrid {
                CanvasEditorAction(title: "旋转", glyph: .redo) { editor.rotateClockwise() }
                CanvasEditorAction(
                    title: editor.isMirrored ? "取消镜像" : "镜像",
                    glyph: .refresh
                ) { editor.isMirrored.toggle() }
            }
            CanvasHairline()
            CanvasPlainRow("叠加文字") {
                TextField("输入画面文字", text: $editor.overlayText)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
            }
            CanvasHairline()
            Menu {
                ForEach(VideoTextPosition.allCases) { position in
                    Button(position.rawValue) { editor.overlayPosition = position }
                }
            } label: {
                CanvasPlainRow("文字位置", accessibilityValue: editor.overlayPosition.rawValue) {
                    Text(editor.overlayPosition.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(CanvasColor.tertiary(scheme))
                }
            }
            .buttonStyle(CanvasPressStyle())
        }
    }

    private var videoCaptionTools: some View {
        CanvasEditorSection(
            title: "字幕",
            detail: editor.captions.isEmpty ? "未添加" : "\(editor.captions.count) 条"
        ) {
            CanvasPlainRow("字幕内容") {
                TextField("输入字幕", text: $captionDraft)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
            }
            CanvasHairline()
            CanvasEditorSlider(
                title: "持续时间",
                value: $captionDuration,
                range: 0.5...12,
                valueText: String(format: "%.1f 秒", captionDuration)
            )
            CanvasHairline()
            CanvasEditorAction(title: "添加到 \(editor.timecode(playback.time))", glyph: .plus) {
                let text = captionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    showNotice("请先输入字幕内容。", error: true)
                    return
                }
                editor.addCaption(text: text, at: playback.time, duration: captionDuration)
                captionDraft = ""
            }
            ForEach(editor.captions) { caption in
                CanvasHairline()
                HStack(spacing: 12) {
                    Text(editor.timecode(caption.start))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CanvasColor.tertiary(scheme))
                    Text(caption.text)
                        .font(.subheadline)
                        .foregroundStyle(CanvasColor.ink(scheme))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button(role: .destructive) { editor.deleteCaption(caption.id) } label: {
                        CanvasGlyph(.trash, size: 18)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(CanvasPressStyle())
                    .accessibilityLabel("删除字幕 \(caption.text)")
                }
                .frame(minHeight: 52)
            }
        }
    }

    private var videoAudioTools: some View {
        CanvasEditorSection(
            title: "音轨",
            detail: editor.audioTracks.isEmpty ? "片段原声" : "\(editor.audioTracks.count) 条背景音"
        ) {
            Toggle("静音当前片段", isOn: $editor.isMuted)
                .frame(minHeight: 50)
                .tint(CanvasColor.accent(scheme))
            CanvasHairline()
            CanvasEditorSlider(
                title: "片段音量",
                value: $editor.volume,
                range: 0...2,
                valueText: "\(Int(editor.volume * 100))%"
            )
            CanvasHairline()
            CanvasEditorAction(title: "导入背景音轨", glyph: .plus) { importingAudio = true }
            ForEach(editor.audioTracks) { track in
                CanvasHairline()
                HStack(spacing: 12) {
                    CanvasGlyph(.audio, size: 19)
                        .foregroundStyle(CanvasColor.accent(scheme))
                    Text(track.name)
                        .font(.subheadline)
                        .foregroundStyle(CanvasColor.ink(scheme))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button(role: .destructive) { editor.deleteAudioTrack(track.id) } label: {
                        CanvasGlyph(.trash, size: 18).frame(width: 44, height: 44)
                    }
                    .buttonStyle(CanvasPressStyle())
                    .accessibilityLabel("删除音轨 \(track.name)")
                }
                .frame(minHeight: 52)
            }
        }
    }

    private var videoExportTools: some View {
        CanvasEditorSection(title: "导出", detail: outputURL == nil ? "视频文件" : "已生成") {
            Menu {
                ForEach(VideoExportSize.allCases) { size in
                    Button(size.rawValue) { editor.exportSize = size }
                }
            } label: {
                CanvasPlainRow("尺寸", accessibilityValue: editor.exportSize.rawValue) {
                    Text(editor.exportSize.rawValue).foregroundStyle(CanvasColor.tertiary(scheme))
                }
            }
            .buttonStyle(CanvasPressStyle())
            CanvasHairline()
            Menu {
                ForEach(VideoExportCodec.allCases) { codec in
                    Button(codec.rawValue) { editor.exportCodec = codec }
                }
            } label: {
                CanvasPlainRow("编码", accessibilityValue: editor.exportCodec.rawValue) {
                    Text(editor.exportCodec.rawValue).foregroundStyle(CanvasColor.tertiary(scheme))
                }
            }
            .buttonStyle(CanvasPressStyle())
            CanvasHairline()
            Menu {
                ForEach([0, 24, 30, 60], id: \.self) { fps in
                    Button(fps == 0 ? "保持原始" : "\(fps) fps") { editor.exportFrameRate = fps }
                }
            } label: {
                CanvasPlainRow("帧率", accessibilityValue: exportFrameRateTitle) {
                    Text(exportFrameRateTitle).foregroundStyle(CanvasColor.tertiary(scheme))
                }
            }
            .buttonStyle(CanvasPressStyle())
            CanvasHairline()
            exportProgress(value: editor.exportProgress, active: editor.isExporting)
            Button {
                Task { await exportVideo() }
            } label: {
                CanvasExportLabel(
                    title: editor.isExporting ? "正在导出" : "导出视频",
                    active: editor.isExporting
                )
            }
            .buttonStyle(CanvasPressStyle())
            .disabled(editor.isExporting)
            .accessibilityIdentifier("canvas.videoEditor.export")

            if let outputURL {
                ShareLink(item: outputURL) {
                    CanvasShareReadyLabel(fileName: outputURL.lastPathComponent)
                }
                .buttonStyle(CanvasPressStyle())
                .accessibilityIdentifier("canvas.videoEditor.share")
            }
        }
    }

    @ViewBuilder private var noticeView: some View {
        if let notice {
            CanvasInlineNotice(message: notice.message, tone: notice.isError ? .error : .info)
                .id(notice.id)
                .transition(.opacity)
        }
    }

    private var visibleCaption: TimedCaption? {
        editor.captions.last {
            playback.time >= $0.start && playback.time <= $0.start + $0.duration
        }
    }

    private var exportFrameRateTitle: String {
        editor.exportFrameRate == 0 ? "保持原始" : "\(editor.exportFrameRate) fps"
    }

    private func captionAlignment(_ position: VideoTextPosition) -> Alignment {
        switch position {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
    }

    private func exportProgress(value: Double, active: Bool) -> some View {
        Group {
            if active {
                VStack(spacing: 7) {
                    ProgressView(value: value).tint(CanvasColor.accent(scheme))
                    Text("正在生成 \(Int(value * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CanvasColor.tertiary(scheme))
                }
                .padding(.vertical, 10)
            }
        }
    }

    private func receiveBackgroundAudio(_ result: Result<[URL], Error>) {
        Task {
            do {
                guard let url = try result.get().first else { return }
                try await editor.addBackgroundAudio(url: url)
                showNotice("背景音轨已添加。")
            } catch {
                showNotice(error.localizedDescription, error: true)
            }
        }
    }

    @MainActor private func exportVideo() async {
        do {
            outputURL = try await editor.export()
            showNotice("视频已生成，可以分享或保存。")
        } catch {
            showNotice(error.localizedDescription, error: true)
        }
    }

    private func showNotice(_ message: String, error: Bool = false) {
        let next = CanvasEditorNotice(message: message, isError: error)
        if reduceMotion { notice = next }
        else { withAnimation(.easeOut(duration: 0.16)) { notice = next } }
    }
}

// MARK: - Audio editor

struct CanvasAudioEditorView: View {
    private enum Tool: String, CaseIterable, Identifiable {
        case clips = "片段"
        case tone = "音色"
        case cleanup = "降噪"
        case lyrics = "歌词"
        case export = "导出"

        var id: String { rawValue }
        var glyph: CanvasGlyphName {
            switch self {
            case .clips: .trim
            case .tone: .waveform
            case .cleanup: .refresh
            case .lyrics: .document
            case .export: .export
            }
        }
    }

    @StateObject private var editor: AudioEditor
    @StateObject private var playback: CanvasPlaybackController
    @State private var selectedTool: Tool = .clips
    @State private var importingLyrics = false
    @State private var outputURL: URL?
    @State private var notice: CanvasEditorNotice?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(recording: AudioRecording) {
        _editor = StateObject(wrappedValue: AudioEditor(sourceURL: recording.url, duration: recording.duration))
        _playback = StateObject(wrappedValue: CanvasPlaybackController(url: recording.url))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                audioStage
                audioTimeline.padding(.top, 18)
                audioTransport.padding(.top, 18)
                audioToolStrip.padding(.top, 24)
                audioNotice.padding(.top, notice == nil ? 0 : 14)
                activeAudioTool.padding(.top, 22)
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
        .background(CanvasBackdrop())
        .navigationTitle("音频编辑")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $importingLyrics,
            allowedContentTypes: lyricTypes,
            allowsMultipleSelection: false,
            onCompletion: receiveLyrics
        )
        .task { await editor.loadWaveform() }
        .onChange(of: editor.selectedClipID) { _, _ in
            playback.seek(to: editor.trimStart)
        }
        .onDisappear { playback.pause() }
        .accessibilityIdentifier("canvas.audioEditor.page")
    }

    private var audioStage: some View {
        VStack(spacing: 24) {
            HStack {
                HStack(spacing: 7) {
                    Circle()
                        .fill(playback.isPlaying ? CanvasColor.coral : CanvasColor.accent(scheme))
                        .frame(width: 6, height: 6)
                    Text(playback.isPlaying ? "正在播放" : "音频预览")
                }
                Spacer()
                Text(audioTimecode(editor.selectedDuration))
                    .monospacedDigit()
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(CanvasColor.tertiary(scheme))
            .padding(.top, 24)

            CanvasEditableWaveform(
                samples: editor.waveform,
                progress: playback.time / max(editor.duration, 0.1),
                selectedRange: editor.trimStart...editor.trimEnd,
                duration: editor.duration
            )
            .frame(height: 118)
            .accessibilityLabel("音频波形")
            .accessibilityValue("播放位置 \(audioTimecode(playback.time))")

            Text(audioTimecode(playback.time))
                .font(.system(.title2, design: .rounded).monospacedDigit())
                .foregroundStyle(CanvasColor.ink(scheme))
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas.audioEditor.stage")
    }

    private var audioTimeline: some View {
        VStack(spacing: 10) {
            Slider(
                value: Binding(get: { playback.time }, set: { playback.seek(to: $0) }),
                in: 0...max(editor.duration, 0.1),
                step: 0.01
            )
            .tint(CanvasColor.accent(scheme))
            .frame(minHeight: 44)
            .accessibilityLabel("播放位置")
            .accessibilityValue(audioTimecode(playback.time))

            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(Array(editor.clips.enumerated()), id: \.element.id) { index, clip in
                        Button { editor.selectClip(clip.id) } label: {
                            HStack(spacing: 6) {
                                Text("\(index + 1)").font(.caption2.monospacedDigit().weight(.semibold))
                                Text(audioTimecode(clip.duration)).font(.caption2.monospacedDigit())
                            }
                            .foregroundStyle(
                                clip.id == editor.selectedClipID
                                    ? CanvasColor.background(scheme)
                                    : CanvasColor.ink(scheme)
                            )
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(
                                clip.id == editor.selectedClipID
                                    ? CanvasColor.accent(scheme)
                                    : CanvasColor.elevated(scheme),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(CanvasPressStyle())
                        .accessibilityLabel("片段 \(index + 1)，\(audioTimecode(clip.duration))")
                        .accessibilityAddTraits(clip.id == editor.selectedClipID ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var audioTransport: some View {
        CanvasGlassSurface(cornerRadius: 28) {
            HStack(spacing: 0) {
                audioTransportButton("撤销", glyph: .undo, enabled: editor.canUndo) { editor.undo() }
                Spacer(minLength: 8)
                Button {
                    playback.toggle(range: editor.trimStart...editor.trimEnd)
                } label: {
                    ZStack {
                        Circle().fill(CanvasColor.accent(scheme)).frame(width: 52, height: 52)
                        CanvasGlyph(playback.isPlaying ? .pause : .play, size: 22, weight: 2)
                            .foregroundStyle(CanvasColor.background(scheme))
                    }
                    .frame(width: 60, height: 60)
                    .contentShape(Circle())
                }
                .buttonStyle(CanvasPressStyle())
                .accessibilityLabel(playback.isPlaying ? "暂停" : "播放")
                .accessibilityIdentifier("canvas.audioEditor.play")
                Spacer(minLength: 8)
                audioTransportButton("重做", glyph: .redo, enabled: editor.canRedo) { editor.redo() }
            }
            .padding(.horizontal, 12)
            .frame(width: 264, height: 64)
        }
        .frame(maxWidth: .infinity)
    }

    private func audioTransportButton(
        _ title: String,
        glyph: CanvasGlyphName,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                CanvasGlyph(glyph, size: 18)
                Text(title).font(.caption2.weight(.medium))
            }
            .foregroundStyle(CanvasColor.secondary(scheme))
            .frame(width: 58)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(CanvasPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }

    private var audioToolStrip: some View {
        HStack(spacing: 0) {
            ForEach(Tool.allCases) { tool in
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { selectedTool = tool }
                } label: {
                    VStack(spacing: 5) {
                        CanvasGlyph(tool.glyph, size: 19)
                        Text(tool.rawValue).font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(
                        selectedTool == tool
                            ? CanvasColor.accent(scheme)
                            : CanvasColor.secondary(scheme)
                    )
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(CanvasPressStyle())
                .accessibilityAddTraits(selectedTool == tool ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) { CanvasHairline() }
    }

    @ViewBuilder private var activeAudioTool: some View {
        switch selectedTool {
        case .clips: audioClipTools
        case .tone: audioToneTools
        case .cleanup: audioCleanupTools
        case .lyrics: audioLyricsTools
        case .export: audioExportTools
        }
    }

    private var audioClipTools: some View {
        CanvasEditorSection(title: "片段", detail: "\(editor.clips.count) 段") {
            CanvasEditorSlider(
                title: "入点",
                value: Binding(get: { editor.trimStart }, set: { editor.setTrimStart($0) }),
                range: 0...max(editor.duration, 0.1),
                valueText: audioTimecode(editor.trimStart)
            )
            CanvasHairline()
            CanvasEditorSlider(
                title: "出点",
                value: Binding(get: { editor.trimEnd }, set: { editor.setTrimEnd($0) }),
                range: 0...max(editor.duration, 0.1),
                valueText: audioTimecode(editor.trimEnd)
            )
            CanvasHairline()
            CanvasEditorSlider(
                title: "速度",
                value: $editor.speed,
                range: 0.25...4,
                valueText: String(format: "%.2f×", editor.speed)
            )
            CanvasHairline()
            CanvasEditorSlider(
                title: "音量",
                value: $editor.volume,
                range: 0...2,
                valueText: "\(Int(editor.volume * 100))%"
            )
            CanvasHairline()
            CanvasEditorActionGrid {
                CanvasEditorAction(title: "分割", glyph: .trim) {
                    if !editor.split(at: playback.time) { showAudioNotice("当前位置无法分割。", error: true) }
                }
                CanvasEditorAction(title: "复制", glyph: .plus) { editor.duplicateSelectedClip() }
                CanvasEditorAction(title: "删除", glyph: .trash, destructive: true) { editor.deleteSelectedClip() }
                    .disabled(!editor.canDeleteClip)
            }
        }
    }

    private var audioToneTools: some View {
        CanvasEditorSection(title: "音色", detail: editor.hasAudioEffects ? "已调整" : "原声") {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(AudioEQPreset.allCases) { preset in
                        CanvasChoiceChip(preset.rawValue, selected: false) { editor.applyEQPreset(preset) }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.vertical, 10)
            CanvasHairline()
            CanvasEditorSlider(
                title: "低频",
                value: $editor.bassGain,
                range: -12...12,
                valueText: String(format: "%+.1f dB", editor.bassGain)
            )
            CanvasHairline()
            CanvasEditorSlider(
                title: "中频",
                value: $editor.midGain,
                range: -12...12,
                valueText: String(format: "%+.1f dB", editor.midGain)
            )
            CanvasHairline()
            CanvasEditorSlider(
                title: "高频",
                value: $editor.trebleGain,
                range: -12...12,
                valueText: String(format: "%+.1f dB", editor.trebleGain)
            )
            CanvasHairline()
            CanvasEditorSlider(
                title: "音高",
                value: $editor.pitchSemitones,
                range: -12...12,
                valueText: String(format: "%+.0f", editor.pitchSemitones)
            )
            CanvasHairline()
            CanvasEditorAction(title: editor.isRenderingPreview ? "正在生成试听" : "试听处理效果", glyph: .play) {
                Task { await previewAudioEffects() }
            }
            .disabled(editor.isRenderingPreview)
        }
    }

    private var audioCleanupTools: some View {
        CanvasEditorSection(title: "降噪", detail: "保留人声细节") {
            CanvasEditorSlider(
                title: "降噪强度",
                value: $editor.noiseReduction,
                range: 0...1,
                valueText: "\(Int(editor.noiseReduction * 100))%"
            )
            CanvasHairline()
            CanvasEditorAction(
                title: editor.isAnalyzingNoise ? "正在识别噪声" : "自动匹配降噪",
                glyph: .refresh
            ) { Task { await editor.autoTuneNoiseReduction() } }
            .disabled(editor.isAnalyzingNoise)
            CanvasHairline()
            CanvasEditorAction(
                title: editor.isAnalyzingSilence ? "正在分析静音" : "检测静音片段",
                glyph: .waveform
            ) { Task { await editor.analyzeSilence() } }
            .disabled(editor.isAnalyzingSilence)
            CanvasHairline()
            CanvasEditorAction(
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
                CanvasInlineNotice(message: error, tone: .warning).padding(.top, 8)
            }
        }
    }

    private var audioLyricsTools: some View {
        CanvasEditorSection(
            title: "歌词",
            detail: editor.lyrics.isEmpty ? "未导入" : "\(editor.lyrics.count) 行"
        ) {
            CanvasEditorAction(title: "导入歌词", glyph: .plus) { importingLyrics = true }
            CanvasHairline()
            CanvasEditorAction(title: "在 \(audioTimecode(playback.time)) 添加一行", glyph: .document) {
                _ = editor.addLyric(at: playback.time)
            }
            ForEach(editor.lyrics) { line in
                CanvasHairline()
                VStack(spacing: 8) {
                    HStack {
                        Button(audioTimecode(line.time ?? 0)) {
                            editor.setLyricTime(line.id, to: playback.time)
                        }
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(CanvasColor.accent(scheme))
                        .frame(minWidth: 54, minHeight: 44)
                        .buttonStyle(CanvasPressStyle())

                        TextField(
                            "歌词内容",
                            text: Binding(
                                get: { editor.lyrics.first(where: { $0.id == line.id })?.text ?? line.text },
                                set: { editor.updateLyric(line.id, text: $0) }
                            )
                        )
                        .textFieldStyle(.plain)

                        Button(role: .destructive) { editor.deleteLyric(line.id) } label: {
                            CanvasGlyph(.trash, size: 18).frame(width: 44, height: 44)
                        }
                        .buttonStyle(CanvasPressStyle())
                        .accessibilityLabel("删除歌词 \(line.text)")
                    }
                }
                .frame(minHeight: 52)
            }
            if !editor.lyrics.isEmpty {
                CanvasHairline()
                CanvasEditorAction(title: "保存歌词文件", glyph: .download) {
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
        CanvasEditorSection(title: "导出", detail: outputURL == nil ? "音频文件" : "已生成") {
            Menu {
                ForEach(editor.availableFormats) { format in
                    Button(format.rawValue) { editor.exportFormat = format }
                }
            } label: {
                CanvasPlainRow("格式", accessibilityValue: editor.exportFormat.rawValue) {
                    Text(editor.exportFormat.rawValue).foregroundStyle(CanvasColor.tertiary(scheme))
                }
            }
            .buttonStyle(CanvasPressStyle())
            CanvasHairline()
            Menu {
                ForEach(AudioExportBitrate.allCases) { bitrate in
                    Button(bitrate.title) { editor.exportBitrate = bitrate }
                }
            } label: {
                CanvasPlainRow("码率", accessibilityValue: editor.exportBitrate.title) {
                    Text(editor.exportBitrate.title).foregroundStyle(CanvasColor.tertiary(scheme))
                }
            }
            .buttonStyle(CanvasPressStyle())
            CanvasHairline()
            Menu {
                ForEach([44_100, 48_000], id: \.self) { rate in
                    Button("\(rate / 1_000) kHz") { editor.exportSampleRate = rate }
                }
            } label: {
                CanvasPlainRow("采样率", accessibilityValue: "\(editor.exportSampleRate / 1_000) 千赫兹") {
                    Text("\(editor.exportSampleRate / 1_000) kHz").foregroundStyle(CanvasColor.tertiary(scheme))
                }
            }
            .buttonStyle(CanvasPressStyle())
            CanvasHairline()
            if editor.isExporting {
                VStack(spacing: 7) {
                    ProgressView(value: editor.exportProgress).tint(CanvasColor.accent(scheme))
                    Text("正在生成 \(Int(editor.exportProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CanvasColor.tertiary(scheme))
                }
                .padding(.vertical, 10)
            }
            Button { Task { await exportAudio() } } label: {
                CanvasExportLabel(
                    title: editor.isExporting ? "正在导出" : "导出音频",
                    active: editor.isExporting
                )
            }
            .buttonStyle(CanvasPressStyle())
            .disabled(editor.isExporting)
            .accessibilityIdentifier("canvas.audioEditor.export")

            if let outputURL {
                ShareLink(item: outputURL) {
                    CanvasShareReadyLabel(fileName: outputURL.lastPathComponent)
                }
                .buttonStyle(CanvasPressStyle())
                .accessibilityIdentifier("canvas.audioEditor.share")
            }
        }
    }

    @ViewBuilder private var audioNotice: some View {
        if let notice {
            CanvasInlineNotice(message: notice.message, tone: notice.isError ? .error : .info)
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
        let next = CanvasEditorNotice(message: message, isError: error)
        if reduceMotion { notice = next }
        else { withAnimation(.easeOut(duration: 0.16)) { notice = next } }
    }

    private func audioTimecode(_ time: Double) -> String {
        let value = max(0, Int(time.rounded(.down)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

// MARK: - Shared editor pieces

@MainActor
private final class CanvasPlaybackController: ObservableObject {
    let player: AVPlayer
    @Published private(set) var time: Double = 0
    @Published private(set) var isPlaying = false

    private var clockTask: Task<Void, Never>?
    private var playbackRange: ClosedRange<Double>?

    init(url: URL) {
        player = AVPlayer(url: url)
    }

    func replace(with url: URL) {
        pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        seek(to: 0)
    }

    func toggle(range: ClosedRange<Double>) {
        if isPlaying { pause() }
        else { play(range: range) }
    }

    func play(range: ClosedRange<Double>) {
        playbackRange = range
        if time < range.lowerBound || time >= range.upperBound - 0.02 {
            seek(to: range.lowerBound)
        }
        player.play()
        isPlaying = true
        startClock()
    }

    func pause() {
        player.pause()
        isPlaying = false
        clockTask?.cancel()
        clockTask = nil
    }

    func seek(to seconds: Double) {
        let value = max(0, seconds)
        player.seek(
            to: CMTime(seconds: value, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        time = value
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { return }
                let seconds = player.currentTime().seconds
                if seconds.isFinite { time = max(0, seconds) }
                if let playbackRange, time >= playbackRange.upperBound - 0.015 {
                    pause()
                    seek(to: playbackRange.lowerBound)
                    return
                }
            }
        }
    }
}

private struct CanvasVideoFilmstrip: View {
    let frames: [VideoTimelineFrame]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            if frames.isEmpty {
                HStack(spacing: 1) {
                    ForEach(0..<8, id: \.self) { index in
                        LinearGradient(
                            colors: [
                                CanvasColor.elevated(scheme),
                                CanvasColor.secondary(scheme).opacity(0.14 + Double(index % 3) * 0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: max(36, proxy.size.width / 8))
                    }
                }
            } else {
                HStack(spacing: 1) {
                    ForEach(frames) { frame in
                        Image(uiImage: frame.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: max(34, proxy.size.width / CGFloat(max(frames.count, 1))))
                            .clipped()
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CanvasEditableWaveform: View {
    let samples: [Float]
    let progress: Double
    let selectedRange: ClosedRange<Double>
    let duration: Double

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        SwiftUI.Canvas { context, size in
            let values = samples.isEmpty ? placeholder : samples
            let gap = size.width / CGFloat(max(values.count - 1, 1))
            let midY = size.height / 2
            let startX = size.width * selectedRange.lowerBound / max(duration, 0.1)
            let endX = size.width * selectedRange.upperBound / max(duration, 0.1)

            context.fill(
                Path(CGRect(x: startX, y: 0, width: max(0, endX - startX), height: size.height)),
                with: .color(CanvasColor.accent(scheme).opacity(0.055))
            )

            for (index, sample) in values.enumerated() {
                let x = CGFloat(index) * gap
                let amplitude = max(2, min(1, CGFloat(abs(sample))) * size.height * 0.44)
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: midY - amplitude))
                tick.addLine(to: CGPoint(x: x, y: midY + amplitude))
                context.stroke(
                    tick,
                    with: .color(CanvasColor.secondary(scheme).opacity(0.52)),
                    style: StrokeStyle(lineWidth: index.isMultiple(of: 9) ? 1.35 : 0.8, lineCap: .round)
                )
            }

            let playheadX = size.width * min(1, max(0, progress))
            var playhead = Path()
            playhead.move(to: CGPoint(x: playheadX, y: 0))
            playhead.addLine(to: CGPoint(x: playheadX, y: size.height))
            context.stroke(playhead, with: .color(CanvasColor.coral), lineWidth: 1.5)
        }
    }

    private var placeholder: [Float] {
        (0..<96).map { index in
            Float(0.14 + abs(sin(Double(index) * 0.37)) * (index.isMultiple(of: 5) ? 0.72 : 0.42))
        }
    }
}

private struct CanvasEditorSection<Content: View>: View {
    let title: String
    let detail: String
    private let content: Content

    @Environment(\.colorScheme) private var scheme

    init(title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer(minLength: 12)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(CanvasColor.tertiary(scheme))
            }
            .foregroundStyle(CanvasColor.ink(scheme))
            .padding(.bottom, 10)
            content
        }
        .accessibilityElement(children: .contain)
    }
}

private struct CanvasEditorSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var valueText: String?

    @Environment(\.colorScheme) private var scheme

    init(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueText: String? = nil
    ) {
        self.title = title
        _value = value
        self.range = range
        self.valueText = valueText
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(valueText ?? String(format: "%.2f", value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CanvasColor.tertiary(scheme))
            }
            Slider(value: $value, in: range)
                .tint(CanvasColor.accent(scheme))
                .frame(minHeight: 44)
        }
        .foregroundStyle(CanvasColor.ink(scheme))
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }
}

private struct CanvasEditorAction: View {
    let title: String
    let glyph: CanvasGlyphName
    var destructive = false
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                CanvasGlyph(glyph, size: 18)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
            }
            .foregroundStyle(destructive ? CanvasColor.danger(scheme) : CanvasColor.ink(scheme))
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(CanvasPressStyle())
        .accessibilityLabel(title)
    }
}

private struct CanvasEditorActionGrid<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content }
            VStack(spacing: 0) { content }
        }
        .padding(.vertical, 4)
    }
}

private struct CanvasChoiceChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    init(_ title: String, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.selected = selected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(selected ? CanvasColor.background(scheme) : CanvasColor.ink(scheme))
                .padding(.horizontal, 13)
                .frame(minHeight: 44)
                .background(
                    selected ? CanvasColor.accent(scheme) : CanvasColor.elevated(scheme),
                    in: Capsule()
                )
        }
        .buttonStyle(CanvasPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct CanvasExportLabel: View {
    let title: String
    let active: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 9) {
            if active { ProgressView().tint(CanvasColor.background(scheme)) }
            else { CanvasGlyph(.export, size: 19) }
            Text(title).font(.body.weight(.semibold))
        }
        .foregroundStyle(CanvasColor.background(scheme))
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(CanvasColor.accent(scheme), in: Capsule())
        .padding(.top, 12)
    }
}

private struct CanvasShareReadyLabel: View {
    let fileName: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 11) {
            CanvasGlyph(.check, size: 20)
                .foregroundStyle(CanvasColor.accent(scheme))
            VStack(alignment: .leading, spacing: 2) {
                Text("导出成功")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CanvasColor.ink(scheme))
                Text(fileName)
                    .font(.caption)
                    .foregroundStyle(CanvasColor.tertiary(scheme))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            CanvasGlyph(.share, size: 19)
                .foregroundStyle(CanvasColor.accent(scheme))
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .contentShape(Rectangle())
        .padding(.top, 4)
    }
}

private struct CanvasEditorNotice: Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
}
