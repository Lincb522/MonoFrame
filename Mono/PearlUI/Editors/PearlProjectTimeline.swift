import SwiftUI
import UniformTypeIdentifiers

struct PearlProjectTimeline: View {
    @ObservedObject var editor: VideoEditor
    @ObservedObject var playback: PearlPlaybackController
    var selectCaption: (UUID) -> Void
    var selectMask: (UUID) -> Void
    var addMedia: () -> Void
    var selectTransition: (UUID) -> Void
    var compact = false
    @State private var snapping = true
    @State private var pointsPerSecond = 52.0
    @State private var zoomOrigin = 52.0
    @State private var position = ScrollPosition(x: 0)
    @State private var scrolling = false
    @State private var trimOrigin: Double?
    private let orange = Color(red: 1, green: 0.36, blue: 0.16)

    var body: some View {
        VStack(spacing: 0) {
            if !compact {
            HStack(spacing: 8) {
                Text("时间线").font(.caption.weight(.semibold))
                Text("\(editor.clips.count) 个片段").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button { snapping.toggle() } label: {
                    Image(systemName: "dot.scope").frame(width: 36, height: 44).foregroundStyle(snapping ? orange : .gray)
                }.accessibilityLabel(snapping ? "关闭剪辑点吸附" : "开启剪辑点吸附")
                Button { pointsPerSecond = max(12, pointsPerSecond / 1.4); zoomOrigin = pointsPerSecond } label: {
                    Image(systemName: "minus.magnifyingglass").frame(width: 44, height: 44)
                }.accessibilityLabel("缩小时间线")
                Button { pointsPerSecond = min(240, pointsPerSecond * 1.4); zoomOrigin = pointsPerSecond } label: {
                    Image(systemName: "plus.magnifyingglass").frame(width: 44, height: 44)
                }.accessibilityLabel("放大时间线")
                Button(action: addMedia) {
                    Image(systemName: "plus").frame(width: 44, height: 44).background(orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                }.accessibilityLabel("添加视频片段")
            }.padding(.horizontal, 12)
            }
            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 8) {
                        ruler.frame(height: 24)
                        ZStack(alignment: .leading) {
                            ForEach(Array(editor.clips.enumerated()), id: \.element.id) { index, clip in
                                clipCell(clip, index: index)
                                    .offset(x: editor.clipOffset(at: index) * pointsPerSecond)
                            }
                            ForEach(Array(editor.clips.dropLast().enumerated()), id: \.element.id) { index, clip in
                                transitionButton(clip, index: index)
                            }
                        }.frame(width: trackWidth, height: 56, alignment: .leading)
                        ForEach(editor.audioTracks) { audio in
                            trackBar(audio.name, icon: "waveform", start: audio.timelineStart,
                                     length: audio.loop ? editor.projectDuration - audio.timelineStart : audio.duration,
                                     color: .teal) { playback.pause(); playback.seek(to: audio.timelineStart) }
                        }
                        ForEach(editor.captions) { caption in
                            trackBar(caption.text, icon: "textformat", start: caption.start, length: caption.duration,
                                     color: .yellow) { selectCaption(caption.id); playback.pause(); playback.seek(to: caption.start) }
                        }
                        ForEach(editor.redactions) { mask in
                            trackBar(mask.style.rawValue, icon: "rectangle.dashed", start: mask.start,
                                     length: mask.duration, color: .purple) {
                                selectMask(mask.id); playback.pause(); playback.seek(to: mask.start)
                            }
                        }
                        if editor.audioTracks.isEmpty && editor.captions.isEmpty && editor.redactions.isEmpty {
                            Label("字幕、音轨与遮挡将显示在这里", systemImage: "square.stack.3d.down.right")
                                .font(.caption2).foregroundStyle(.secondary).frame(height: 32)
                        }
                    }
                    .frame(width: trackWidth, alignment: .leading)
                    .padding(.horizontal, proxy.size.width / 2)
                    .padding(.bottom, 12)
                }
                .scrollPosition($position)
                .onScrollPhaseChange { _, phase in
                    let wasScrolling = scrolling
                    scrolling = phase == .interacting || phase == .decelerating || phase == .tracking
                    if scrolling { playback.pause() }
                    if phase == .idle, wasScrolling, snapping {
                        let time = editor.snappedProjectTime(playback.time, threshold: 8 / pointsPerSecond)
                        playback.seek(to: time); position.scrollTo(x: time * pointsPerSecond)
                    }
                }
                .onScrollGeometryChange(for: Double.self) { Double($0.contentOffset.x) } action: { _, x in
                    if scrolling { playback.seek(to: min(editor.projectDuration, max(0, x / pointsPerSecond))) }
                }
                .onChange(of: playback.time) { _, time in
                    if !scrolling { position.scrollTo(x: time * pointsPerSecond) }
                }
                .onChange(of: pointsPerSecond) { _, _ in position.scrollTo(x: playback.time * pointsPerSecond) }
                .simultaneousGesture(MagnifyGesture().onChanged { value in
                    pointsPerSecond = min(240, max(12, zoomOrigin * value.magnification))
                }.onEnded { _ in zoomOrigin = pointsPerSecond })
                .scrollIndicators(.hidden)
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 10, height: 10)
                        Rectangle().fill(.white).frame(width: 1.5)
                    }.allowsHitTesting(false)
                }
                .accessibilityIdentifier("pearl.videoEditor.timeline")
                .accessibilityAdjustableAction { direction in
                    playback.pause()
                    playback.seek(to: min(editor.projectDuration, max(0,
                        playback.time + (direction == .increment ? 1 : -1) * editor.frameDuration)))
                }
            }
            .frame(height: 135 + CGFloat(editor.audioTracks.count + editor.captions.count + editor.redactions.count) * 40)
        }
        .background(Color(white: 0.095))
    }

    private func transitionButton(_ clip: VideoClip, index: Int) -> some View {
        let empty = clip.transition == .none
        let midpoint = editor.clipOffset(at: index + 1) + editor.effectiveTransitionDuration(after: index) / 2
        let x = midpoint * pointsPerSecond - 22
        return Button { selectTransition(clip.id) } label: {
            Image(systemName: empty ? "plus" : "square.on.square")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(empty ? Color.white : Color.black)
                .frame(width: 24, height: 24)
                .background(empty ? Color(white: 0.16) : orange, in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.3), lineWidth: 1) }
                .frame(width: 44, height: 56)
        }.buttonStyle(.plain)
            .accessibilityLabel("片段 \(index + 1) 转场，\(clip.transition.rawValue)")
            .accessibilityIdentifier("pearl.timeline.transition.\(index)")
            .offset(x: x)
    }

    private var trackWidth: CGFloat { max(1, editor.projectDuration * pointsPerSecond) }

    private var ruler: some View {
        Canvas { context, size in
            let step = pointsPerSecond < 25 ? 5.0 : pointsPerSecond < 80 ? 1.0 : 0.5
            for time in stride(from: 0.0, through: editor.projectDuration, by: step) {
                let x = time * pointsPerSecond
                context.fill(Path(CGRect(x: x, y: 19, width: 1, height: 5)), with: .color(.gray))
                context.draw(Text(String(format: "%.1fs", time)).font(.system(size: 9, design: .monospaced)).foregroundColor(.gray),
                             at: CGPoint(x: x + 3, y: 7), anchor: .leading)
            }
        }
    }

    private func clipCell(_ clip: VideoClip, index: Int) -> some View {
        let selected = clip.id == editor.selectedClipID
        let width = max(12, clip.timelineDuration * pointsPerSecond)
        return ZStack {
            HStack(spacing: 1) {
                ForEach(0..<max(1, min(24, Int(width / 38))), id: \.self) { index in
                    if clip.sourceURL == editor.selectedSourceURL, !editor.timelineFrames.isEmpty {
                        let count = max(1, min(24, Int(width / 38)))
                        let time = clip.start + clip.duration * Double(index) / Double(count)
                        let frame = editor.timelineFrames.min { abs($0.time - time) < abs($1.time - time) }
                        if let frame {
                            Image(uiImage: frame.image).resizable().scaledToFill().frame(width: width / CGFloat(count), height: 56).clipped()
                        }
                    } else {
                        PearlThumbnail(url: clip.sourceURL).frame(maxWidth: .infinity)
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text("\(index + 1) · \(String(format: "%.1fs", clip.timelineDuration))")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .padding(3).background(.black.opacity(0.65))
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).stroke(selected ? orange : .white.opacity(0.3), lineWidth: selected ? 2 : 1) }
            if selected {
                HStack {
                    trimHandle(start: true)
                    Spacer(minLength: 0)
                    trimHandle(start: false)
                }
            }
        }
        .frame(width: width, height: 56)
        .contentShape(Rectangle())
        .onTapGesture { editor.selectClip(clip.id) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("片段 \(index + 1)，\(clip.timelineDuration.formatted()) 秒")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { editor.selectClip(clip.id) }
        .draggable(clip.id.uuidString)
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first, let id = UUID(uuidString: value),
                  let from = editor.clips.firstIndex(where: { $0.id == id }), from != index else { return false }
            editor.selectClip(id); editor.moveSelected(by: index - from); return true
        }
    }

    private func trimHandle(start: Bool) -> some View {
        Capsule().fill(orange).frame(width: 5, height: 24).padding(.horizontal, 4)
            .frame(height: 56).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3).onChanged { drag in
                if trimOrigin == nil {
                    editor.checkpoint(); trimOrigin = start ? editor.trimStart : editor.trimEnd
                }
                let value = (trimOrigin ?? 0) + drag.translation.width / pointsPerSecond * editor.speed
                if start { editor.setTrimStart(value) } else { editor.setTrimEnd(value) }
            }.onEnded { _ in trimOrigin = nil })
    }

    private func trackBar(_ title: String, icon: String, start: Double, length: Double,
                          color: Color, action: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: max(0, start * pointsPerSecond))
            Button(action: action) {
                Label(title, systemImage: icon).font(.caption2.weight(.medium)).lineLimit(1)
                    .frame(width: max(22, min(length, editor.projectDuration - start) * pointsPerSecond) - 12,
                           height: 32, alignment: .leading).padding(.horizontal, 6)
                    .foregroundStyle(color).background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
        }.frame(width: trackWidth, alignment: .leading)
    }
}
