import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Video editor

struct PearlVideoEditorView: View {
    private enum Tool: String, CaseIterable, Identifiable {
        case clips = "剪切"
        case transitions = "转场"
        case motion = "运动"
        case look = "调色"
        case canvas = "画布"
        case captions = "字幕"
        case audio = "音轨"
        case privacy = "遮挡"

        var id: String { rawValue }
        var glyph: PearlGlyphName {
            switch self {
            case .clips: .trim
            case .transitions: .redo
            case .motion: .orientation
            case .look: .image
            case .canvas: .orientation
            case .captions: .captions
            case .audio: .audio
            case .privacy: .shield
            }
        }
    }

    @StateObject private var editor: VideoEditor
    @StateObject private var playback: PearlPlaybackController
    @StateObject private var compressor = MediaTranscoder()
    @State private var selectedTool: Tool?
    @State private var previewReady = false
    @State private var refreshingPreview = false
    @State private var importingVideo = false
    @State private var livePhotoItem: PearlExportItem?
    @State private var selectedCaptionID: UUID?
    @State private var selectedMaskID: UUID?
    @State private var maskDragOrigin: VideoRedaction?
    @State private var transcribing = false
    @State private var transcriptionStatus = ""
    @State private var speechLocale = "zh-CN"
    @State private var transcriptionTask: Task<Void, Never>?
    @State private var compressEnabled = false
    @State private var targetMB = 20.0
    @State private var compressing = false
    @State private var exportSummary = ""

    @State private var showingExport = false
    @State private var showingFullPreview = false
    @State private var isMakingLivePhoto = false
    @State private var fileExport: PearlExportItem?
    @State private var subtitleExport: PearlExportItem?
    private let recording: Recording
    @State private var captionDraft = ""
    @State private var captionDuration = 3.0
    @State private var importingAudio = false
    @State private var outputURL: URL?
    @State private var notice: PearlEditorNotice?

    private var scheme: ColorScheme { .dark }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(recording: Recording) {
        self.recording = recording
        _editor = StateObject(wrappedValue: VideoEditor(sourceURL: recording.url, duration: recording.duration))
        _playback = StateObject(wrappedValue: PearlPlaybackController(url: recording.url))
    }

