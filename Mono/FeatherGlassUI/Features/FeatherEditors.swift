import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers

private enum FeatherVideoTool: String, CaseIterable, Identifiable {
    case cut = "剪辑"
    case frame = "画面"
    case sound = "声音"
    case captions = "字幕"
    case draw = "标注"
    case export = "导出"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cut: "scissors"
        case .frame: "adjustments"
        case .sound: "speaker"
        case .captions: "captions"
        case .draw: "target"
        case .export: "export"
        }
    }
}

struct FeatherVideoEditorView: View {
    let recording: Recording

    @StateObject private var editor: VideoEditor
    @State private var player: AVPlayer
    @State private var activeTool: FeatherVideoTool = .cut
    @State private var playhead: Double
    @State private var isPlaying = false
    @State private var timeObserver: Any?
    @State private var showVideoImporter = false
    @State private var showAudioImporter = false
    @State private var outputURL: URL?
    @State private var message: String?
    @State private var captionDraft = ""
    @State private var captionDuration = 3.0
    @State private var annotationDraft: [VideoAnnotationPoint] = []
    @State private var annotationColor: VideoAnnotationColor = .coral
    @State private var annotationWidth = 5.0
    @State private var annotationDuration = 3.0

    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(recording: Recording) {
        self.recording = recording
        let model = VideoEditor(sourceURL: recording.url, duration: recording.duration)
        _editor = StateObject(wrappedValue: model)
        _player = State(initialValue: AVPlayer(url: recording.url))
        _playhead = State(initialValue: model.trimStart)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                videoPreview
                projectTimeline
                videoToolSelector
                activeVideoPanel
            }
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 48)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .background(FeatherBackdrop())
        .navigationTitle(recording.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { editorToolbar }
        .overlay(alignment: .top) {
            if let message {
                FeatherInlineNotice(message: message, tone: message.contains("失败") ? .error : .success)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .fileImporter(
            isPresented: $showVideoImporter,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: true
        ) { result in
            Task { await importVideoClips(result) }
        }
        .fileImporter(
            isPresented: $showAudioImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            Task { await importBackgroundAudio(result) }
        }
        .task { await editor.loadFFmpegPreview() }
        .onAppear { installVideoObserver() }
        .onDisappear {
            player.pause()
            removeVideoObserver()
        }
        .onChange(of: editor.selectedClipID) { _, _ in
            player.replaceCurrentItem(with: AVPlayerItem(url: editor.selectedSourceURL))
            playhead = editor.trimStart
            isPlaying = false
        }
    }

    @ToolbarContentBuilder private var editorToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                editor.undo()
            } label: {
                FeatherIcon(name: "undo", size: 18)
            }
            .disabled(!editor.canUndo)
            .accessibilityLabel("撤销")
            .accessibilityIdentifier("feather.video.undo")

            Button {
                editor.redo()
            } label: {
                FeatherIcon(name: "redo", size: 18)
            }
            .disabled(!editor.canRedo)
            .accessibilityLabel("重做")
            .accessibilityIdentifier("feather.video.redo")

            if let outputURL {
                ShareLink(item: outputURL) {
                    FeatherIcon(name: "export", size: 18)
                }
                .accessibilityLabel("分享已导出视频")
            }
        }
    }

    private var videoPreview: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                VideoPlayer(player: player)
                    .disabled(activeTool == .draw)

                captionPreview
                annotationCanvas(size: proxy.size)

                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Button {
                            toggleVideoPlayback()
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(FeatherPressStyle())
                        .accessibilityLabel(isPlaying ? "暂停" : "播放")

                        Text(editor.timecode(playhead))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)

                        Spacer()

                        Text(editor.technicalSummary ?? "\(Int(editor.frameRate.rounded())) fps")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.66))
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(scheme == .dark ? 0.14 : 0.06), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityIdentifier("feather.video.preview")
    }

    @ViewBuilder private var captionPreview: some View {
        let visible = editor.captions.filter {
            playhead >= $0.start && playhead <= $0.start + $0.duration
        }
        VStack {
            if visible.contains(where: { $0.position == .top }) {
                captionLine(visible.filter { $0.position == .top })
            }
            Spacer()
            if visible.contains(where: { $0.position == .center }) {
                captionLine(visible.filter { $0.position == .center })
            }
            Spacer()
            if visible.contains(where: { $0.position == .bottom }) {
                captionLine(visible.filter { $0.position == .bottom })
            }
        }
        .padding(.vertical, 34)
        .padding(.horizontal, 22)
        .allowsHitTesting(false)
    }

    private func captionLine(_ captions: [TimedCaption]) -> some View {
        Text(captions.map(\.text).joined(separator: " "))
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white.opacity(editor.overlayOpacity))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func annotationCanvas(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            for stroke in editor.annotations where playhead >= stroke.start && playhead <= stroke.start + stroke.duration {
                draw(stroke.points, color: annotationColorValue(stroke.color), width: stroke.width, context: &context, size: canvasSize)
            }
            draw(annotationDraft, color: annotationColorValue(annotationColor), width: annotationWidth, context: &context, size: canvasSize)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard activeTool == .draw, size.width > 0, size.height > 0 else { return }
                    let point = VideoAnnotationPoint(
                        x: min(1, max(0, value.location.x / size.width)),
                        y: min(1, max(0, value.location.y / size.height))
                    )
                    if let previous = annotationDraft.last,
                       hypot(previous.x - point.x, previous.y - point.y) < 0.002 { return }
                    annotationDraft.append(point)
                }
                .onEnded { _ in
                    guard activeTool == .draw else {
                        annotationDraft.removeAll()
                        return
                    }
                    editor.addAnnotation(
                        points: annotationDraft,
                        color: annotationColor,
                        width: annotationWidth,
                        at: playhead,
                        duration: annotationDuration
                    )
                    annotationDraft.removeAll()
                }
        )
        .allowsHitTesting(activeTool == .draw)
    }

    private func draw(
        _ points: [VideoAnnotationPoint],
        color: Color,
        width: Double,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private var projectTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("时间线")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text(editor.timecode(editor.projectDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(FeatherColor.secondary(scheme))
            }

            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Array(editor.clips.enumerated()), id: \.element.id) { index, clip in
                        Button {
                            editor.selectClip(clip.id)
                            playhead = clip.start
                            seekVideo(to: clip.start)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(clip.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                HStack(spacing: 5) {
                                    Text(String(format: "%.1f 秒", clip.timelineDuration))
                                    if clip.transition != .none, index < editor.clips.count - 1 {
                                        Text("· \(clip.transition.rawValue)")
                                    }
                                }
                                .font(.caption2.monospacedDigit())
                            }
                            .foregroundStyle(clip.id == editor.selectedClipID ? .white : FeatherColor.ink(scheme))
                            .frame(width: max(104, min(224, CGFloat(clip.timelineDuration) * 22)), alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(minHeight: 58)
                            .background(
                                clip.id == editor.selectedClipID ? FeatherColor.lagoon : FeatherColor.raised(scheme),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                        }
                        .buttonStyle(FeatherPressStyle())
                        .accessibilityAddTraits(clip.id == editor.selectedClipID ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                Text(editor.timecode(playhead))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(FeatherColor.secondary(scheme))
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 54, alignment: .leading)
                Slider(
                    value: $playhead,
                    in: 0...max(editor.duration, 0.1),
                    step: editor.frameDuration
                )
                .tint(FeatherColor.accent(scheme))
                .onChange(of: playhead) { _, newValue in seekVideo(to: newValue) }
                .accessibilityLabel("视频播放位置")
                .accessibilityValue(editor.timecode(playhead))
            }
        }
        .padding(16)
        .background(FeatherColor.surface(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var videoToolSelector: some View {
        FeatherGlassControl(cornerRadius: 22) {
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(FeatherVideoTool.allCases) { tool in
                        Button {
                            if reduceMotion {
                                activeTool = tool
                            } else {
                                withAnimation(.smooth(duration: 0.22)) { activeTool = tool }
                            }
                        } label: {
                            VStack(spacing: 6) {
                                FeatherIcon(name: tool.icon, size: 18)
                                Text(tool.rawValue)
                                    .font(.caption2.weight(.semibold))
                                Capsule()
                                    .fill(activeTool == tool ? FeatherColor.lagoon : .clear)
                                    .frame(width: 22, height: 2)
                            }
                            .foregroundStyle(activeTool == tool ? FeatherColor.accent(scheme) : FeatherColor.secondary(scheme))
                            .frame(width: 62)
                            .padding(.vertical, 8)
                            .frame(minHeight: 58)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(FeatherPressStyle())
                        .accessibilityAddTraits(activeTool == tool ? .isSelected : [])
                        .accessibilityIdentifier("feather.video.tool.\(tool.id)")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private var activeVideoPanel: some View {
        FeatherSurface(cornerRadius: 18) {
            switch activeTool {
            case .cut: videoCutPanel
            case .frame: videoFramePanel
            case .sound: videoSoundPanel
            case .captions: videoCaptionsPanel
            case .draw: videoDrawPanel
            case .export: videoExportPanel
            }
        }
    }

    private var videoCutPanel: some View {
        VStack(spacing: 0) {
            editorSectionHeader("片段", detail: "\(editor.clips.count) 段")
            FeatherRule()
            VStack(spacing: 14) {
                editorSlider(
                    "入点",
                    value: Binding(get: { editor.trimStart }, set: { editor.setTrimStart($0) }),
                    range: 0...max(editor.duration, 0.1),
                    valueText: editor.timecode(editor.trimStart)
                )
                editorSlider(
                    "出点",
                    value: Binding(get: { editor.trimEnd }, set: { editor.setTrimEnd($0) }),
                    range: 0...max(editor.duration, 0.1),
                    valueText: editor.timecode(editor.trimEnd)
                )
                editorSlider("速度", value: $editor.speed, range: 0.25...4, valueText: String(format: "%.2f×", editor.speed))

                HStack(spacing: 8) {
                    compactAction("分割", icon: "scissors") {
                        if !editor.split(at: playhead) { showMessage("当前位置无法分割", isError: true) }
                    }
                    compactAction("复制", icon: "add") { editor.duplicateSelectedClip() }
                    compactAction("删除", icon: "trash", destructive: true) { editor.deleteSelectedClip() }
                        .disabled(!editor.canDeleteClip)
                }

                HStack(spacing: 8) {
                    compactAction("添加片段", icon: "video") { showVideoImporter = true }
                    compactAction("定格画面", icon: "image") {
                        Task {
                            do {
                                try await editor.insertFreezeFrame(at: playhead)
                                showMessage("已插入定格画面")
                            } catch {
                                showMessage("定格失败：\(error.localizedDescription)", isError: true)
                            }
                        }
                    }
                }

                HStack {
                    Picker("转场", selection: $editor.transition) {
                        ForEach(VideoTransition.allCases) { transition in
                            Text(transition.rawValue).tag(transition)
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    if editor.transition != .none {
                        Text(String(format: "%.1f 秒", editor.transitionDuration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(FeatherColor.secondary(scheme))
                    }
                }
                if editor.transition != .none {
                    Slider(value: $editor.transitionDuration, in: 0.1...1.5, step: 0.1)
                        .tint(FeatherColor.accent(scheme))
                        .accessibilityLabel("转场时长")
                        .accessibilityValue(String(format: "%.1f 秒", editor.transitionDuration))
                }
            }
            .padding(16)
        }
    }

    private var videoFramePanel: some View {
        VStack(spacing: 0) {
            editorSectionHeader("画面", detail: editor.look.rawValue)
            FeatherRule()
            VStack(spacing: 15) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(VideoLook.allCases) { look in
                            Button(look.rawValue) { editor.apply(look) }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(editor.look == look ? .white : FeatherColor.ink(scheme))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .frame(minHeight: 44)
                                .background(
                                    editor.look == look ? FeatherColor.lagoon : FeatherColor.raised(scheme),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                                .buttonStyle(FeatherPressStyle())
                                .accessibilityAddTraits(editor.look == look ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)

                editorSlider("亮度", value: $editor.brightness, range: -1...1)
                editorSlider("对比度", value: $editor.contrast, range: 0.5...1.5)
                editorSlider("饱和度", value: $editor.saturation, range: 0...2)
                editorSlider("曝光", value: $editor.exposure, range: -2...2)
                editorSlider("色温", value: $editor.warmth, range: -1...1)
                editorSlider("锐度", value: $editor.sharpness, range: 0...2)
                editorSlider("暗角", value: $editor.vignette, range: 0...1)

                FeatherRule()

                HStack(spacing: 8) {
                    compactAction("旋转", icon: "redo") { editor.rotateClockwise() }
                    compactAction(editor.isMirrored ? "取消镜像" : "镜像", icon: "forward") {
                        editor.isMirrored.toggle()
                    }
                    Menu {
                        Picker("画布比例", selection: $editor.canvasRatio) {
                            ForEach(VideoCanvasRatio.allCases) { ratio in
                                Text(ratio.rawValue).tag(ratio)
                            }
                        }
                    } label: {
                        compactActionLabel(editor.canvasRatio.rawValue, icon: "crop")
                    }
                }

                Button("恢复原始画面") { editor.resetVisualAdjustments() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FeatherColor.accent(scheme))
                    .frame(minHeight: 44)
                    .buttonStyle(FeatherPressStyle())
            }
            .padding(16)
        }
    }

    private var videoSoundPanel: some View {
        VStack(spacing: 0) {
            editorSectionHeader("声音", detail: editor.isMuted ? "已静音" : "片段原声")
            FeatherRule()
            VStack(spacing: 15) {
                Toggle("静音当前片段", isOn: $editor.isMuted)
                    .tint(FeatherColor.accent(scheme))
                editorSlider("音量", value: $editor.volume, range: 0...2, valueText: "\(Int(editor.volume * 100))%")
                editorSlider("淡入", value: $editor.fadeIn, range: 0...5, valueText: String(format: "%.1f 秒", editor.fadeIn))
                editorSlider("淡出", value: $editor.fadeOut, range: 0...5, valueText: String(format: "%.1f 秒", editor.fadeOut))

                FeatherRule()

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("背景音乐").font(.body.weight(.medium))
                        Text(editor.audioTracks.isEmpty ? "未添加" : "\(editor.audioTracks.count) 条音轨")
                            .font(.caption)
                            .foregroundStyle(FeatherColor.secondary(scheme))
                    }
                    Spacer()
                    Button("导入") { showAudioImporter = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FeatherColor.accent(scheme))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .buttonStyle(FeatherPressStyle())
                }

                ForEach(editor.audioTracks) { track in
                    HStack(spacing: 12) {
                        FeatherIcon(name: "music", size: 18)
                            .foregroundStyle(FeatherColor.accent(scheme))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.name).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text(String(format: "%.1f 秒", track.duration))
                                .font(.caption)
                                .foregroundStyle(FeatherColor.secondary(scheme))
                        }
                        Spacer()
                        Button(role: .destructive) { editor.deleteAudioTrack(track.id) } label: {
                            FeatherIcon(name: "trash", size: 17)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("删除 \(track.name)")
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(16)
        }
    }

    private var videoCaptionsPanel: some View {
        VStack(spacing: 0) {
            editorSectionHeader("字幕", detail: editor.captions.isEmpty ? "未添加" : "\(editor.captions.count) 条")
            FeatherRule()
            VStack(spacing: 14) {
                TextField("输入字幕内容", text: $captionDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(FeatherColor.raised(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("feather.video.captionText")

                captionControls

                FeatherPrimaryButton(
                    title: "添加到 \(editor.timecode(playhead))",
                    icon: "add",
                    isEnabled: !captionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    editor.addCaption(text: captionDraft, at: playhead, duration: captionDuration)
                    captionDraft = ""
                }

                ForEach(editor.captions) { caption in
                    HStack(alignment: .top, spacing: 12) {
                        Text(editor.timecode(caption.start))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(FeatherColor.secondary(scheme))
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: 54, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(caption.text).font(.subheadline).lineLimit(2)
                            Text("\(caption.position.rawValue) · \(String(format: "%.1f", caption.duration)) 秒")
                                .font(.caption2)
                                .foregroundStyle(FeatherColor.secondary(scheme))
                        }
                        Spacer()
                        Button(role: .destructive) { editor.deleteCaption(caption.id) } label: {
                            FeatherIcon(name: "trash", size: 16)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("删除字幕")
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(16)
        }
    }

    private var captionControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                captionPositionControl
                Spacer(minLength: 12)
                captionDurationControl
            }

            VStack(alignment: .leading, spacing: 8) {
                captionPositionControl
                    .frame(maxWidth: .infinity, alignment: .leading)
                captionDurationControl
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var captionPositionControl: some View {
        Picker("位置", selection: $editor.overlayPosition) {
            ForEach(VideoTextPosition.allCases) { position in
                Text(position.rawValue).tag(position)
            }
        }
        .pickerStyle(.menu)
        .frame(minHeight: 44)
    }

    private var captionDurationControl: some View {
        Stepper(
            String(format: "%.1f 秒", captionDuration),
            value: $captionDuration,
            in: 0.5...10,
            step: 0.5
        )
        .font(.subheadline)
        .frame(minHeight: 44)
        .accessibilityLabel("字幕时长")
        .accessibilityValue(String(format: "%.1f 秒", captionDuration))
    }

    private var videoDrawPanel: some View {
        VStack(spacing: 0) {
            editorSectionHeader("标注", detail: "直接在预览画面上绘制")
            FeatherRule()
            VStack(spacing: 15) {
                HStack(spacing: 14) {
                    ForEach(VideoAnnotationColor.allCases) { color in
                        Button {
                            annotationColor = color
                        } label: {
                            Circle()
                                .fill(annotationColorValue(color))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Circle().stroke(
                                        FeatherColor.accent(scheme),
                                        lineWidth: annotationColor == color ? 3 : 0
                                    )
                                }
                                .overlay {
                                    Circle().stroke(FeatherColor.ink(scheme).opacity(0.20), lineWidth: 1)
                                }
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(FeatherPressStyle())
                        .accessibilityLabel("标注颜色 \(color.rawValue)")
                        .accessibilityAddTraits(annotationColor == color ? .isSelected : [])
                    }
                    Spacer()
                    Button("清除全部", role: .destructive) { editor.clearAnnotations() }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .disabled(editor.annotations.isEmpty)
                }

                editorSlider("笔画", value: $annotationWidth, range: 2...14, valueText: "\(Int(annotationWidth)) pt")
                editorSlider("显示", value: $annotationDuration, range: 0.5...10, valueText: String(format: "%.1f 秒", annotationDuration))

                Text("绘制内容从当前播放位置开始显示。切换到其他工具后，预览恢复常规手势。")
                    .font(.caption)
                    .foregroundStyle(FeatherColor.secondary(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(editor.annotations) { annotation in
                    HStack(spacing: 10) {
                        Circle().fill(annotationColorValue(annotation.color)).frame(width: 10, height: 10)
                        Text(editor.timecode(annotation.start)).font(.caption.monospacedDigit())
                        Text("\(annotation.points.count) 点")
                            .font(.caption)
                            .foregroundStyle(FeatherColor.secondary(scheme))
                        Spacer()
                        Button(role: .destructive) { editor.deleteAnnotation(annotation.id) } label: {
                            FeatherIcon(name: "trash", size: 16)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("删除标注")
                    }
                }
            }
            .padding(16)
        }
    }

    private var videoExportPanel: some View {
        VStack(spacing: 0) {
            editorSectionHeader("导出", detail: outputURL == nil ? "尚未生成" : "文件已就绪")
            FeatherRule()
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Picker("尺寸", selection: $editor.exportSize) {
                        ForEach(VideoExportSize.allCases) { size in Text(size.rawValue).tag(size) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("编码", selection: $editor.exportCodec) {
                        ForEach(VideoExportCodec.allCases) { codec in Text(codec.rawValue).tag(codec) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Picker("帧率", selection: $editor.exportFrameRate) {
                    Text("跟随源文件").tag(0)
                    Text("24 fps").tag(24)
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                if editor.isExporting {
                    VStack(alignment: .leading, spacing: 7) {
                        ProgressView(value: editor.exportProgress)
                            .tint(FeatherColor.accent(scheme))
                        Text("正在生成 \(Int(editor.exportProgress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(FeatherColor.secondary(scheme))
                    }
                }

                FeatherPrimaryButton(
                    title: editor.isExporting ? "正在导出" : "导出视频",
                    icon: "export",
                    isEnabled: !editor.isExporting
                ) { exportVideo() }
                .accessibilityIdentifier("feather.video.export")

                if let outputURL {
                    ShareLink(item: outputURL) {
                        FeatherIconLabel(title: "分享文件", icon: "forward")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(FeatherColor.accent(scheme))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(FeatherPressStyle())
                }
            }
            .padding(16)
        }
    }

    private func editorSectionHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline.weight(.semibold))
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(FeatherColor.secondary(scheme))
        }
        .padding(16)
    }

    private func editorSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueText: String? = nil
    ) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(valueText ?? String(format: "%.2f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(FeatherColor.secondary(scheme))
            }
            Slider(value: value, in: range)
                .tint(FeatherColor.accent(scheme))
                .accessibilityLabel(title)
                .accessibilityValue(valueText ?? String(format: "%.2f", value.wrappedValue))
        }
    }

    private func compactAction(
        _ title: String,
        icon: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            compactActionLabel(title, icon: icon, destructive: destructive)
        }
        .buttonStyle(FeatherPressStyle())
    }

    private func compactActionLabel(_ title: String, icon: String, destructive: Bool = false) -> some View {
        FeatherIconLabel(title: title, icon: icon, iconSize: 16)
            .font(.caption.weight(.semibold))
            .foregroundStyle(destructive ? FeatherColor.danger(scheme) : FeatherColor.ink(scheme))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .background(FeatherColor.raised(scheme), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
    }

    private func annotationColorValue(_ color: VideoAnnotationColor) -> Color {
        Color(uiColor: color.uiColor)
    }

    private func toggleVideoPlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if playhead >= editor.trimEnd - editor.frameDuration {
                playhead = editor.trimStart
                seekVideo(to: playhead)
            }
            player.play()
            isPlaying = true
        }
    }

    private func seekVideo(to time: Double) {
        let clamped = min(max(time, 0), editor.duration)
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 60_000),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func installVideoObserver() {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 1 / 30, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            Task { @MainActor in
                guard isPlaying else { return }
                let seconds = max(0, time.seconds)
                playhead = seconds
                if seconds >= editor.trimEnd {
                    player.pause()
                    isPlaying = false
                }
            }
        }
    }

    private func removeVideoObserver() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func importVideoClips(_ result: Result<[URL], Error>) async {
        do {
            let sources = try result.get()
            let urls = try sources.map(persistImportedMedia)
            try await editor.addClips(urls: urls)
            showMessage("已添加 \(urls.count) 段视频")
        } catch {
            showMessage("导入失败：\(error.localizedDescription)", isError: true)
        }
    }

    private func importBackgroundAudio(_ result: Result<[URL], Error>) async {
        do {
            guard let source = try result.get().first else { return }
            let url = try persistImportedMedia(source)
            try await editor.addBackgroundAudio(url: url)
            showMessage("背景音乐已添加")
        } catch {
            showMessage("导入失败：\(error.localizedDescription)", isError: true)
        }
    }

    private func exportVideo() {
        Task {
            do {
                outputURL = try await editor.export()
                await library.reload()
                showMessage("视频已导出")
            } catch {
                showMessage("导出失败：\(error.localizedDescription)", isError: true)
            }
        }
    }

    private func showMessage(_ text: String, isError: Bool = false) {
        message = isError && !text.contains("失败") ? "操作失败：\(text)" : text
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if message == (isError && !text.contains("失败") ? "操作失败：\(text)" : text) {
                message = nil
            }
        }
    }
}

private enum FeatherAudioTool: String, CaseIterable, Identifiable {
    case cut = "剪辑"
    case tone = "音色"
    case smart = "智能"
    case lyrics = "歌词"
    case export = "导出"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cut: "scissors"
        case .tone: "adjustments"
        case .smart: "waveform"
        case .lyrics: "document"
        case .export: "export"
        }
    }
}

struct FeatherAudioEditorView: View {
    let recording: AudioRecording

    @StateObject private var editor: AudioEditor
    @State private var player: AVPlayer
    @State private var activeTool: FeatherAudioTool = .cut
    @State private var playhead = 0.0
    @State private var isPlaying = false
    @State private var timeObserver: Any?
    @State private var showLyricsImporter = false
    @State private var outputURL: URL?
    @State private var message: String?

    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(recording: AudioRecording) {
        self.recording = recording
        _editor = StateObject(wrappedValue: AudioEditor(sourceURL: recording.url, duration: recording.duration))
        _player = State(initialValue: AVPlayer(url: recording.url))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                audioStage
                audioToolSelector
                activeAudioPanel
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 48)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .background(FeatherBackdrop())
        .navigationTitle(recording.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { audioToolbar }
        .overlay(alignment: .top) {
            if let message {
                FeatherInlineNotice(message: message, tone: message.contains("失败") ? .error : .success)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .fileImporter(
            isPresented: $showLyricsImporter,
            allowedContentTypes: [.plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            importLyrics(result)
        }
        .task { await editor.loadWaveform() }
        .onAppear { installAudioObserver() }
        .onDisappear {
            player.pause()
            removeAudioObserver()
        }
    }

    @ToolbarContentBuilder private var audioToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { editor.undo() } label: { FeatherIcon(name: "undo", size: 18) }
                .disabled(!editor.canUndo)
                .accessibilityLabel("撤销")
            Button { editor.redo() } label: { FeatherIcon(name: "redo", size: 18) }
                .disabled(!editor.canRedo)
                .accessibilityLabel("重做")
            if let outputURL {
                ShareLink(item: outputURL) { FeatherIcon(name: "export", size: 18) }
                    .accessibilityLabel("分享已导出音频")
            }
        }
    }

    private var audioStage: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(isPlaying ? "正在播放" : "音频波形")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text(audioTimecode(playhead))
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(FeatherColor.secondary(scheme))
            }

            waveformView
                .frame(height: 118)

            Slider(value: $playhead, in: 0...max(editor.duration, 0.1), step: 0.01)
                .tint(FeatherColor.accent(scheme))
                .onChange(of: playhead) { _, value in seekAudio(to: value) }
                .accessibilityLabel("音频播放位置")
                .accessibilityValue(audioTimecode(playhead))

            HStack {
                Button { seekAudioBy(-5) } label: {
                    Image(systemName: "gobackward.5")
                        .font(.title3.weight(.medium))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(FeatherPressStyle())
                .accessibilityLabel("后退五秒")

                Spacer()

                Button { toggleAudioPlayback() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                        .background(FeatherColor.lagoon, in: Circle())
                }
                .buttonStyle(FeatherPressStyle())
                .accessibilityLabel(isPlaying ? "暂停" : "播放")
                .accessibilityIdentifier("feather.audio.playback")

                Spacer()

                Button { seekAudioBy(5) } label: {
                    Image(systemName: "goforward.5")
                        .font(.title3.weight(.medium))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(FeatherPressStyle())
                .accessibilityLabel("前进五秒")
            }
            .foregroundStyle(FeatherColor.ink(scheme))
        }
        .padding(18)
        .background(FeatherColor.surface(scheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("feather.audio.waveform")
    }

    private var waveformView: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let samples = editor.waveform.isEmpty ? placeholderWaveform : editor.waveform
                let count = max(1, samples.count)
                let slot = size.width / CGFloat(count)
                let progress = min(1, max(0, playhead / max(editor.duration, 0.1)))
                for (index, sample) in samples.enumerated() {
                    let normalized = min(1, max(0.05, CGFloat(abs(sample))))
                    let height = max(2, normalized * size.height * 0.88)
                    let x = CGFloat(index) * slot + slot * 0.5
                    let rect = CGRect(x: x - max(0.7, slot * 0.22), y: (size.height - height) / 2, width: max(1.4, slot * 0.44), height: height)
                    let color = Double(index) / Double(count) <= progress ? FeatherColor.lagoon : FeatherColor.rule(scheme)
                    context.fill(Path(roundedRect: rect, cornerRadius: rect.width / 2), with: .color(color))
                }
            }
        }
    }

    private var placeholderWaveform: [Float] {
        (0..<72).map { index in
            Float(0.18 + abs(sin(Double(index) * 0.37)) * 0.58)
        }
    }

    private var audioToolSelector: some View {
        FeatherGlassControl(cornerRadius: 22) {
            HStack(spacing: 0) {
                ForEach(FeatherAudioTool.allCases) { tool in
                    Button {
                        if reduceMotion { activeTool = tool }
                        else { withAnimation(.smooth(duration: 0.22)) { activeTool = tool } }
                    } label: {
                        VStack(spacing: 6) {
                            FeatherIcon(name: tool.icon, size: 18)
                            Text(tool.rawValue).font(.caption2.weight(.semibold))
                            Capsule()
                                .fill(activeTool == tool ? FeatherColor.lagoon : .clear)
                                .frame(width: 22, height: 2)
                        }
                        .foregroundStyle(activeTool == tool ? FeatherColor.accent(scheme) : FeatherColor.secondary(scheme))
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(FeatherPressStyle())
                    .accessibilityAddTraits(activeTool == tool ? .isSelected : [])
                    .accessibilityIdentifier("feather.audio.tool.\(tool.id)")
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        }
    }

    @ViewBuilder private var activeAudioPanel: some View {
        FeatherSurface(cornerRadius: 18) {
            switch activeTool {
            case .cut: audioCutPanel
            case .tone: audioTonePanel
            case .smart: audioSmartPanel
            case .lyrics: audioLyricsPanel
            case .export: audioExportPanel
            }
        }
    }

    private var audioCutPanel: some View {
        VStack(spacing: 0) {
            audioPanelHeader("片段", detail: "\(editor.clips.count) 段")
            FeatherRule()
            VStack(spacing: 14) {
                audioSlider(
                    "入点",
                    value: Binding(get: { editor.trimStart }, set: { editor.setTrimStart($0) }),
                    range: 0...max(editor.duration, 0.1),
                    valueText: audioTimecode(editor.trimStart)
                )
                audioSlider(
                    "出点",
                    value: Binding(get: { editor.trimEnd }, set: { editor.setTrimEnd($0) }),
                    range: 0...max(editor.duration, 0.1),
                    valueText: audioTimecode(editor.trimEnd)
                )
                audioSlider("速度", value: $editor.speed, range: 0.25...4, valueText: String(format: "%.2f×", editor.speed))
                audioSlider("音量", value: $editor.volume, range: 0...2, valueText: "\(Int(editor.volume * 100))%")
                audioSlider("淡入", value: $editor.fadeIn, range: 0...5, valueText: String(format: "%.1f 秒", editor.fadeIn))
                audioSlider("淡出", value: $editor.fadeOut, range: 0...5, valueText: String(format: "%.1f 秒", editor.fadeOut))

                HStack(spacing: 8) {
                    audioCompactAction("分割", icon: "scissors") {
                        if !editor.split(at: playhead) { showAudioMessage("当前位置无法分割", isError: true) }
                    }
                    audioCompactAction("复制", icon: "add") { editor.duplicateSelectedClip() }
                    audioCompactAction("删除", icon: "trash", destructive: true) { editor.deleteSelectedClip() }
                        .disabled(!editor.canDeleteClip)
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Array(editor.clips.enumerated()), id: \.element.id) { index, clip in
                            Button {
                                editor.selectClip(clip.id)
                                playhead = clip.start
                            } label: {
                                Text("片段 \(index + 1) · \(String(format: "%.1f", clip.duration)) 秒")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(clip.id == editor.selectedClipID ? .white : FeatherColor.ink(scheme))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .frame(minHeight: 44)
                                    .background(
                                        clip.id == editor.selectedClipID ? FeatherColor.lagoon : FeatherColor.raised(scheme),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                            }
                            .buttonStyle(FeatherPressStyle())
                            .accessibilityAddTraits(clip.id == editor.selectedClipID ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(16)
        }
    }

    private var audioTonePanel: some View {
        VStack(spacing: 0) {
            audioPanelHeader("音色", detail: editor.hasAudioEffects ? "已调整" : "原声")
            FeatherRule()
            VStack(spacing: 15) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(AudioEQPreset.allCases) { preset in
                            Button(preset.rawValue) { editor.applyEQPreset(preset) }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(FeatherColor.ink(scheme))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .frame(minHeight: 44)
                                .background(FeatherColor.raised(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .buttonStyle(FeatherPressStyle())
                        }
                    }
                }
                .scrollIndicators(.hidden)

                audioSlider("降噪", value: $editor.noiseReduction, range: 0...1, valueText: "\(Int(editor.noiseReduction * 100))%")
                audioSlider("低频", value: $editor.bassGain, range: -12...12, valueText: String(format: "%+.1f dB", editor.bassGain))
                audioSlider("中频", value: $editor.midGain, range: -12...12, valueText: String(format: "%+.1f dB", editor.midGain))
                audioSlider("高频", value: $editor.trebleGain, range: -12...12, valueText: String(format: "%+.1f dB", editor.trebleGain))
                audioSlider("音高", value: $editor.pitchSemitones, range: -12...12, valueText: String(format: "%+.0f", editor.pitchSemitones))

                Button {
                    Task {
                        do {
                            let url = try await editor.renderEffectPreview()
                            player.replaceCurrentItem(with: AVPlayerItem(url: url))
                            playhead = 0
                            showAudioMessage("试听已生成")
                        } catch {
                            showAudioMessage("试听失败：\(error.localizedDescription)", isError: true)
                        }
                    }
                } label: {
                    HStack {
                        if editor.isRenderingPreview { ProgressView() }
                        FeatherIconLabel(title: editor.isRenderingPreview ? "正在生成" : "试听处理效果", icon: "play")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FeatherColor.accent(scheme))
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(FeatherPressStyle())
                .disabled(editor.isRenderingPreview)
            }
            .padding(16)
        }
    }

    private var audioSmartPanel: some View {
        VStack(spacing: 0) {
            audioPanelHeader("智能处理", detail: "本机完成")
            FeatherRule()
            VStack(spacing: 0) {
                smartAction(
                    title: "检测静音",
                    detail: editor.isAnalyzingSilence ? "正在分析波形" : "标记可安全移除的安静片段",
                    icon: "waveform"
                ) { Task { await editor.analyzeSilence() } }
                FeatherRule().padding(.leading, 46)
                smartAction(
                    title: "移除静音",
                    detail: editor.silenceRegions.isEmpty ? "请先运行检测" : String(format: "预计缩短 %.1f 秒", editor.detectedSilenceDuration),
                    icon: "scissors"
                ) {
                    if editor.applySilenceRemoval() { showAudioMessage("已移除静音片段") }
                    else { showAudioMessage("没有可移除的静音", isError: true) }
                }
                .disabled(editor.silenceRegions.isEmpty)
                FeatherRule().padding(.leading, 46)
                smartAction(
                    title: "自动降噪",
                    detail: editor.isAnalyzingNoise ? "正在识别噪声底" : "匹配当前录音的降噪强度",
                    icon: "adjustments"
                ) { Task { await editor.autoTuneNoiseReduction() } }

                if let error = editor.silenceAnalysisError ?? editor.noiseAnalysisError {
                    FeatherInlineNotice(message: error, tone: .warning)
                        .padding(.top, 12)
                }
            }
            .padding(16)
        }
    }

    private var audioLyricsPanel: some View {
        VStack(spacing: 0) {
            audioPanelHeader("歌词", detail: editor.lyrics.isEmpty ? "未导入" : "\(editor.lyrics.count) 行")
            FeatherRule()
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    audioCompactAction("导入歌词", icon: "document") { showLyricsImporter = true }
                    audioCompactAction("添加一行", icon: "add") {
                        _ = editor.addLyric(at: playhead)
                    }
                }

                if editor.lyrics.isEmpty {
                    Text("支持 LRC 与常见文本歌词。播放到目标位置后添加一行，即可写入当前时间。")
                        .font(.subheadline)
                        .foregroundStyle(FeatherColor.secondary(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else {
                    ForEach(editor.lyrics) { line in
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                editor.setLyricTime(line.id, to: playhead)
                            } label: {
                                Text(line.time.map(audioTimecode) ?? "设时间")
                                    .font(.caption.monospacedDigit().weight(.medium))
                                    .foregroundStyle(FeatherColor.accent(scheme))
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(minWidth: 54, alignment: .leading)
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(FeatherPressStyle())

                            TextField(
                                "歌词内容",
                                text: Binding(
                                    get: { editor.lyrics.first(where: { $0.id == line.id })?.text ?? line.text },
                                    set: { editor.updateLyric(line.id, text: $0) }
                                ),
                                axis: .vertical
                            )
                            .textFieldStyle(.plain)
                            .font(.subheadline)
                            .padding(.vertical, 8)

                            Button(role: .destructive) { editor.deleteLyric(line.id) } label: {
                                FeatherIcon(name: "trash", size: 16)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("删除歌词")
                        }
                        .overlay(alignment: .bottom) { FeatherRule() }
                    }

                    HStack(spacing: 8) {
                        Button("整体提前 0.5 秒") { editor.shiftLyrics(by: -0.5) }
                            .frame(minHeight: 44)
                        Spacer()
                        Button("整体延后 0.5 秒") { editor.shiftLyrics(by: 0.5) }
                            .frame(minHeight: 44)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FeatherColor.accent(scheme))
                    .buttonStyle(FeatherPressStyle())

                    Button {
                        do {
                            _ = try editor.saveLyrics()
                            showAudioMessage("歌词已保存")
                        } catch {
                            showAudioMessage("保存失败：\(error.localizedDescription)", isError: true)
                        }
                    } label: {
                        FeatherIconLabel(title: "保存歌词文件", icon: "check")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(FeatherColor.accent(scheme))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(FeatherPressStyle())
                }
            }
            .padding(16)
        }
    }

    private var audioExportPanel: some View {
        VStack(spacing: 0) {
            audioPanelHeader("导出", detail: outputURL == nil ? "尚未生成" : "文件已就绪")
            FeatherRule()
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Picker("格式", selection: $editor.exportFormat) {
                        ForEach(editor.availableFormats) { format in Text(format.rawValue).tag(format) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("码率", selection: $editor.exportBitrate) {
                        ForEach(AudioExportBitrate.allCases) { bitrate in Text(bitrate.title).tag(bitrate) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Picker("采样率", selection: $editor.exportSampleRate) {
                    Text("44.1 kHz").tag(44_100)
                    Text("48 kHz").tag(48_000)
                    Text("96 kHz").tag(96_000)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Picker("声道", selection: $editor.exportChannelCount) {
                    Text("单声道").tag(1)
                    Text("立体声").tag(2)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                if editor.isExporting {
                    VStack(alignment: .leading, spacing: 7) {
                        ProgressView(value: editor.exportProgress).tint(FeatherColor.accent(scheme))
                        Text("正在生成 \(Int(editor.exportProgress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(FeatherColor.secondary(scheme))
                    }
                }

                FeatherPrimaryButton(
                    title: editor.isExporting ? "正在导出" : "导出音频",
                    icon: "export",
                    isEnabled: !editor.isExporting
                ) { exportAudio() }
                .accessibilityIdentifier("feather.audio.export")

                if let outputURL {
                    ShareLink(item: outputURL) {
                        FeatherIconLabel(title: "分享文件", icon: "forward")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(FeatherColor.accent(scheme))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(FeatherPressStyle())
                }
            }
            .padding(16)
        }
    }

    private func audioPanelHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline.weight(.semibold))
            Spacer()
            Text(detail).font(.caption).foregroundStyle(FeatherColor.secondary(scheme))
        }
        .padding(16)
    }

    private func audioSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueText: String? = nil
    ) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(valueText ?? String(format: "%.2f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(FeatherColor.secondary(scheme))
            }
            Slider(value: value, in: range)
                .tint(FeatherColor.accent(scheme))
                .accessibilityLabel(title)
                .accessibilityValue(valueText ?? String(format: "%.2f", value.wrappedValue))
        }
    }

    private func audioCompactAction(
        _ title: String,
        icon: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            FeatherIconLabel(title: title, icon: icon, iconSize: 16)
                .font(.caption.weight(.semibold))
                .foregroundStyle(destructive ? FeatherColor.danger(scheme) : FeatherColor.ink(scheme))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 8)
                .background(FeatherColor.raised(scheme), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(FeatherPressStyle())
    }

    private func smartAction(
        title: String,
        detail: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                FeatherIcon(name: icon, size: 19)
                    .foregroundStyle(FeatherColor.accent(scheme))
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.medium))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(FeatherColor.secondary(scheme))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FeatherColor.secondary(scheme))
            }
            .foregroundStyle(FeatherColor.ink(scheme))
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(FeatherPressStyle())
    }

    private func toggleAudioPlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if playhead >= editor.duration - 0.02 {
                playhead = 0
                seekAudio(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }

    private func seekAudio(to time: Double) {
        let value = min(editor.duration, max(0, time))
        player.seek(
            to: CMTime(seconds: value, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func seekAudioBy(_ offset: Double) {
        playhead = min(editor.duration, max(0, playhead + offset))
        seekAudio(to: playhead)
    }

    private func installAudioObserver() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { time in
            Task { @MainActor in
                guard isPlaying else { return }
                playhead = min(editor.duration, max(0, time.seconds))
                if playhead >= editor.duration - 0.02 {
                    player.pause()
                    isPlaying = false
                }
            }
        }
    }

    private func removeAudioObserver() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func importLyrics(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try editor.importLyrics(from: url)
            showAudioMessage("歌词已导入")
        } catch {
            showAudioMessage("导入失败：\(error.localizedDescription)", isError: true)
        }
    }

    private func exportAudio() {
        Task {
            do {
                outputURL = try await editor.export()
                await library.reload()
                showAudioMessage("音频已导出")
            } catch {
                showAudioMessage("导出失败：\(error.localizedDescription)", isError: true)
            }
        }
    }

    private func audioTimecode(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func showAudioMessage(_ text: String, isError: Bool = false) {
        let final = isError && !text.contains("失败") ? "操作失败：\(text)" : text
        message = final
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if message == final { message = nil }
        }
    }
}

private func persistImportedMedia(_ source: URL) throws -> URL {
    let hasAccess = source.startAccessingSecurityScopedResource()
    defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }
    try SharedStorage.prepare()
    let ext = source.pathExtension.isEmpty ? "bin" : source.pathExtension
    let destination = SharedStorage.studioMediaDirectory
        .appendingPathComponent("Media-\(UUID().uuidString).\(ext)")
    try FileManager.default.copyItem(at: source, to: destination)
    return destination
}
