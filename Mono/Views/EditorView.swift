import AVKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum ProfessionalVideoTool: String, CaseIterable, Identifiable {
    case cut = "剪切"
    case media = "素材"
    case transition = "转场"
    case speed = "变速"
    case canvas = "画布"
    case color = "调色"
    case audio = "音频"
    case text = "文字"
    case caption = "字幕"
    case annotation = "标注"
    case export = "导出"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .cut: "scissors"
        case .media: "rectangle.stack.badge.plus"
        case .transition: "square.stack.3d.forward.dottedline"
        case .speed: "speedometer"
        case .canvas: "crop.rotate"
        case .color: "camera.filters"
        case .audio: "waveform"
        case .text: "textformat"
        case .caption: "captions.bubble"
        case .annotation: "pencil.and.outline"
        case .export: "square.and.arrow.up"
        }
    }
}

private struct VideoPreviewSignature: Equatable {
    let brightness: Double
    let contrast: Double
    let saturation: Double
    let exposure: Double
    let warmth: Double
    let sharpness: Double
    let vignette: Double
    let rotation: Int
    let mirrored: Bool
    let ratio: VideoCanvasRatio
    let text: String
    let textPosition: VideoTextPosition
    let textOpacity: Double
}

struct EditorView: View {
    let recording: Recording
    @StateObject private var editor: VideoEditor
    @State private var player: AVPlayer
    @State private var message: String?
    @State private var isMakingLivePhoto = false
    @State private var isMakingGIF = false
    @State private var activeBoundary: TrimBoundary = .start
    @State private var activeTool: ProfessionalVideoTool = .cut
    @State private var playhead: Double = 0
    @State private var timeObserver: Any?
    @State private var outputURL: URL?
    @State private var showVideoImporter = false
    @State private var showAudioImporter = false
    @State private var captionDraft = ""
    @State private var expandedCaptionID: UUID?
    @State private var captionDuration: Double = 3
    @State private var annotationDraft: [VideoAnnotationPoint] = []
    @State private var annotationColor: VideoAnnotationColor = .coral
    @State private var annotationWidth: Double = 5
    @State private var annotationDuration: Double = 3
    @State private var freezeDuration: Double = 1
    @State private var previewFocused = false
    @Namespace private var toolSelectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    init(recording: Recording) {
        self.recording = recording
        let model = VideoEditor(
            sourceURL: recording.url,
            duration: recording.duration
        )
        _editor = StateObject(wrappedValue: model)
        _player = State(initialValue: AVPlayer(url: recording.url))
        _playhead = State(initialValue: model.trimStart)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                editorHero
                timeline
                toolSelector
                toolPanel
                exportAction
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .background { SignalPageBackground() }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            if let message { toast(message) }
        }
        .task { await editor.loadFFmpegPreview() }
        .onAppear { installTimeObserver() }
        .onChange(of: previewSignature) { _, _ in
            Task { await refreshPreview() }
        }
        .onChange(of: editor.selectedClipID) { _, _ in
            Task { await loadSelectedClipPreview() }
        }
        .fileImporter(
            isPresented: $showVideoImporter,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            Task { await importVideoClips(result) }
        }
        .fileImporter(
            isPresented: $showAudioImporter,
            allowedContentTypes: [.audio, .mp3, .wav, .mpeg4Audio],
            allowsMultipleSelection: false
        ) { result in
            Task { await importBackgroundAudio(result) }
        }
        .onDisappear {
            editor.saveDraft()
            player.pause()
            removeTimeObserver()
        }
    }

    private var previewSignature: VideoPreviewSignature {
        VideoPreviewSignature(
            brightness: editor.brightness,
            contrast: editor.contrast,
            saturation: editor.saturation,
            exposure: editor.exposure,
            warmth: editor.warmth,
            sharpness: editor.sharpness,
            vignette: editor.vignette,
            rotation: editor.rotationSteps,
            mirrored: editor.isMirrored,
            ratio: editor.canvasRatio,
            text: editor.overlayText,
            textPosition: editor.overlayPosition,
            textOpacity: editor.overlayOpacity
        )
    }

    private var editorHero: some View {
        ZStack(alignment: .top) {
            playerStage
            header
                .padding(9)
                .background(SignalColor.surface(scheme).opacity(0.56))
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
                .padding(10)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            iconButton("arrow.left") { dismiss() }

            VStack(alignment: .leading, spacing: 2) {
                Text("剪出好镜头")
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

    private var playerStage: some View {
        VideoPlayer(player: player)
            .frame(minHeight: 360)
            .background(.black)
            .scaleEffect(previewFocused && !reduceMotion ? 1.055 : 1)
            .clipShape(YouthNotchedPanelShape(cornerRadius: 34, notchWidth: 94, notchDepth: 62))
            .animation(.spring(response: 0.38, dampingFraction: 0.88), value: previewFocused)
            .onTapGesture(count: 2) {
                withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.38, dampingFraction: 0.84)) {
                    previewFocused.toggle()
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: previewFocused)
            .overlay(alignment: .topLeading) {
                Text(editor.timecode(playhead))
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 27)
                    .background(.black.opacity(0.68))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.top, 80)
                    .padding(.leading, 12)
            }
            .overlay(alignment: .topTrailing) {
                if let summary = editor.technicalSummary {
                    Text(summary)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .frame(height: 27)
                        .background(.black.opacity(0.68))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(.top, 80)
                        .padding(.trailing, 12)
                }
            }
            .overlay { annotationCanvas }
            .overlay(alignment: .topTrailing) {
                YouthStatusBubble(value: "\(editor.clips.count)", symbol: "film.stack")
                    .padding(.top, 78)
                    .padding(.trailing, 8)
            }
            .youthStageEntrance()
    }

    private var annotationCanvas: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let timelineTime = editor.projectTime(forSelectedSourceTime: playhead)
                for stroke in editor.annotations where timelineTime >= stroke.start && timelineTime <= stroke.start + stroke.duration {
                    draw(stroke.points, color: annotationSwiftUIColor(stroke.color), width: stroke.width, in: &context, size: size)
                }
                draw(annotationDraft, color: annotationSwiftUIColor(annotationColor), width: annotationWidth, in: &context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard activeTool == .annotation, proxy.size.width > 0, proxy.size.height > 0 else { return }
                        let point = VideoAnnotationPoint(
                            x: min(1, max(0, value.location.x / proxy.size.width)),
                            y: min(1, max(0, value.location.y / proxy.size.height))
                        )
                        if let previous = annotationDraft.last {
                            let distance = hypot(point.x - previous.x, point.y - previous.y)
                            if distance < 0.003 { return }
                        }
                        annotationDraft.append(point)
                    }
                    .onEnded { _ in
                        guard activeTool == .annotation else { annotationDraft.removeAll(); return }
                        let timelineTime = editor.projectTime(forSelectedSourceTime: playhead)
                        editor.addAnnotation(
                            points: annotationDraft,
                            color: annotationColor,
                            width: annotationWidth,
                            at: timelineTime,
                            duration: annotationDuration
                        )
                        annotationDraft.removeAll()
                    }
            )
        }
        .allowsHitTesting(activeTool == .annotation)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private func draw(
        _ points: [VideoAnnotationPoint],
        color: Color,
        width: Double,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard points.count > 1 else { return }
        var path = Path()
        path.move(to: CGPoint(x: points[0].x * size.width, y: points[0].y * size.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func annotationSwiftUIColor(_ color: VideoAnnotationColor) -> Color {
        switch color {
        case .coral: MonoTheme.coral
        case .white: .white
        case .yellow: .yellow
        case .cyan: .cyan
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("时间线")
                    .font(.system(.headline, design: .rounded, weight: .black))
                Spacer()
                Text("\(Int(editor.frameRate.rounded())) FPS  ·  \(editor.clips.count) CLIPS")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(MonoTheme.muted(scheme))
            }

            TimelineFilmstrip(frames: editor.timelineFrames, selectedTime: playhead) { time in
                seek(to: time)
            }

            frameNavigator

            ClipStrip(
                clips: editor.clips,
                selectedID: editor.selectedClipID,
                onSelect: { clip in
                    editor.selectClip(clip.id)
                    activeBoundary = .start
                    seek(to: clip.start)
                }
            )
        }
        .padding(14)
        .monoPanel()
    }

    private var toolSelector: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ProfessionalVideoTool.allCases) { tool in
                    Button {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.34, dampingFraction: 0.88)) {
                            activeTool = tool
                        }
                    } label: {
                        VStack(spacing: 6) {
                            MonoIcon(tool.symbol, size: 17, weight: 2)
                            Text(tool.rawValue)
                        }
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(activeTool == tool ? SignalColor.acid : MonoTheme.ink(scheme))
                            .frame(width: 66, height: 58)
                            .background {
                                if activeTool == tool {
                                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        .fill(SignalColor.stage)
                                        .matchedGeometryEffect(id: "editor-tool-selection", in: toolSelectionNamespace)
                                } else {
                                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        .fill(MonoTheme.surface(scheme))
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    }
                    .buttonStyle(MonoSpringPressStyle())
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var toolPanel: some View {
        Group {
            switch activeTool {
            case .cut: cutPanel
            case .media: mediaPanel
            case .transition: transitionPanel
            case .speed: speedPanel
            case .canvas: canvasPanel
            case .color: colorPanel
            case .audio: audioPanel
            case .text: textPanel
            case .caption: captionPanel
            case .annotation: annotationPanel
            case .export: exportPanel
            }
        }
        .id(activeTool)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)).combined(with: .scale(scale: 0.985)))
        .sensoryFeedback(.selection, trigger: activeTool)
    }

    private var cutPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            panelTitle("片段 \((editor.selectedClipIndex ?? 0) + 1)", detail: editor.selectedClip.map { format($0.duration) })

            HStack(spacing: 7) {
                editAction("分割", symbol: "scissors", accent: true) {
                    if editor.split(at: playhead) { show("已在当前帧分割") }
                    else { show("播放头需要位于片段内部") }
                }
                editAction("复制", symbol: "plus.square.on.square") { editor.duplicateSelectedClip() }
                editAction("删除", symbol: "trash", disabled: !editor.canDeleteClip) { editor.deleteSelectedClip() }
            }

            HStack(spacing: 7) {
                editAction("前移", symbol: "arrow.left", disabled: editor.selectedClipIndex == 0) {
                    editor.moveSelected(by: -1)
                }
                editAction(
                    "后移",
                    symbol: "arrow.right",
                    disabled: editor.selectedClipIndex == editor.clips.count - 1
                ) { editor.moveSelected(by: 1) }
                editAction("重置", symbol: "arrow.counterclockwise") { editor.resetTimeline() }
            }

            HStack(spacing: 7) {
                editAction("去开头", symbol: "forward.end.fill", accent: true) {
                    editor.skipOpening()
                    seek(to: editor.trimStart)
                    show("已避开开头录入")
                }
                editAction("保留开头", symbol: "backward.end.fill") {
                    editor.includeOpening()
                    seek(to: editor.trimStart)
                }
            }

            HStack(spacing: 8) {
                editAction("冻结帧", symbol: "snowflake", accent: true) {
                    Task {
                        do {
                            try await editor.insertFreezeFrame(at: playhead, duration: freezeDuration)
                            show("冻结帧已插入")
                        } catch { show(error.localizedDescription) }
                    }
                }
                VStack(spacing: 3) {
                    Text("\(String(format: "%.1f", freezeDuration))s")
                        .font(.system(.caption2, design: .monospaced, weight: .black))
                    Slider(value: $freezeDuration, in: 0.5...5, step: 0.5)
                        .tint(MonoTheme.coral)
                }
                .frame(maxWidth: .infinity)
            }

            Divider().overlay(MonoTheme.muted(scheme).opacity(0.22))

            TrimRangeControl(
                lower: Binding(get: { editor.trimStart }, set: { editor.setTrimStart($0) }),
                upper: Binding(get: { editor.trimEnd }, set: { editor.setTrimEnd($0) }),
                range: 0...max(editor.selectedClip?.sourceDuration ?? recording.duration, 0.1),
                minimumDistance: editor.frameDuration
            )

            HStack(spacing: 8) {
                ForEach(TrimBoundary.allCases) { boundary in boundaryButton(boundary) }
            }
            frameControls
        }
        .padding(15)
        .monoPanel()
    }

    private var mediaPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            panelTitle("项目素材", detail: "\(editor.clips.count) VIDEO  ·  \(editor.audioTracks.count) AUDIO")
            HStack(spacing: 8) {
                editAction("添加视频", symbol: "video.badge.plus", accent: true) {
                    showVideoImporter = true
                }
                editAction("添加音乐", symbol: "music.note.list") {
                    showAudioImporter = true
                }
            }

            ForEach(Array(editor.clips.enumerated()), id: \.element.id) { index, clip in
                Button {
                    editor.selectClip(clip.id)
                } label: {
                    HStack(spacing: 10) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(.caption, design: .monospaced, weight: .black))
                            .foregroundStyle(editor.selectedClipID == clip.id ? .white : MonoTheme.ink(scheme))
                            .frame(width: 34, height: 34)
                            .background(editor.selectedClipID == clip.id ? MonoTheme.coral : MonoTheme.background(scheme))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(clip.name)
                                .font(.system(.caption, design: .rounded, weight: .black))
                                .lineLimit(1)
                            Text("\(format(clip.timelineDuration))  ·  \(speedLabel(clip.speed))")
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                .foregroundStyle(MonoTheme.muted(scheme))
                        }
                        Spacer()
                        MonoIcon("line.3.horizontal", size: 17, weight: 2)
                            .foregroundStyle(MonoTheme.muted(scheme))
                    }
                    .foregroundStyle(MonoTheme.ink(scheme))
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(15)
        .monoPanel()
    }

    private var transitionPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelTitle(
                "片段转场",
                detail: editor.selectedClipIndex == editor.clips.count - 1 ? "末段" : editor.transition.rawValue
            )
            HStack(spacing: 8) {
                ForEach(VideoTransition.allCases) { transition in
                    choiceChip(transition.rawValue, selected: editor.transition == transition) {
                        editor.transition = transition
                    }
                }
            }
            .disabled(editor.selectedClipIndex == editor.clips.count - 1)

            if editor.transition != .none {
                controlSlider(
                    "转场时长",
                    value: $editor.transitionDuration,
                    range: 0.15...2,
                    text: String(format: "%.2fs", editor.transitionDuration)
                )
            }
            Text("转场位于当前片段与下一片段之间，并同步交叉淡化原声。")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(MonoTheme.muted(scheme))
        }
        .padding(15)
        .monoPanel()
    }

    private func boundaryButton(_ boundary: TrimBoundary) -> some View {
        Button {
            activeBoundary = boundary
            seek(to: editor.time(for: boundary))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(boundary.rawValue)
                    .font(.system(.caption2, design: .rounded, weight: .black))
                Text(editor.timecode(editor.time(for: boundary)))
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
            }
            .foregroundStyle(
                activeBoundary == boundary ? MonoTheme.background(scheme) : MonoTheme.ink(scheme)
            )
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 11)
            .background(
                activeBoundary == boundary ? MonoTheme.ink(scheme) : MonoTheme.background(scheme)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var frameControls: some View {
        HStack(spacing: 7) {
            frameButton("backward.frame.fill", delta: -1)
            Text(editor.timecode(editor.time(for: activeBoundary)))
                .font(.system(.subheadline, design: .monospaced, weight: .black))
                .frame(maxWidth: .infinity)
            frameButton("forward.frame.fill", delta: 1)
            Button {
                editor.select(activeBoundary, at: playhead)
                seek(to: editor.time(for: activeBoundary))
            } label: {
                MonoIcon("scope", size: 18, weight: 2.1)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 42)
                    .background(MonoTheme.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func frameButton(_ symbol: String, delta: Int) -> some View {
        Button {
            editor.step(activeBoundary, frames: delta)
            seek(to: editor.time(for: activeBoundary))
        } label: {
            MonoIcon(symbol, size: 18, weight: 2.1)
                .frame(width: 46, height: 42)
                .signalControlSurface(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(MonoTheme.ink(scheme))
    }

    private var frameNavigator: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Text(currentFrameText)
                    .font(.system(.caption2, design: .monospaced, weight: .black))
                    .foregroundStyle(MonoTheme.coral)
                    .frame(width: 86, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { playhead },
                        set: { seek(to: $0) }
                    ),
                    in: playheadRange,
                    step: max(editor.frameDuration, 0.001)
                )
                .tint(MonoTheme.coral)
            }

            HStack(spacing: 6) {
                frameJumpButton("-10", frames: -10)
                frameJumpButton("-5", frames: -5)
                frameJumpButton("-1", frames: -1, accent: true)
                frameJumpButton("+1", frames: 1, accent: true)
                frameJumpButton("+5", frames: 5)
                frameJumpButton("+10", frames: 10)
            }

            HStack(spacing: 7) {
                editAction("设为入点", symbol: "arrow.down.to.line") {
                    mark(.start)
                }
                editAction("设为出点", symbol: "arrow.up.to.line") {
                    mark(.end)
                }
            }
        }
        .padding(10)
        .background(MonoTheme.background(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var playheadRange: ClosedRange<Double> {
        let clip = editor.selectedClip
        let lower = clip?.start ?? 0
        let upper = max(lower + editor.frameDuration, clip?.end ?? editor.selectedDuration)
        return lower...upper
    }

    private var currentFrameText: String {
        let frame = max(0, Int((playhead * editor.frameRate).rounded()))
        return "#\(frame)"
    }

    private func frameJumpButton(_ title: String, frames: Int, accent: Bool = false) -> some View {
        Button { seekByFrames(frames) } label: {
            Text(title)
                .font(.system(.caption2, design: .monospaced, weight: .black))
                .foregroundStyle(accent ? .white : MonoTheme.ink(scheme))
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(accent ? MonoTheme.coral : MonoTheme.surface(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var speedPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelTitle("变速", detail: speedLabel(editor.speed))
            Slider(value: $editor.speed, in: 0.25...4, step: 0.05)
                .tint(MonoTheme.coral)
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach([0.25, 0.5, 1, 1.5, 2, 3, 4], id: \.self) { value in
                        choiceChip(speedLabel(value), selected: abs(editor.speed - value) < 0.01) {
                            editor.speed = value
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            Text("音画同步变速  ·  成片 \(format(editor.selectedDuration))")
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(MonoTheme.muted(scheme))
        }
        .padding(15)
        .monoPanel()
    }

    private var canvasPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelTitle("画布", detail: editor.canvasRatio.rawValue)
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(VideoCanvasRatio.allCases) { ratio in
                        choiceChip(ratio.rawValue, selected: editor.canvasRatio == ratio) {
                            editor.canvasRatio = ratio
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 8) {
                editAction("旋转 90°", symbol: "rotate.right") { editor.rotateClockwise() }
                editAction(
                    editor.isMirrored ? "已镜像" : "水平镜像",
                    symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right"
                ) { editor.isMirrored.toggle() }
            }
            Text("旋转 \(editor.rotationSteps * 90)°  ·  \(editor.isMirrored ? "镜像" : "正常")")
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(MonoTheme.muted(scheme))
        }
        .padding(15)
        .monoPanel()
    }

    private var colorPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelTitle("调色", detail: editor.look.rawValue)
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(VideoLook.allCases) { look in
                        choiceChip(look.rawValue, selected: editor.look == look) { editor.apply(look) }
                    }
                }
            }
            .scrollIndicators(.hidden)

            colorSlider("亮度", value: $editor.brightness, range: -0.35...0.35, shown: editor.brightness * 100)
            colorSlider("对比度", value: $editor.contrast, range: 0.5...1.5, shown: (editor.contrast - 1) * 100)
            colorSlider("饱和度", value: $editor.saturation, range: 0...2, shown: (editor.saturation - 1) * 100)
            colorSlider("曝光", value: $editor.exposure, range: -2...2, shown: editor.exposure * 50)
            colorSlider("色温", value: $editor.warmth, range: -1...1, shown: editor.warmth * 100)
            colorSlider("锐化", value: $editor.sharpness, range: 0...1, shown: editor.sharpness * 100)
            colorSlider("暗角", value: $editor.vignette, range: 0...1.2, shown: editor.vignette * 100)

            Button("重置调色") { editor.resetVisualAdjustments() }
                .font(.system(.caption, design: .rounded, weight: .black))
                .foregroundStyle(MonoTheme.coral)
        }
        .padding(15)
        .monoPanel()
    }

    private func colorSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        shown: Double
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.system(.caption, design: .rounded, weight: .black))
                Spacer()
                Text(shown > 0 ? "+\(Int(shown))" : "\(Int(shown))")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(MonoTheme.muted(scheme))
            }
            Slider(value: value, in: range).tint(MonoTheme.coral)
        }
    }

    private var audioPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelTitle("原声音轨", detail: editor.isMuted ? "静音" : "\(Int(editor.volume * 100))%")
            Button { editor.isMuted.toggle() } label: {
                HStack {
                    MonoLabel(
                        editor.isMuted ? "恢复原声" : "静音原声",
                        icon: editor.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
                    )
                    Spacer()
                    MonoIcon(editor.isMuted ? "checkmark.circle.fill" : "circle", size: 18, weight: 2.1)
                        .foregroundStyle(editor.isMuted ? MonoTheme.coral : MonoTheme.muted(scheme))
                }
                .font(.system(.subheadline, design: .rounded, weight: .black))
                .foregroundStyle(MonoTheme.ink(scheme))
                .frame(height: 46)
            }
            .buttonStyle(.plain)
            .disabled(editor.videoInfo?.hasAudio == false)

            controlSlider("音量", value: $editor.volume, range: 0...2, text: "\(Int(editor.volume * 100))%")
            controlSlider("淡入", value: $editor.fadeIn, range: 0...5, text: String(format: "%.1fs", editor.fadeIn))
            controlSlider("淡出", value: $editor.fadeOut, range: 0...5, text: String(format: "%.1fs", editor.fadeOut))

            Divider().overlay(MonoTheme.muted(scheme).opacity(0.22))
            HStack {
                Text("背景音乐轨")
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                Spacer()
                Button { showAudioImporter = true } label: {
                    MonoLabel("添加", icon: "plus", iconSize: 14, spacing: 4)
                        .font(.system(.caption, design: .rounded, weight: .black))
                        .foregroundStyle(MonoTheme.coral)
                }
            }
            ForEach(editor.audioTracks) { track in
                VStack(spacing: 10) {
                    HStack {
                        MonoIcon("music.note", size: 17, weight: 2)
                        Text(track.name)
                            .font(.system(.caption, design: .rounded, weight: .black))
                            .lineLimit(1)
                        Spacer()
                        Button(role: .destructive) { editor.deleteAudioTrack(track.id) } label: {
                            MonoIcon("trash", size: 16, weight: 2)
                        }
                    }
                    HStack(spacing: 10) {
                        Text("\(Int(track.volume * 100))%")
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .frame(width: 38)
                        Slider(
                            value: Binding(
                                get: { track.volume },
                                set: { editor.updateAudioTrack(track.id, volume: $0) }
                            ),
                            in: 0...1.5
                        )
                        .tint(MonoTheme.coral)
                        Button {
                            editor.updateAudioTrack(track.id, loop: !track.loop)
                        } label: {
                            MonoIcon(track.loop ? "repeat.circle.fill" : "repeat.circle", size: 18, weight: 2)
                                .foregroundStyle(track.loop ? MonoTheme.coral : MonoTheme.muted(scheme))
                        }
                    }
                    audioTrackSlider(
                        "开始",
                        value: Binding(
                            get: { track.timelineStart },
                            set: { editor.updateAudioTrack(track.id, timelineStart: $0) }
                        ),
                        range: 0...max(editor.projectDuration, 0.1),
                        text: editor.timecode(track.timelineStart)
                    )
                    audioTrackSlider(
                        "淡入",
                        value: Binding(
                            get: { track.fadeIn },
                            set: { editor.updateAudioTrack(track.id, fadeIn: $0) }
                        ),
                        range: 0...max(track.duration / 2, 0.1),
                        text: String(format: "%.1fs", track.fadeIn)
                    )
                    audioTrackSlider(
                        "淡出",
                        value: Binding(
                            get: { track.fadeOut },
                            set: { editor.updateAudioTrack(track.id, fadeOut: $0) }
                        ),
                        range: 0...max(track.duration / 2, 0.1),
                        text: String(format: "%.1fs", track.fadeOut)
                    )
                }
                .padding(11)
                .background(MonoTheme.background(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .padding(15)
        .monoPanel()
    }

    private func audioTrackSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        text: String
    ) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(.caption2, design: .rounded, weight: .black))
                Spacer()
                Text(text)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(MonoTheme.muted(scheme))
            }
            Slider(value: value, in: range, step: max(editor.frameDuration, 0.001))
                .tint(MonoTheme.coral)
        }
    }

    private var textPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelTitle("文字叠加", detail: editor.overlayText.isEmpty ? "关闭" : editor.overlayPosition.rawValue)
            TextField("输入画面文字", text: $editor.overlayText)
                .textInputAutocapitalization(.never)
                .font(.system(.body, design: .rounded, weight: .bold))
                .padding(.horizontal, 13)
                .frame(height: 48)
                .background(MonoTheme.background(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            HStack(spacing: 7) {
                ForEach(VideoTextPosition.allCases) { position in
                    choiceChip(position.rawValue, selected: editor.overlayPosition == position) {
                        editor.overlayPosition = position
                    }
                }
            }
            controlSlider(
                "不透明度",
                value: $editor.overlayOpacity,
                range: 0.2...1,
                text: "\(Int(editor.overlayOpacity * 100))%"
            )
            if !editor.overlayText.isEmpty {
                Button("清除文字") { editor.overlayText = "" }
                    .font(.system(.caption, design: .rounded, weight: .black))
                    .foregroundStyle(MonoTheme.coral)
            }
        }
        .padding(15)
        .monoPanel()
    }

    private var captionPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            panelTitle("时间字幕", detail: "\(editor.captions.count) 条")
            TextField("输入字幕", text: $captionDraft)
                .font(.system(.body, design: .rounded, weight: .bold))
                .padding(.horizontal, 13)
                .frame(height: 48)
                .background(MonoTheme.background(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            controlSlider(
                "持续时间",
                value: $captionDuration,
                range: 0.5...10,
                text: String(format: "%.1fs", captionDuration)
            )
            HStack(spacing: 8) {
                ForEach(VideoTextPosition.allCases) { position in
                    choiceChip(position.rawValue, selected: editor.overlayPosition == position) {
                        editor.overlayPosition = position
                    }
                }
            }
            Button {
                let timelineTime = editor.projectTime(forSelectedSourceTime: playhead)
                editor.addCaption(text: captionDraft, at: timelineTime, duration: captionDuration)
                captionDraft = ""
                show("字幕已放到当前时间")
            } label: {
                MonoLabel("在播放头添加字幕", icon: "plus.bubble.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(MonoTheme.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(captionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            ForEach(editor.captions) { caption in captionEditorRow(caption) }
        }
        .padding(15)
        .monoPanel()
    }

    private func captionEditorRow(_ caption: TimedCaption) -> some View {
        let expanded = expandedCaptionID == caption.id
        return VStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    expandedCaptionID = expanded ? nil : caption.id
                }
            } label: {
                HStack(spacing: 10) {
                    Text(String(format: "%05.2f", caption.start))
                        .font(.system(.caption2, design: .monospaced, weight: .black))
                        .foregroundStyle(MonoTheme.coral)
                        .frame(width: 48, alignment: .leading)
                    Text(caption.text)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.1fs", caption.duration))
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(MonoTheme.muted(scheme))
                    MonoIcon(expanded ? "chevron.up" : "chevron.down", size: 12, weight: 2.1)
                        .foregroundStyle(MonoTheme.muted(scheme))
                }
                .foregroundStyle(MonoTheme.ink(scheme))
                .frame(minHeight: 40)
            }
            .buttonStyle(.plain)

            if expanded {
                TextField("字幕文字", text: Binding(
                    get: { caption.text },
                    set: { editor.updateCaption(caption.id, text: $0) }
                ))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .padding(.horizontal, 11)
                .frame(height: 42)
                .signalControlSurface(cornerRadius: 14)

                captionSlider(
                    "开始",
                    value: Binding(
                        get: { caption.start },
                        set: { editor.updateCaption(caption.id, start: $0) }
                    ),
                    range: 0...max(editor.projectDuration, 0.2),
                    text: editor.timecode(caption.start)
                )

                captionSlider(
                    "时长",
                    value: Binding(
                        get: { caption.duration },
                        set: { editor.updateCaption(caption.id, duration: $0) }
                    ),
                    range: 0.2...max(editor.projectDuration, 0.2),
                    text: String(format: "%.1fs", caption.duration)
                )

                HStack(spacing: 7) {
                    ForEach(VideoTextPosition.allCases) { position in
                        choiceChip(position.rawValue, selected: caption.position == position) {
                            editor.updateCaption(caption.id, position: position)
                        }
                    }
                }

                HStack(spacing: 8) {
                    editAction("放到播放头", symbol: "scope", accent: true) {
                        let timelineTime = editor.projectTime(forSelectedSourceTime: playhead)
                        editor.updateCaption(caption.id, start: timelineTime)
                    }
                    editAction("删除", symbol: "trash") {
                        editor.deleteCaption(caption.id)
                    }
                }
            }
        }
        .padding(10)
        .background(MonoTheme.background(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var annotationPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            panelTitle("画面标注", detail: "\(editor.annotations.count) 笔")
            HStack(spacing: 10) {
                Image(systemName: "hand.draw.fill")
                    .foregroundStyle(MonoTheme.coral)
                Text("直接在上方预览画面拖动绘制，笔画从当前播放头开始显示。")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(MonoTheme.muted(scheme))
            }

            HStack(spacing: 10) {
                ForEach(VideoAnnotationColor.allCases) { color in
                    Button { annotationColor = color } label: {
                        Circle()
                            .fill(annotationSwiftUIColor(color))
                            .frame(width: 30, height: 30)
                            .overlay {
                                if annotationColor == color {
                                    Circle().stroke(MonoTheme.ink(scheme), lineWidth: 3).padding(-4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择\(color.rawValue)标注颜色")
                }
                Spacer()
                Button("清空") { editor.clearAnnotations() }
                    .font(.system(.caption, design: .rounded, weight: .black))
                    .foregroundStyle(MonoTheme.coral)
                    .disabled(editor.annotations.isEmpty)
            }

            controlSlider("笔画", value: $annotationWidth, range: 2...14, text: "\(Int(annotationWidth)) pt")
            controlSlider("显示时长", value: $annotationDuration, range: 0.5...10, text: String(format: "%.1fs", annotationDuration))

            ForEach(editor.annotations) { annotation in
                HStack(spacing: 10) {
                    Circle().fill(annotationSwiftUIColor(annotation.color)).frame(width: 12, height: 12)
                    Text(editor.timecode(annotation.start))
                        .font(.system(.caption2, design: .monospaced, weight: .black))
                    Text("\(annotation.points.count) 点  ·  \(String(format: "%.1fs", annotation.duration))")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(MonoTheme.muted(scheme))
                    Spacer()
                    Button(role: .destructive) { editor.deleteAnnotation(annotation.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 11)
                .frame(minHeight: 42)
                .background(MonoTheme.background(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(15)
        .monoPanel()
    }

    private var exportPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelTitle("导出参数", detail: "\(editor.exportSize.rawValue)  ·  \(editor.exportCodec.rawValue)")
            Text("编码").font(.system(.caption, design: .rounded, weight: .black))
            HStack(spacing: 7) {
                ForEach(VideoExportCodec.allCases) { codec in
                    choiceChip(codec.rawValue, selected: editor.exportCodec == codec) {
                        editor.exportCodec = codec
                    }
                }
            }

            Text("分辨率").font(.system(.caption, design: .rounded, weight: .black))
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(VideoExportSize.allCases) { size in
                        choiceChip(size.rawValue, selected: editor.exportSize == size) {
                            editor.exportSize = size
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            Text("帧率").font(.system(.caption, design: .rounded, weight: .black))
            HStack(spacing: 7) {
                ForEach([0, 15, 24, 30, 60], id: \.self) { fps in
                    choiceChip(fps == 0 ? "源" : "\(fps)", selected: editor.exportFrameRate == fps) {
                        editor.exportFrameRate = fps
                    }
                }
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

            Button { Task { await makeLivePhoto() } } label: {
                MonoLabel("转为 Live Photo", icon: "livephoto")
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                    .foregroundStyle(MonoTheme.ink(scheme))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(MonoTheme.background(scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(editor.isExporting || isMakingLivePhoto || isMakingGIF)

            Button { Task { await makeGIF() } } label: {
                HStack {
                    if isMakingGIF { ProgressView().controlSize(.small) }
                    MonoLabel(isMakingGIF ? "正在生成 GIF" : "导出动态 GIF", icon: "photo.stack")
                    Spacer()
                    Text("最高 15 FPS")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(MonoTheme.muted(scheme))
                }
                .font(.system(.subheadline, design: .rounded, weight: .black))
                .foregroundStyle(MonoTheme.ink(scheme))
                .padding(.horizontal, 13)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(MonoTheme.background(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(editor.isExporting || isMakingLivePhoto || isMakingGIF)
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

    private func editAction(
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
                .padding(.horizontal, 12)
                .frame(minWidth: 48, minHeight: 38)
                .background(selected ? MonoTheme.ink(scheme) : MonoTheme.background(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func captionSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        text: String
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(.caption2, design: .rounded, weight: .black))
                Spacer()
                Text(text)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(MonoTheme.muted(scheme))
            }
            Slider(value: value, in: range, step: max(editor.frameDuration, 0.001))
                .tint(MonoTheme.coral)
        }
    }

    private func controlSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        text: String
    ) -> some View {
        VStack(spacing: 6) {
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

    private var exportAction: some View {
        Button { Task { await exportVideo() } } label: {
            HStack(spacing: 10) {
                if editor.isExporting { ProgressView().tint(.white) }
                Text(editor.isExporting ? "正在导出" : "导出成片")
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
        .disabled(editor.isExporting || isMakingLivePhoto || isMakingGIF)
    }

    private func exportVideo() async {
        do {
            let output = try await editor.export()
            outputURL = output
            _ = try await library.saveVideoToPhotos(output)
            show("成片已保存")
        } catch { show(error.localizedDescription) }
    }

    private func refreshPreview() async {
        let current = player.currentTime()
        let wasPlaying = player.rate != 0
        let sourceURL = editor.selectedSourceURL
        let item = AVPlayerItem(url: sourceURL)
        if editor.hasVideoComposition {
            item.videoComposition = try? await editor.makeVideoComposition(for: AVURLAsset(url: sourceURL))
        }
        player.replaceCurrentItem(with: item)
        await player.seek(to: current, toleranceBefore: .zero, toleranceAfter: .zero)
        if wasPlaying { player.play() }
    }

    private func loadSelectedClipPreview() async {
        player.pause()
        await editor.loadFFmpegPreview()
        let sourceURL = editor.selectedSourceURL
        let item = AVPlayerItem(url: sourceURL)
        if editor.hasVideoComposition {
            item.videoComposition = try? await editor.makeVideoComposition(for: AVURLAsset(url: sourceURL))
        }
        player.replaceCurrentItem(with: item)
        let target = CMTime(seconds: editor.trimStart, preferredTimescale: 60_000)
        await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        playhead = editor.trimStart
    }

    private func importVideoClips(_ result: Result<[URL], Error>) async {
        do {
            let sources = try result.get()
            let localURLs = try sources.map(persistImportedMedia)
            try await editor.addClips(urls: localURLs)
            show("已添加 \(localURLs.count) 段视频")
        } catch {
            show(error.localizedDescription)
        }
    }

    private func importBackgroundAudio(_ result: Result<[URL], Error>) async {
        do {
            guard let source = try result.get().first else { return }
            let localURL = try persistImportedMedia(source)
            try await editor.addBackgroundAudio(url: localURL)
            show("背景音乐已添加")
        } catch {
            show(error.localizedDescription)
        }
    }

    private func persistImportedMedia(_ source: URL) throws -> URL {
        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }
        try SharedStorage.prepare()
        let pathExtension = source.pathExtension.isEmpty ? "bin" : source.pathExtension
        let destination = SharedStorage.studioMediaDirectory
            .appendingPathComponent("Media-\(UUID().uuidString).\(pathExtension)")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func seek(to seconds: Double) {
        player.pause()
        let snapped = editor.snapped(seconds)
        let time = CMTime(seconds: snapped, preferredTimescale: 60_000)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        playhead = snapped
    }

    private func seekByFrames(_ frames: Int) {
        seek(to: playhead + Double(frames) * editor.frameDuration)
    }

    private func mark(_ boundary: TrimBoundary) {
        activeBoundary = boundary
        editor.select(boundary, at: playhead)
        seek(to: editor.time(for: boundary))
        show(boundary == .start ? "入点已设定" : "出点已设定")
    }

    private func installTimeObserver() {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 1 / 30, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            Task { @MainActor in
                playhead = max(0, time.seconds)
                if time.seconds >= editor.trimEnd, player.rate != 0 {
                    player.pause()
                }
            }
        }
    }

    private func removeTimeObserver() {
        guard let timeObserver else { return }
        player.removeTimeObserver(timeObserver)
        self.timeObserver = nil
    }

    private func makeLivePhoto() async {
        isMakingLivePhoto = true
        defer { isMakingLivePhoto = false }
        do {
            let output = try await editor.export()
            outputURL = output
            try await LivePhotoMaker.save(videoURL: output)
            show("Live Photo 已保存")
        } catch { show(error.localizedDescription) }
    }

    private func makeGIF() async {
        isMakingGIF = true
        defer { isMakingGIF = false }
        do {
            let video = try await editor.export()
            let gif = try await MediaTranscoder().transcode(inputURL: video, target: .animatedGIF)
            outputURL = gif
            show("动态 GIF 已生成")
        } catch { show(error.localizedDescription) }
    }

    private func show(_ text: String) {
        withAnimation(.easeOut(duration: 0.18)) { message = text }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeOut(duration: 0.18)) { message = nil }
        }
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
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func format(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func speedLabel(_ value: Double) -> String {
        value == floor(value) ? "\(Int(value))×" : "\(String(format: "%.2g", value))×"
    }
}

private struct TimelineFilmstrip: View {
    let frames: [VideoTimelineFrame]
    let selectedTime: Double
    let onSelect: (Double) -> Void
    @State private var isScrubbing = false
    @State private var selectedFrameIndex = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let count = max(frames.count, 10)
            let itemWidth = proxy.size.width / CGFloat(count)
            HStack(spacing: 0) {
                if frames.isEmpty {
                    ForEach(0..<count, id: \.self) { _ in
                        MonoTheme.surface(scheme).frame(width: itemWidth)
                    }
                } else {
                    ForEach(frames) { frame in
                        Button { onSelect(frame.time) } label: {
                            Image(uiImage: frame.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: itemWidth, height: 58)
                                .clipped()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .overlay(alignment: .leading) {
                if let duration = frames.last?.time, duration > 0 {
                    ZStack(alignment: .top) {
                        Capsule()
                            .fill(MonoTheme.coral)
                            .frame(width: isScrubbing ? 4 : 2, height: 64)
                        if isScrubbing {
                            Text(frameTimecode(selectedTime))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .frame(height: 24)
                                .background(MonoTheme.ink(scheme))
                                .clipShape(Capsule())
                                .offset(y: 4)
                                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
                        }
                    }
                    .frame(width: 2, height: 64)
                    .offset(x: min(proxy.size.width - 2, proxy.size.width * selectedTime / duration))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let duration = frames.last?.time, duration > 0 else { return }
                        if !isScrubbing {
                            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.86)) {
                                isScrubbing = true
                            }
                        }
                        let fraction = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                        let rawTime = Double(fraction) * duration
                        if let nearest = frames.enumerated().min(by: {
                            abs($0.element.time - rawTime) < abs($1.element.time - rawTime)
                        }) {
                            selectedFrameIndex = nearest.offset
                            onSelect(nearest.element.time)
                        } else {
                            onSelect(rawTime)
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.16)) { isScrubbing = false }
                    }
            )
        }
        .frame(height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .sensoryFeedback(.selection, trigger: selectedFrameIndex)
        .accessibilityHint("左右拖动可逐帧定位")
    }

    private func frameTimecode(_ seconds: Double) -> String {
        let value = max(0, seconds)
        return String(format: "%02d:%02d.%02d", Int(value) / 60, Int(value) % 60, Int((value.truncatingRemainder(dividingBy: 1)) * 100))
    }
}

private struct ClipStrip: View {
    let clips: [VideoClip]
    let selectedID: UUID
    let onSelect: (VideoClip) -> Void

    var body: some View {
        GeometryReader { proxy in
            let total = max(0.001, clips.reduce(0) { $0 + $1.duration })
            HStack(spacing: 3) {
                ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                    Button { onSelect(clip) } label: {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(selectedID == clip.id ? .white : .black)
                            .frame(
                                width: max(28, (proxy.size.width - CGFloat(max(0, clips.count - 1)) * 3) * clip.duration / total),
                                height: 27
                            )
                            .background(selectedID == clip.id ? MonoTheme.coral : Color.white.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 27)
        .clipped()
    }
}

private struct TrimRangeControl: View {
    @Binding var lower: Double
    @Binding var upper: Double
    let range: ClosedRange<Double>
    let minimumDistance: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let lowerX = x(for: lower, width: width)
            let upperX = x(for: upper, width: width)
            ZStack(alignment: .leading) {
                Capsule().fill(MonoTheme.muted(scheme).opacity(0.26)).frame(height: 8)
                Capsule().fill(MonoTheme.coral)
                    .frame(width: max(upperX - lowerX, 0), height: 8)
                    .offset(x: lowerX)
                handle(x: lowerX)
                    .gesture(DragGesture().onChanged { value in
                        lower = min(upper - minimumDistance, mapped(value.location.x, width: width))
                    })
                handle(x: upperX)
                    .gesture(DragGesture().onChanged { value in
                        upper = max(lower + minimumDistance, mapped(value.location.x, width: width))
                    })
            }
            .frame(height: 44)
        }
        .frame(height: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("片段范围")
    }

    private func handle(x: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(MonoTheme.ink(scheme))
            .frame(width: 20, height: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .fill(MonoTheme.background(scheme))
                    .frame(width: 3, height: 14)
            )
            .offset(x: x - 10)
    }

    private func x(for value: Double, width: CGFloat) -> CGFloat {
        CGFloat((value - range.lowerBound) / max(range.upperBound - range.lowerBound, 0.001)) * width
    }

    private func mapped(_ x: CGFloat, width: CGFloat) -> Double {
        let fraction = min(max(x / width, 0), 1)
        return range.lowerBound + Double(fraction) * (range.upperBound - range.lowerBound)
    }
}