    var body: some View {
        GeometryReader { container in
            let wide = container.size.width > 650 && container.size.width > container.size.height
            VStack(spacing: 0) {
                studioHeader
                if wide {
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            mediaCanvas.frame(maxHeight: .infinity).padding(.horizontal, 12).padding(.top, 4)
                            transport
                        }
                        Divider()
                        ScrollView { activeTool.padding(16) }.frame(width: min(300, container.size.width * 0.36)).background(Color(white: 0.085))
                    }.frame(maxHeight: .infinity)
                    timeline(height: 92, compact: true)
                } else {
                    workspace()
                    if selectedTool != nil {
                        VStack(spacing: 0) {
                            HStack {
                                Text(selectedTool?.rawValue ?? "").font(.caption.bold())
                                Spacer()
                                Button { selectedTool = nil } label: {
                                    Image(systemName: "checkmark").frame(width: 44, height: 44)
                                }.accessibilityLabel("完成工具编辑")
                            }.padding(.horizontal, 16)
                            ScrollView { activeTool.padding(.horizontal, 18).padding(.bottom, 12) }
                        }
                        .frame(height: selectedTool == .transitions ? min(350, container.size.height * 0.44) : min(265, container.size.height * 0.34))
                        .background(Color(white: 0.095))
                        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.09)).frame(height: 0.5) }
                        .accessibilityIdentifier("pearl.videoEditor.toolSheet")
                    }
                }
                toolStrip(compact: wide)
            }
        }
        .background(Color(white: 0.055)).foregroundStyle(.white)
        .environment(\.colorScheme, .dark).preferredColorScheme(.dark)
        .environment(\.studioEditingGesture, { $0 ? editor.beginContinuousEdit() : editor.endContinuousEdit() })
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .tint(Color(red: 1, green: 0.36, blue: 0.16))
        .sheet(isPresented: $showingExport) {
            PearlSecondaryLayout(title: "导出视频") {
                PearlPage(maxWidth: 660) {
                    VStack(spacing: 20) { videoExportTools; noticeView }
                }
            }
            .interactiveDismissDisabled(isExportBusy)
            .sheet(item: $fileExport) { PearlFileExporter(url: $0.url) }
            .sheet(item: $livePhotoItem) { PearlLivePhotoEditor(url: $0.url) }
        }
        .fullScreenCover(isPresented: $showingFullPreview) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                VideoPlayer(player: playback.player).ignoresSafeArea()
                Button {
                    let time = playback.player.currentTime().seconds
                    playback.pause(); if time.isFinite { playback.seek(to: time) }; showingFullPreview = false
                } label: {
                    Image(systemName: "xmark").font(.title3).padding(14).background(.black.opacity(0.7), in: Circle())
                }.padding(20).accessibilityLabel("退出全屏预览")
            }.preferredColorScheme(.dark)
        }
        .sheet(item: $subtitleExport) { PearlFileExporter(url: $0.url) }
        .fileImporter(isPresented: $importingVideo, allowedContentTypes: [.movie], allowsMultipleSelection: true) { result in
            Task {
                do {
                    let urls = try result.get().map { try EditorMediaImport.copy($0) }
                    try await editor.addClips(urls: urls)
                } catch { showNotice(error.localizedDescription, error: true) }
            }
        }
        .task(id: editor.selectedSourceURL) { await editor.loadFFmpegPreview() }
        .task(id: editor.revision) { await refreshPreview() }
        .onDisappear {
            playback.pause(); transcriptionTask?.cancel(); editor.saveDraft()
        }
    }

    private func workspace(timelineHeight: CGFloat = 170) -> some View {
        VStack(spacing: 0) {
            mediaCanvas.frame(maxHeight: .infinity).padding(.horizontal, 12).padding(.top, 6)
            transport
            timeline(height: timelineHeight)
            if let error = editor.draftError {
                Text(error).font(.caption).foregroundStyle(.orange).padding(8)
            }
            if !showingExport { noticeView.padding(.horizontal, 12).lineLimit(3) }
        }
        .disabled(isExportBusy || transcribing)
    }

    private func timeline(height: CGFloat, compact: Bool = false) -> some View {
        ScrollView(.vertical) {
            PearlProjectTimeline(editor: editor, playback: playback, selectCaption: { id in
                selectedCaptionID = id; selectedTool = .captions
            }, selectMask: { id in
                selectedMaskID = id; selectedTool = .privacy
            }, addMedia: { importingVideo = true }, selectTransition: { id in
                editor.selectClip(id); selectedTool = .transitions
            }, compact: compact)
        }.frame(height: height).scrollIndicators(.hidden)
    }

    private var canvasAspect: CGFloat {
        if let ratio = editor.canvasRatio.value { return ratio }
        guard let info = editor.videoInfo, info.height > 0 else { return 3 / 4 }
        let ratio = CGFloat(info.width) / CGFloat(info.height)
        return editor.rotationSteps % 2 == 0 ? ratio : 1 / ratio
    }

    private var mediaCanvas: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, geometry.size.height * canvasAspect)
            let height = width / canvasAspect
            ZStack {
                Color.black
                PearlPlayerSurface(player: playback.player).allowsHitTesting(false)
                if let mask = editor.redactions.first(where: { $0.id == selectedMaskID }),
                   selectedTool == .privacy,
                   playback.time >= mask.start, playback.time < mask.start + mask.duration {
                    Rectangle().stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        .background(.orange.opacity(0.08))
                        .frame(width: width * mask.width, height: height * mask.height)
                        .position(x: width * (mask.x + mask.width / 2), y: height * (mask.y + mask.height / 2))
                        .gesture(DragGesture().onChanged { drag in
                            if maskDragOrigin == nil { editor.checkpoint(); maskDragOrigin = mask }
                            guard var value = maskDragOrigin else { return }
                            value.x += drag.translation.width / max(width, 1)
                            value.y += drag.translation.height / max(height, 1)
                            editor.updateRedaction(value, recordUndo: false)
                        }.onEnded { _ in maskDragOrigin = nil })
                        .accessibilityLabel("拖动遮挡区域，也可使用下方位置滑块")
                }
                if refreshingPreview || !previewReady {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(refreshingPreview ? "正在更新预览" : "预览尚未就绪").font(.caption2)
                    }.padding(12).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(width: width, height: height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .overlay(alignment: .topTrailing) {
            Button { playback.pause(); showingFullPreview = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 12)).frame(width: 44, height: 44)
                    .background(.black.opacity(0.35), in: Circle())
            }.disabled(!previewReady || refreshingPreview).accessibilityLabel("全屏预览")
        }
        .accessibilityIdentifier("pearl.videoEditor.preview")
    }

    private var studioHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 16, weight: .medium)).frame(width: 44, height: 44) }
                .accessibilityLabel("返回")
            VStack(alignment: .leading, spacing: 3) {
                Text("编辑台").font(.system(size: 16, weight: .semibold))
                Text("MONOFRAME  /  STUDIO").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(editor.exportFrameRate > 0 ? editor.exportFrameRate : Int(editor.frameRate)) FPS")
                .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            Button { showingExport = true } label: {
                HStack(spacing: 6) { Text("导出"); Image(systemName: "arrow.up.right") }.font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black).padding(.horizontal, 16).frame(height: 38)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 8))
            }.frame(minHeight: 44).accessibilityIdentifier("pearl.videoEditor.openExport")
        }.padding(.trailing, 16).padding(.vertical, 6)
            .background(Color(white: 0.075))
            .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5) }
    }

    private var transport: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(editor.timecode(playback.time)).foregroundStyle(.white)
                Text(editor.timecode(editor.projectDuration)).foregroundStyle(.secondary)
            }.font(.system(size: 10, weight: .medium, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
            Button { stepFrame(-1) } label: { Image(systemName: "backward.end").frame(width: 40, height: 44) }.accessibilityLabel("上一帧")
            Button { playback.toggle(range: 0...editor.projectDuration) } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
            }.disabled(!previewReady || refreshingPreview)
                .accessibilityLabel(playback.isPlaying ? "暂停" : "播放").accessibilityIdentifier("pearl.videoEditor.play")
            Button { stepFrame(1) } label: { Image(systemName: "forward.end").frame(width: 40, height: 44) }.accessibilityLabel("下一帧")
            Spacer(minLength: 4)
            Button { editor.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 40, height: 44) }
                .disabled(!editor.canUndo).accessibilityLabel("撤销")
            Button { editor.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 40, height: 44) }
                .disabled(!editor.canRedo).accessibilityLabel("重做")
        }.font(.system(size: 14)).padding(.horizontal, 16)
    }
    private func stepFrame(_ direction: Double) {
        playback.pause(); playback.seek(to: min(editor.projectDuration, max(0, playback.time + direction * editor.frameDuration)))
    }
    private func toolSymbol(_ tool: Tool) -> String {
        switch tool {
        case .clips: "crop.rotate"
        case .look: "slider.horizontal.3"
        case .canvas: "aspectratio"
        case .captions: "textformat"
        case .audio: "waveform"
        case .privacy: "rectangle.dashed"
        case .transitions: "square.on.square"
        case .motion: "diamond"
        }
    }
    private var preciseTrimControls: some View {
        VStack(spacing: 2) {
            ForEach(TrimBoundary.allCases) { boundary in
                HStack {
                    Text("\(boundary.rawValue)逐帧").font(.caption)
                    Spacer()
                    Button { editor.checkpoint(); editor.step(boundary, frames: -1) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }.accessibilityLabel("\(boundary.rawValue)前移一帧")
                    Button { editor.checkpoint(); editor.step(boundary, frames: 1) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("\(boundary.rawValue)后移一帧")
                }
            }
            Button {
                guard let index = editor.selectedClipIndex, let clip = editor.selectedClip else { return }
                let start = editor.clipOffset(at: index)
                playback.seek(to: start); playback.play(range: start...min(editor.projectDuration, start + clip.timelineDuration))
            } label: { Label("播放选中片段", systemImage: "play.rectangle").font(.caption).frame(minHeight: 44) }
                .disabled(!previewReady || refreshingPreview)
        }
    }

    private func toolStrip(compact: Bool = false) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 3) {
                Button {
                    if !editor.splitProject(at: playback.time) { showNotice("请将播放头移到片段内部再分割。", error: true) }
                } label: {
                    VStack(spacing: 7) { Image(systemName: "scissors").font(.title3); Text("分割").font(.caption2) }
                        .frame(width: 52, height: compact ? 52 : 66)
                }.accessibilityIdentifier("pearl.videoEditor.split")
                ForEach(Tool.allCases) { tool in
                    Button { selectedTool = selectedTool == tool ? nil : tool } label: {
                        VStack(spacing: 7) { Image(systemName: tool == .transitions ? "square.on.square" : tool == .motion ? "diamond" : toolSymbol(tool)).font(.system(size: 19, weight: .regular)); Text(tool.rawValue).font(.system(size: 10, weight: .medium)) }
                            .frame(width: 52, height: compact ? 52 : 66)
                            .foregroundStyle(selectedTool == tool ? .orange : .white)
                    }.accessibilityIdentifier("pearl.videoEditor.tool.\(tool.rawValue)")
                }
            }.padding(.horizontal, 8)
        }.frame(height: compact ? 52 : 66).scrollIndicators(.hidden).background(Color(white: 0.085))
            .disabled(isExportBusy || transcribing)
    }

    @ViewBuilder private var activeTool: some View {
        switch selectedTool ?? .clips {
        case .clips: videoClipTools
        case .transitions: PearlTransitionPanel(editor: editor, previewReady: previewReady && !refreshingPreview) {
            if let range = editor.transitionPreviewRange() { playback.seek(to: range.lowerBound); playback.play(range: range) }
        }
        case .motion: PearlMotionPanel(editor: editor) { end in
            guard let index = editor.selectedClipIndex, let clip = editor.selectedClip else { return }
            playback.pause(); playback.seek(to: editor.clipOffset(at: index) + (end ? max(0, clip.timelineDuration - editor.frameDuration) : 0))
        }
        case .look: videoLookTools
        case .canvas: videoCanvasTools
        case .captions: videoCaptionTools
        case .audio: videoAudioTools
        case .privacy: privacyTools
        }
    }

    private var videoClipTools: some View {
        PearlStudioSection(title: "片段", detail: "\(editor.clips.count) 段") {
            PearlEditorSlider(
                title: "入点",
                value: Binding(get: { editor.trimStart }, set: { editor.checkpoint(); editor.setTrimStart($0) }),
                range: 0...max(editor.selectedClip?.sourceDuration ?? editor.duration, 0.1),
                valueText: editor.timecode(editor.trimStart)
            )
            PearlHairline()
            PearlEditorSlider(
                title: "出点",
                value: Binding(get: { editor.trimEnd }, set: { editor.checkpoint(); editor.setTrimEnd($0) }),
                range: 0...max(editor.selectedClip?.sourceDuration ?? editor.duration, 0.1),
                valueText: editor.timecode(editor.trimEnd)
            )
            PearlHairline()
            PearlEditorSlider(
                title: "速度",
                value: editBinding(\.speed),
                range: 0.25...4,
                valueText: String(format: "%.2f×", editor.speed)
            )
            PearlHairline()
            preciseTrimControls
            HStack(spacing: 6) {
                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { value in
                    Button(String(format: "%g×", value)) { editor.checkpoint(); editor.speed = value }
                        .font(.caption.monospacedDigit()).frame(maxWidth: .infinity).frame(height: 36)
                        .background(editor.speed == value ? Color.orange.opacity(0.2) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            PearlEditorAction(title: "插入定格", glyph: .freeze) {
                Task {
                    do { try await editor.insertFreezeFrame(at: editor.sourcePosition(at: playback.time)?.time ?? editor.trimStart) }
                    catch { showNotice(error.localizedDescription, error: true) }
                }
            }
            PearlEditorActionGrid {
                PearlEditorAction(title: "分割", glyph: .trim) {
                    if !editor.splitProject(at: playback.time) {
                        showNotice("当前位置无法分割。", error: true)
                    }
                }
                PearlEditorAction(title: "左移", glyph: .back) { editor.moveSelected(by: -1) }
                    .disabled(editor.selectedClipIndex == 0)
                PearlEditorAction(title: "右移", glyph: .chevronRight) { editor.moveSelected(by: 1) }
                    .disabled(editor.selectedClipIndex == editor.clips.count - 1)
                PearlEditorAction(title: "复制", glyph: .plus) { editor.duplicateSelectedClip() }
                PearlEditorAction(title: "删除", glyph: .trash, destructive: true) { editor.deleteSelectedClip() }
                    .disabled(!editor.canDeleteClip)
            }
        }
    }

    private var videoLookTools: some View {
        PearlStudioSection(title: "画面", detail: editor.look.rawValue) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(VideoLook.allCases) { look in
                        PearlChoiceChip(look.rawValue, selected: editor.look == look) { editor.apply(look) }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.vertical, 10)
            PearlHairline()
            PearlEditorSlider(title: "亮度", value: editBinding(\.brightness), range: -1...1)
            PearlHairline()
            PearlEditorSlider(title: "对比度", value: editBinding(\.contrast), range: 0.5...1.5)
            PearlHairline()
            PearlEditorSlider(title: "饱和度", value: editBinding(\.saturation), range: 0...2)
            PearlHairline()
            PearlEditorSlider(title: "色温", value: editBinding(\.warmth), range: -1...1)
            PearlHairline()
            PearlEditorSlider(title: "曝光", value: editBinding(\.exposure), range: -2...2)
            PearlHairline()
            PearlEditorSlider(title: "锐化", value: editBinding(\.sharpness), range: 0...2)
            PearlHairline()
            PearlEditorSlider(title: "暗角", value: editBinding(\.vignette), range: 0...1)
            PearlHairline()
            PearlEditorAction(title: "恢复原始画面", glyph: .refresh) { editor.resetVisualAdjustments() }
        }
    }

    private var videoCanvasTools: some View {
        PearlStudioSection(title: "构图", detail: editor.canvasRatio.rawValue) {
            Menu {
                ForEach(VideoCanvasRatio.allCases) { ratio in
                    Button(ratio.rawValue) { editor.canvasRatio = ratio }
                }
            } label: {
                PearlPlainRow("画布比例", accessibilityValue: editor.canvasRatio.rawValue) {
                    Text(editor.canvasRatio.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(PearlColor.tertiary(scheme))
                }
            }
            .buttonStyle(PearlPressStyle())
            PearlHairline()
            PearlEditorActionGrid {
                PearlEditorAction(title: "旋转", glyph: .redo) { editor.rotateClockwise() }
                PearlEditorAction(
                    title: editor.isMirrored ? "取消镜像" : "镜像",
                    glyph: .refresh
                ) { editor.isMirrored.toggle() }
            }
            PearlHairline()
            PearlPlainRow("叠加文字") {
                TextField("输入画面文字", text: editBinding(\.overlayText))
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
            }
            PearlHairline()
            Menu {
                ForEach(VideoTextPosition.allCases) { position in
                    Button(position.rawValue) { editor.overlayPosition = position }
                }
            } label: {
                PearlPlainRow("文字位置", accessibilityValue: editor.overlayPosition.rawValue) {
                    Text(editor.overlayPosition.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(PearlColor.tertiary(scheme))
                }
            }
            .buttonStyle(PearlPressStyle())
        }
    }

    private var videoCaptionTools: some View {
        VStack(alignment: .leading, spacing: 14) {
            if transcribing {
                ProgressView()
                Text(transcriptionStatus).font(.caption)
                Button("取消识别") { transcriptionTask?.cancel() }
            } else {
                HStack {
                    Picker("识别语言", selection: $speechLocale) {
                        Text("中文").tag("zh-CN"); Text("English").tag("en-US")
                    }.pickerStyle(.menu)
                    Spacer()
                    Button(action: generateCaptions) { Label("自动字幕", systemImage: "waveform.badge.mic") }
                        .buttonStyle(.bordered).tint(.orange)
                        .accessibilityIdentifier("pearl.videoEditor.autoCaptions")
                }
                HStack {
                    TextField("输入字幕", text: $captionDraft).textFieldStyle(.roundedBorder)
                    Button("添加") {
                        editor.addCaption(text: captionDraft, at: playback.time, duration: captionDuration)
                        captionDraft = ""
                    }.frame(minWidth: 44, minHeight: 44).disabled(captionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(editor.captions) { caption in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button(editor.timecode(caption.start)) { selectedCaptionID = caption.id; playback.seek(to: caption.start) }
                            Spacer()
                            Button(role: .destructive) { editor.deleteCaption(caption.id) } label: {
                                Image(systemName: "trash").frame(width: 44, height: 44)
                            }.accessibilityLabel("删除字幕")
                        }
                        TextField("字幕内容", text: Binding(get: { caption.text }, set: { editor.updateCaption(caption.id, text: $0) }),
                                  axis: .vertical).textFieldStyle(.roundedBorder)
                        if selectedCaptionID == caption.id {
                            PearlEditorSlider(title: "开始时间", value: Binding(get: { caption.start },
                                set: { editor.updateCaption(caption.id, start: $0) }), range: 0...max(0.1, editor.projectDuration - 0.1))
                            PearlEditorSlider(title: "持续时间", value: Binding(get: { caption.duration },
                                set: { editor.updateCaption(caption.id, duration: $0) }), range: 0.1...max(0.1, editor.projectDuration - caption.start))
                            Picker("字幕位置", selection: Binding(get: { caption.position },
                                set: { editor.updateCaption(caption.id, position: $0) })) {
                                ForEach(VideoTextPosition.allCases) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented)
                        }
                    }
                    Divider()
                }
                if !editor.captions.isEmpty {
                    Button("导出 SRT 字幕") {
                        do {
                            try SharedStorage.prepare()
                            let url = SharedStorage.exportDirectory.appendingPathComponent("Captions-\(UUID()).srt")
                            try VideoCaptionTranscriber.srt(editor.captions).write(to: url, atomically: true, encoding: .utf8)
                            subtitleExport = PearlExportItem(url: url)
                        } catch { showNotice(error.localizedDescription, error: true) }
                    }.frame(minHeight: 44)
                }
            }
        }
    }

    private var privacyTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                selectedMaskID = editor.addRedaction(at: playback.time)
            } label: { Label("添加遮挡区域", systemImage: "rectangle.dashed") }
                .frame(minHeight: 44).accessibilityIdentifier("pearl.videoEditor.addMask")
            Text("拖动画面中的橙色框定位，调整宽高和时间。实色适合敏感信息；马赛克保留画面轮廓。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(editor.redactions) { mask in
                HStack {
                    Button {
                        selectedMaskID = mask.id; playback.pause(); playback.seek(to: mask.start)
                    } label: {
                        HStack {
                            Image(systemName: selectedMaskID == mask.id ? "checkmark.circle.fill" : "circle")
                            Text(mask.style.rawValue)
                            Spacer()
                            Text(editor.timecode(mask.start)).monospacedDigit()
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Button(role: .destructive) { editor.deleteRedaction(mask.id) } label: {
                        Image(systemName: "trash").frame(width: 44, height: 44)
                    }.accessibilityLabel("删除遮挡")
                }.font(.caption)
                if mask.id == selectedMaskID {
                    Picker("遮挡方式", selection: maskBinding(mask, \.style)) {
                        ForEach(VideoRedaction.Style.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    PearlEditorSlider(title: "水平位置", value: maskBinding(mask, \.x), range: 0...max(0.001, 1 - mask.width))
                    PearlEditorSlider(title: "垂直位置", value: maskBinding(mask, \.y), range: 0...max(0.001, 1 - mask.height))
                    PearlEditorSlider(title: "宽度", value: maskBinding(mask, \.width), range: 0.03...1)
                    PearlEditorSlider(title: "高度", value: maskBinding(mask, \.height), range: 0.03...1)
                    PearlEditorSlider(title: "开始时间", value: maskBinding(mask, \.start), range: 0...max(0.1, editor.projectDuration - 0.1))
                    PearlEditorSlider(title: "持续时间", value: maskBinding(mask, \.duration), range: 0.1...max(0.1, editor.projectDuration - mask.start))
                }
            }
        }
    }

    private func editBinding<T>(_ key: ReferenceWritableKeyPath<VideoEditor, T>) -> Binding<T> {
        Binding(get: { editor[keyPath: key] }, set: { editor.checkpoint(); editor[keyPath: key] = $0 })
    }

    private func maskBinding<T>(_ mask: VideoRedaction, _ key: WritableKeyPath<VideoRedaction, T>) -> Binding<T> {
        Binding(get: { mask[keyPath: key] }, set: { value in
            var changed = mask; changed[keyPath: key] = value; editor.updateRedaction(changed)
        })
    }

    private var videoAudioTools: some View {
        PearlStudioSection(
            title: "音轨",
            detail: editor.audioTracks.isEmpty ? "片段原声" : "\(editor.audioTracks.count) 条背景音"
        ) {
            Toggle("静音当前片段", isOn: editBinding(\.isMuted))
                .frame(minHeight: 50)
                .tint(PearlColor.accent(scheme))
            PearlHairline()
            PearlEditorSlider(
                title: "片段音量",
                value: editBinding(\.volume),
                range: 0...2,
                valueText: "\(Int(editor.volume * 100))%"
            )
            PearlHairline()
            PearlEditorAction(title: "导入背景音轨", glyph: .plus) { importingAudio = true }
            ForEach(editor.audioTracks) { track in
                PearlHairline()
                HStack(spacing: 12) {
                    PearlGlyph(.audio, size: 19)
                        .foregroundStyle(PearlColor.accent(scheme))
                    Text(track.name)
                        .font(.subheadline)
                        .foregroundStyle(PearlColor.ink(scheme))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button(role: .destructive) { editor.deleteAudioTrack(track.id) } label: {
                        PearlGlyph(.trash, size: 18).frame(width: 44, height: 44)
                    }
                    .buttonStyle(PearlPressStyle())
                    .accessibilityLabel("删除音轨 \(track.name)")
                }
                .frame(minHeight: 52)
                PearlEditorSlider(title: "音轨起点", value: Binding(get: { track.timelineStart },
                    set: { editor.updateAudioTrack(track.id, timelineStart: $0) }),
                    range: 0...max(0.1, editor.projectDuration - 0.1))
                PearlEditorSlider(title: "音源入点", value: Binding(get: { track.trimStart },
                    set: { editor.updateAudioTrack(track.id, trimStart: $0) }), range: 0...max(0.05, track.sourceDuration))
                PearlEditorSlider(title: "音源出点", value: Binding(get: { track.trimEnd },
                    set: { editor.updateAudioTrack(track.id, trimEnd: $0) }), range: 0...max(0.05, track.sourceDuration))
                PearlEditorSlider(title: "背景音量", value: Binding(get: { track.volume },
                    set: { editor.updateAudioTrack(track.id, volume: $0) }), range: 0...2)
                Toggle("循环播放背景音", isOn: Binding(get: { track.loop },
                    set: { editor.updateAudioTrack(track.id, loop: $0) })).frame(minHeight: 44)
                PearlEditorSlider(title: "淡入", value: Binding(get: { track.fadeIn },
                    set: { editor.updateAudioTrack(track.id, fadeIn: $0) }), range: 0...max(0.1, track.duration / 2))
                PearlEditorSlider(title: "淡出", value: Binding(get: { track.fadeOut },
                    set: { editor.updateAudioTrack(track.id, fadeOut: $0) }), range: 0...max(0.1, track.duration / 2))
            }
        }
        .fileImporter(isPresented: $importingAudio, allowedContentTypes: [.audio], allowsMultipleSelection: false, onCompletion: receiveBackgroundAudio)
    }

    private var videoExportTools: some View {
        PearlStudioSection(title: "导出", detail: outputURL == nil ? "视频文件" : "已生成") {
            Menu {
                ForEach(VideoExportSize.allCases) { size in
                    Button(size.rawValue) { editor.exportSize = size }
                }
            } label: {
                PearlPlainRow("尺寸", accessibilityValue: editor.exportSize.rawValue) {
                    Text(editor.exportSize.rawValue).foregroundStyle(PearlColor.tertiary(scheme))
                }
            }
            .buttonStyle(PearlPressStyle())
            PearlHairline()
            Menu {
                ForEach(VideoExportCodec.allCases) { codec in
                    Button(codec.rawValue) { editor.exportCodec = codec }
                }
            } label: {
                PearlPlainRow("编码", accessibilityValue: editor.exportCodec.rawValue) {
                    Text(editor.exportCodec.rawValue).foregroundStyle(PearlColor.tertiary(scheme))
                }
            }
            .buttonStyle(PearlPressStyle())
            PearlHairline()
            Menu {
                ForEach([0, 24, 30, 60], id: \.self) { fps in
                    Button(fps == 0 ? "保持原始" : "\(fps) fps") { editor.exportFrameRate = fps }
                }
            } label: {
                PearlPlainRow("帧率", accessibilityValue: exportFrameRateTitle) {
                    Text(exportFrameRateTitle).foregroundStyle(PearlColor.tertiary(scheme))
                }
            }
            .buttonStyle(PearlPressStyle())
            PearlHairline()
            Toggle("限制导出体积", isOn: $compressEnabled).frame(minHeight: 44)
                .accessibilityIdentifier("pearl.videoEditor.limitSize")
            if compressEnabled {
                HStack {
                    ForEach([20.0, 50, 100, 200], id: \.self) { size in
                        Button("\(Int(size)) MB") { targetMB = size }
                            .font(.caption).buttonStyle(.bordered).tint(targetMB == size ? .orange : .gray)
                    }
                }
                HStack {
                    Text("目标上限")
                    TextField("MB", value: $targetMB, format: .number)
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("pearl.videoEditor.targetMB")
                    Text("MB")
                }.frame(minHeight: 44)
                Text("先应用全部剪辑，再压缩并核对实际字节。尺寸、帧率与编码沿用上方选择；体积不足时明确报错。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if compressing { ProgressView("正在按目标体积编码", value: compressor.progress) }
            if !exportSummary.isEmpty { Text(exportSummary).font(.caption).foregroundStyle(.orange) }
            exportProgress(value: editor.exportProgress, active: editor.isExporting)
            Button {
                Task { await exportVideo() }
            } label: {
                PearlExportLabel(
                    title: editor.isExporting ? "正在导出" : "导出视频",
                    active: editor.isExporting
                )
            }
            .buttonStyle(PearlPressStyle())
            .disabled(isExportBusy)
            .accessibilityIdentifier("pearl.videoEditor.export")

            PearlHairline()
            Button(action: makeLivePhoto) {
                HStack(spacing: 10) {
                    if isMakingLivePhoto { ProgressView().tint(PearlColor.accent(scheme)) }
                    else { Image(systemName: "livephoto").font(.title3).accessibilityHidden(true) }
                    Text(isMakingLivePhoto ? "正在制作 Live Photo" : "转为 Live Photo")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(PearlColor.accent(scheme))
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(PearlPressStyle())
            .disabled(isExportBusy)
            .accessibilityIdentifier("pearl.videoEditor.livePhoto")
            Text("从当前剪辑结果中选择动态片段、关键照片和声音，再保存到相册。")
                .font(.caption)
                .foregroundStyle(PearlColor.secondary(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let outputURL {
                Button { fileExport = PearlExportItem(url: outputURL) } label: {
                    PearlPrimaryLabel(title: "保存到文件", glyph: .export)
                }.buttonStyle(PearlPressStyle()).accessibilityIdentifier("pearl.videoEditor.saveFile")
                ShareLink(item: outputURL) {
                    PearlShareReadyLabel(fileName: outputURL.lastPathComponent)
                }
                .buttonStyle(PearlPressStyle())
                .accessibilityIdentifier("pearl.videoEditor.share")
            }
        }
    }

    @ViewBuilder private var noticeView: some View {
        if let notice {
            PearlInlineNotice(message: notice.message, tone: notice.isError ? .error : .info)
                .id(notice.id)
                .accessibilityIdentifier("pearl.videoEditor.notice")
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
                    ProgressView(value: value).tint(PearlColor.accent(scheme))
                    Text("正在生成 \(Int(value * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(PearlColor.tertiary(scheme))
                }
                .padding(.vertical, 10)
            }
        }
    }

    private func receiveBackgroundAudio(_ result: Result<[URL], Error>) {
        Task {
            do {
                guard let url = try result.get().first else { return }
                try await editor.addBackgroundAudio(url: EditorMediaImport.copy(url))
                showNotice("背景音轨已添加。")
            } catch {
                showNotice(error.localizedDescription, error: true)
            }
        }
    }

    private var isExportBusy: Bool { editor.isExporting || isMakingLivePhoto || compressing || transcribing }

    @MainActor private func makeLivePhoto() {
        guard !isExportBusy else { return }
        isMakingLivePhoto = true
        notice = nil
        playback.pause()
        Task {
            defer { isMakingLivePhoto = false }
            do {
                // Always render the current edits; an earlier export may be stale.
                let video = try await editor.export()
                outputURL = video
                livePhotoItem = PearlExportItem(url: video)
            } catch {
                showNotice("Live Photo 保存失败：\(error.localizedDescription)", error: true)
            }
        }
    }

    @MainActor private func exportVideo() async {
        guard !isExportBusy else { return }
        do {
            playback.pause()
            let rendered = try await editor.export()
            if compressEnabled {
                guard targetMB.isFinite, targetMB > 0, targetMB <= 100000 else { throw EditingDeskError.sizeTooSmall }
                compressing = true
                defer { compressing = false }
                outputURL = try await compressor.compress(inputURL: rendered, maximumBytes: Int64(targetMB * 1_000_000),
                                                         hevc: editor.exportCodec == .hevc)
            } else { outputURL = rendered }
            if let outputURL {
                let size = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                exportSummary = String(format: "实际体积 %.2f MB", Double(size) / 1_000_000)
            }
            showNotice("视频已生成，可以分享或保存。")
        } catch {
            showNotice(error.localizedDescription, error: true)
        }
    }

    @MainActor private func refreshPreview() async {
        playback.pause(); refreshingPreview = true
        do {
            try await Task.sleep(for: .milliseconds(450))
            let time = playback.time
            let item = try await editor.makePreview()
            try Task.checkCancellation()
            playback.replace(item: item, at: min(time, editor.projectDuration))
            previewReady = true; refreshingPreview = false
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled else { return }
            refreshingPreview = false; previewReady = false
            showNotice("预览更新失败：\(error.localizedDescription)", error: true)
        }
    }

    @MainActor private func generateCaptions() {
        guard !transcribing else { return }
        playback.pause(); transcribing = true; transcriptionStatus = "正在准备剪辑音轨"
        transcriptionTask = Task {
            defer { transcribing = false }
            do {
                let url = try await editor.transcriptionAudio()
                defer { try? FileManager.default.removeItem(at: url) }
                let captions = try await VideoCaptionTranscriber.transcribe(url: url, localeID: speechLocale) {
                    transcriptionStatus = $0
                }
                try Task.checkCancellation()
                editor.appendCaptions(captions)
                selectedCaptionID = captions.first?.id
                showNotice("已添加 \(captions.count) 条自动字幕，可逐条修改。")
            } catch is CancellationError { showNotice("已取消识别，原有字幕保持不变。") }
            catch { showNotice(error.localizedDescription, error: true) }
        }
    }

    private func showNotice(_ message: String, error: Bool = false) {
        let next = PearlEditorNotice(message: message, isError: error)
        if reduceMotion { notice = next }
        else { withAnimation(.easeOut(duration: 0.16)) { notice = next } }
    }
}

