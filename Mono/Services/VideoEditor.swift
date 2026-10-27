import AVFoundation
import CoreImage
import FFmpegSwiftSDK
import Foundation
import QuartzCore
import UIKit

enum VideoLook: String, CaseIterable, Identifiable, Codable {
    case original = "原始"
    case mono = "黑白"
    case vivid = "鲜明"
    case soft = "柔和"
    case warm = "暖调"
    case cool = "冷调"
    case film = "胶片"

    var id: String { rawValue }

    var controls: (brightness: Double, contrast: Double, saturation: Double, warmth: Double, vignette: Double) {
        switch self {
        case .original: (0, 1, 1, 0, 0)
        case .mono: (0.01, 1.12, 0, 0, 0.18)
        case .vivid: (0.03, 1.16, 1.28, 0.05, 0.08)
        case .soft: (0.06, 0.92, 0.86, 0.04, 0)
        case .warm: (0.02, 1.06, 1.08, 0.28, 0.12)
        case .cool: (0, 1.08, 0.96, -0.28, 0.1)
        case .film: (-0.02, 1.18, 0.82, 0.12, 0.42)
        }
    }
}

enum TrimBoundary: String, CaseIterable, Identifiable {
    case start = "入点"
    case end = "出点"

    var id: String { rawValue }
}

enum VideoCanvasRatio: String, CaseIterable, Identifiable, Codable {
    case original = "原始"
    case square = "1:1"
    case landscape = "16:9"
    case portrait = "9:16"
    case classic = "4:3"
    case vertical = "3:4"

    var id: String { rawValue }

    var value: CGFloat? {
        switch self {
        case .original: nil
        case .square: 1
        case .landscape: 16 / 9
        case .portrait: 9 / 16
        case .classic: 4 / 3
        case .vertical: 3 / 4
        }
    }
}

enum VideoExportSize: String, CaseIterable, Identifiable, Codable {
    case source = "源尺寸"
    case p240 = "240P"
    case p480 = "480P"
    case p720 = "720P"
    case p1080 = "1080P"
    case p1440 = "2K"

    var id: String { rawValue }

    var longEdge: CGFloat? {
        switch self {
        case .source: nil
        case .p240: 426
        case .p480: 854
        case .p720: 1280
        case .p1080: 1920
        case .p1440: 2560
        }
    }
}

enum VideoExportCodec: String, CaseIterable, Identifiable, Codable {
    case source = "自动"
    case h264 = "H.264"
    case hevc = "HEVC"

    var id: String { rawValue }
}

enum VideoTextPosition: String, CaseIterable, Identifiable, Codable {
    case top = "顶部"
    case center = "居中"
    case bottom = "底部"

    var id: String { rawValue }
}

struct VideoTimelineFrame: Identifiable {
    let id: Int
    let time: Double
    let image: UIImage
}

struct VideoClip: Identifiable, Equatable, Codable {
    let id: UUID
    var sourceURL: URL
    var sourceDuration: Double
    var start: Double
    var end: Double
    var speed: Double
    var volume: Double
    var isMuted: Bool
    var transition: VideoTransition
    var transitionDuration: Double
    var motion: ClipMotion?

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        sourceDuration: Double,
        start: Double,
        end: Double,
        speed: Double = 1,
        volume: Double = 1,
        isMuted: Bool = false,
        transition: VideoTransition = .none,
        transitionDuration: Double = 0.4,
        motion: ClipMotion? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.sourceDuration = sourceDuration
        self.start = start
        self.end = end
        self.speed = speed
        self.volume = volume
        self.isMuted = isMuted
        self.transition = transition
        self.transitionDuration = transitionDuration
        self.motion = motion
    }

    var duration: Double { max(0, end - start) }
    var timelineDuration: Double { duration / max(speed, 0.05) }
    var name: String { sourceURL.deletingPathExtension().lastPathComponent }
}

struct ProjectAudioTrack: Identifiable, Equatable, Codable {
    let id: UUID
    var sourceURL: URL
    var sourceDuration: Double
    var timelineStart: Double
    var trimStart: Double
    var trimEnd: Double
    var volume: Double
    var fadeIn: Double
    var fadeOut: Double
    var loop: Bool

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        sourceDuration: Double,
        timelineStart: Double = 0,
        trimStart: Double = 0,
        trimEnd: Double,
        volume: Double = 0.7,
        fadeIn: Double = 0,
        fadeOut: Double = 0,
        loop: Bool = false
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.sourceDuration = sourceDuration
        self.timelineStart = timelineStart
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.volume = volume
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.loop = loop
    }

    var duration: Double { max(0.01, trimEnd - trimStart) }
    var name: String { sourceURL.deletingPathExtension().lastPathComponent }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceURL
        case sourceDuration
        case timelineStart
        case trimStart
        case trimEnd
        case volume
        case fadeIn
        case fadeOut
        case loop
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceURL = try container.decode(URL.self, forKey: .sourceURL)
        sourceDuration = try container.decode(Double.self, forKey: .sourceDuration)
        timelineStart = try container.decode(Double.self, forKey: .timelineStart)
        trimStart = try container.decode(Double.self, forKey: .trimStart)
        trimEnd = try container.decode(Double.self, forKey: .trimEnd)
        volume = try container.decode(Double.self, forKey: .volume)
        fadeIn = try container.decodeIfPresent(Double.self, forKey: .fadeIn) ?? 0
        fadeOut = try container.decodeIfPresent(Double.self, forKey: .fadeOut) ?? 0
        loop = try container.decodeIfPresent(Bool.self, forKey: .loop) ?? false
    }
}

struct TimedCaption: Identifiable, Equatable, Codable {
    let id: UUID
    var text: String
    var start: Double
    var duration: Double
    var position: VideoTextPosition

    init(
        id: UUID = UUID(),
        text: String,
        start: Double,
        duration: Double = 3,
        position: VideoTextPosition = .bottom
    ) {
        self.id = id
        self.text = text
        self.start = start
        self.duration = duration
        self.position = position
    }
}

enum VideoAnnotationColor: String, CaseIterable, Identifiable, Codable {
    case coral, white, yellow, cyan
    var id: String { rawValue }

    var uiColor: UIColor {
        switch self {
        case .coral: UIColor(red: 0.94, green: 0.24, blue: 0.16, alpha: 1)
        case .white: .white
        case .yellow: UIColor(red: 1, green: 0.78, blue: 0.12, alpha: 1)
        case .cyan: UIColor(red: 0.12, green: 0.78, blue: 0.92, alpha: 1)
        }
    }
}

struct VideoAnnotationPoint: Equatable, Codable, Sendable {
    var x: Double
    var y: Double
}

struct VideoAnnotationStroke: Identifiable, Equatable, Codable {
    let id: UUID
    var points: [VideoAnnotationPoint]
    var color: VideoAnnotationColor
    var width: Double
    var start: Double
    var duration: Double

    init(
        id: UUID = UUID(),
        points: [VideoAnnotationPoint],
        color: VideoAnnotationColor,
        width: Double,
        start: Double,
        duration: Double
    ) {
        self.id = id
        self.points = points
        self.color = color
        self.width = width
        self.start = start
        self.duration = duration
    }
}

@MainActor
final class VideoEditor: ObservableObject {
    @Published private(set) var clips: [VideoClip] { didSet { scheduleDraftSave() } }
    @Published private(set) var selectedClipID: UUID { didSet { scheduleDraftSave() } }
    @Published private(set) var audioTracks: [ProjectAudioTrack] = [] { didSet { scheduleDraftSave() } }
    @Published private(set) var captions: [TimedCaption] = [] { didSet { scheduleDraftSave() } }
    @Published private(set) var annotations: [VideoAnnotationStroke] = [] { didSet { scheduleDraftSave() } }
    @Published private(set) var redactions: [VideoRedaction] = [] { didSet { scheduleDraftSave() } }
    @Published private(set) var revision = 0
    @Published private(set) var draftError: String?
    @Published var trimStart: Double
    @Published var trimEnd: Double
    @Published var speed: Double = 1 { didSet { syncSelectedClipSettings(); scheduleDraftSave() } }
    @Published var isMuted = false { didSet { syncSelectedClipSettings(); scheduleDraftSave() } }
    @Published var volume: Double = 1 { didSet { syncSelectedClipSettings(); scheduleDraftSave() } }
    @Published var transition: VideoTransition = .none { didSet { syncSelectedClipSettings(); scheduleDraftSave() } }
    @Published var transitionDuration: Double = 0.4 { didSet { syncSelectedClipSettings(); scheduleDraftSave() } }
    @Published var fadeIn: Double = 0 { didSet { scheduleDraftSave() } }
    @Published var fadeOut: Double = 0 { didSet { scheduleDraftSave() } }
    @Published var look: VideoLook = .original { didSet { scheduleDraftSave() } }
    @Published var brightness: Double = 0 { didSet { scheduleDraftSave() } }
    @Published var contrast: Double = 1 { didSet { scheduleDraftSave() } }
    @Published var saturation: Double = 1 { didSet { scheduleDraftSave() } }
    @Published var exposure: Double = 0 { didSet { scheduleDraftSave() } }
    @Published var warmth: Double = 0 { didSet { scheduleDraftSave() } }
    @Published var sharpness: Double = 0 { didSet { scheduleDraftSave() } }
    @Published var vignette: Double = 0 { didSet { scheduleDraftSave() } }
    @Published var rotationSteps = 0 { didSet { scheduleDraftSave() } }
    @Published var isMirrored = false { didSet { scheduleDraftSave() } }
    @Published var canvasRatio: VideoCanvasRatio = .original { didSet { scheduleDraftSave() } }
    @Published var overlayText = "" { didSet { scheduleDraftSave() } }
    @Published var overlayPosition: VideoTextPosition = .bottom { didSet { scheduleDraftSave() } }
    @Published var overlayOpacity: Double = 1 { didSet { scheduleDraftSave() } }
    @Published var exportSize: VideoExportSize = .source { didSet { scheduleDraftSave() } }
    @Published var exportCodec: VideoExportCodec = .source { didSet { scheduleDraftSave() } }
    @Published var exportFrameRate = 0 { didSet { scheduleDraftSave() } }
    @Published private(set) var isExporting = false
    @Published private(set) var exportProgress: Double = 0
    @Published private(set) var timelineFrames: [VideoTimelineFrame] = []
    @Published private(set) var videoInfo: VideoInfo?

    let sourceURL: URL
    let duration: Double
    private let ffmpeg = VideoProcessor()
    private var undoStack: [VideoProjectSnapshot] = []
    private var redoStack: [VideoProjectSnapshot] = []
    private var isSynchronizingSelection = false
    private var isRestoringDraft = false
    private var draftSaveTask: Task<Void, Never>?
    private var previewedSourceURL: URL?

    init(sourceURL: URL, duration: Double) {
        self.sourceURL = sourceURL
        self.duration = max(duration, 0.1)
        let initialStart: Double
        let initialEnd: Double
        if sourceURL.lastPathComponent.hasPrefix("ScreenReady-") {
            initialStart = min(1.5, max(0, duration - 1 / 30))
            initialEnd = max(initialStart + 1 / 30, duration)
        } else {
            initialStart = 0
            initialEnd = max(duration, 0.1)
        }
        let initialClip = VideoClip(
            sourceURL: sourceURL,
            sourceDuration: max(duration, 0.1),
            start: initialStart,
            end: initialEnd
        )
        self.clips = [initialClip]
        self.selectedClipID = initialClip.id
        self.trimStart = initialClip.start
        self.trimEnd = initialClip.end
        restoreDraftIfAvailable()
    }

    deinit {
        draftSaveTask?.cancel()
        if let url = previewTimelineURL { try? FileManager.default.removeItem(at: url) }
    }

    var selectedClipIndex: Int? { clips.firstIndex { $0.id == selectedClipID } }
    var selectedClip: VideoClip? { selectedClipIndex.map { clips[$0] } }
    var selectedSourceURL: URL { selectedClip?.sourceURL ?? sourceURL }
    var canDeleteClip: Bool { clips.count > 1 }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var hasNextClip: Bool { selectedClipIndex.map { $0 < clips.count - 1 } ?? false }
    var cutTimes: [Double] { [0] + clips.indices.dropFirst().map { clipOffset(at: $0) } + [projectDuration] }
    func snappedProjectTime(_ time: Double, threshold: Double) -> Double {
        let clamped = min(projectDuration, max(0, time))
        if let closest = cutTimes.min(by: { abs($0 - clamped) < abs($1 - clamped) }), abs(closest - clamped) <= threshold { return closest }
        return (clamped / frameDuration).rounded() * frameDuration
    }
    func setTransition(_ effect: VideoTransition, duration: Double? = nil, all: Bool = false) {
        guard hasNextClip || all else { return }
        registerTimelineChange()
        let indices = all ? Array(clips.indices.dropLast()) : selectedClipIndex.map { [$0] } ?? []
        for index in indices {
            clips[index].transition = effect
            if let duration { clips[index].transitionDuration = min(2, max(0.1, duration)) }
        }
        selectClip(selectedClipID)
    }
    func transitionPreviewRange() -> ClosedRange<Double>? {
        guard let index = selectedClipIndex, hasNextClip else { return nil }
        let start = clipOffset(at: index + 1)
        return max(0, start - 0.5)...min(projectDuration, start + effectiveTransitionDuration(after: index) + 0.5)
    }
    func updateMotion(_ motion: ClipMotion?) {
        guard let index = selectedClipIndex else { return }
        registerTimelineChange(); clips[index].motion = motion
    }

    var selectedDuration: Double {
        max(frameDuration, projectDuration)
    }

    var projectDuration: Double {
        var total = clips.reduce(0) { $0 + $1.timelineDuration }
        for index in clips.indices.dropLast() where clips[index].transition != .none {
            total -= effectiveTransitionDuration(after: index)
        }
        return max(frameDuration, total)
    }

    var frameRate: Double {
        let detected = videoInfo?.frameRate ?? 0
        return detected > 0 ? detected : 30
    }

    var frameDuration: Double { 1 / frameRate }

    func time(for boundary: TrimBoundary) -> Double {
        boundary == .start ? trimStart : trimEnd
    }

    func select(_ boundary: TrimBoundary, at time: Double) {
        if boundary == .start { setTrimStart(time) }
        else { setTrimEnd(time) }
    }

    func step(_ boundary: TrimBoundary, frames: Int) {
        select(boundary, at: time(for: boundary) + Double(frames) * frameDuration)
    }

    func skipOpening(seconds: Double = 1.5) { setTrimStart(max(trimStart, seconds)) }
    func includeOpening() { setTrimStart(0) }

    func setTrimStart(_ time: Double) {
        guard let index = selectedClipIndex else { return }
        let value = min(trimEnd - frameDuration, snapped(time))
        trimStart = max(0, value)
        clips[index].start = trimStart
    }

    func setTrimEnd(_ time: Double) {
        guard let index = selectedClipIndex else { return }
        let value = max(trimStart + frameDuration, snapped(time))
        trimEnd = min(clips[index].sourceDuration, value)
        clips[index].end = trimEnd
    }

    func selectClip(_ id: UUID) {
        guard let clip = clips.first(where: { $0.id == id }) else { return }
        selectedClipID = id
        trimStart = clip.start
        trimEnd = clip.end
        isSynchronizingSelection = true
        speed = clip.speed
        volume = clip.volume
        isMuted = clip.isMuted
        transition = clip.transition
        transitionDuration = clip.transitionDuration
        isSynchronizingSelection = false
    }

    @discardableResult
    func split(at time: Double) -> Bool {
        guard let index = selectedClipIndex else { return false }
        let clip = clips[index]
        let splitTime = snapped(time)
        guard splitTime > clip.start + frameDuration,
              splitTime < clip.end - frameDuration else { return false }
        registerTimelineChange()
        var left = clip
        left = VideoClip(
            sourceURL: clip.sourceURL,
            sourceDuration: clip.sourceDuration,
            start: clip.start,
            end: splitTime,
            speed: clip.speed,
            volume: clip.volume,
            isMuted: clip.isMuted
        )
        left.motion = clip.motion?.sliced(from: 0, to: (splitTime - clip.start) / clip.duration)
        let right = VideoClip(
            sourceURL: clip.sourceURL,
            sourceDuration: clip.sourceDuration,
            start: splitTime,
            end: clip.end,
            speed: clip.speed,
            volume: clip.volume,
            isMuted: clip.isMuted,
            transition: clip.transition,
            transitionDuration: clip.transitionDuration,
            motion: clip.motion?.sliced(from: (splitTime - clip.start) / clip.duration, to: 1)
        )
        clips.replaceSubrange(index...index, with: [left, right])
        selectClip(right.id)
        return true
    }

    func deleteSelectedClip() {
        guard clips.count > 1, let index = selectedClipIndex else { return }
        registerTimelineChange()
        clips.remove(at: index)
        selectClip(clips[min(index, clips.count - 1)].id)
    }

    func duplicateSelectedClip() {
        guard let index = selectedClipIndex else { return }
        registerTimelineChange()
        let source = clips[index]
        let copy = VideoClip(
            sourceURL: source.sourceURL,
            sourceDuration: source.sourceDuration,
            start: source.start,
            end: source.end,
            speed: source.speed,
            volume: source.volume,
            isMuted: source.isMuted,
            transition: source.transition,
            transitionDuration: source.transitionDuration,
            motion: source.motion
        )
        clips.insert(copy, at: index + 1)
        selectClip(copy.id)
    }

    func moveSelected(by offset: Int) {
        guard let index = selectedClipIndex else { return }
        let destination = index + offset
        guard clips.indices.contains(destination) else { return }
        registerTimelineChange()
        let moving = clips.remove(at: index)
        clips.insert(moving, at: destination)
    }

    func addClips(urls: [URL]) async throws {
        guard !urls.isEmpty else { return }
        var additions: [VideoClip] = []
        for url in urls {
            let info = try await ffmpeg.inspect(url: url)
            let clipDuration = max(info.duration, frameDuration)
            additions.append(VideoClip(
                sourceURL: url,
                sourceDuration: clipDuration,
                start: 0,
                end: clipDuration
            ))
        }
        registerTimelineChange()
        let insertion = min((selectedClipIndex ?? clips.count - 1) + 1, clips.count)
        clips.insert(contentsOf: additions, at: insertion)
        if let first = additions.first { selectClip(first.id) }
    }

    func addBackgroundAudio(url: URL) async throws {
        let info = try await FFmpegMediaInspector().inspect(url: url)
        guard info.hasAudio else { throw ExportError.missingAudio }
        let trackDuration = max(info.duration, 0.1)
        registerTimelineChange()
        audioTracks.append(ProjectAudioTrack(
            sourceURL: url,
            sourceDuration: trackDuration,
            trimEnd: trackDuration
        ))
    }

    func deleteAudioTrack(_ id: UUID) { registerTimelineChange(); audioTracks.removeAll { $0.id == id } }

    func updateAudioTrack(
        _ id: UUID,
        timelineStart: Double? = nil,
        volume: Double? = nil,
        fadeIn: Double? = nil,
        fadeOut: Double? = nil,
        loop: Bool? = nil,
        trimStart: Double? = nil,
        trimEnd: Double? = nil
    ) {
        guard let index = audioTracks.firstIndex(where: { $0.id == id }) else { return }
        registerTimelineChange()
        if let timelineStart { audioTracks[index].timelineStart = max(0, timelineStart) }
        if let volume { audioTracks[index].volume = min(max(volume, 0), 2) }
        if let fadeIn { audioTracks[index].fadeIn = min(max(fadeIn, 0), audioTracks[index].duration / 2) }
        if let fadeOut { audioTracks[index].fadeOut = min(max(fadeOut, 0), audioTracks[index].duration / 2) }
        if let loop { audioTracks[index].loop = loop }
        if let trimStart { audioTracks[index].trimStart = min(audioTracks[index].trimEnd - 0.05, max(0, trimStart)) }
        if let trimEnd { audioTracks[index].trimEnd = max(audioTracks[index].trimStart + 0.05, min(audioTracks[index].sourceDuration, trimEnd)) }
        audioTracks[index].fadeIn = min(audioTracks[index].fadeIn, audioTracks[index].duration / 2)
        audioTracks[index].fadeOut = min(audioTracks[index].fadeOut, audioTracks[index].duration / 2)
    }

    func addCaption(text: String, at time: Double, duration: Double = 3) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        registerTimelineChange()
        captions.append(TimedCaption(
            text: clean,
            start: min(max(time, 0), projectDuration),
            duration: min(max(duration, 0.2), max(projectDuration, 0.2)),
            position: overlayPosition
        ))
        captions.sort { $0.start < $1.start }
    }

    func deleteCaption(_ id: UUID) { registerTimelineChange(); captions.removeAll { $0.id == id } }

    func addAnnotation(
        points: [VideoAnnotationPoint],
        color: VideoAnnotationColor,
        width: Double,
        at time: Double,
        duration: Double
    ) {
        guard points.count > 1 else { return }
        annotations.append(VideoAnnotationStroke(
            points: points,
            color: color,
            width: min(max(width, 1), 24),
            start: min(max(time, 0), projectDuration),
            duration: min(max(duration, 0.2), max(projectDuration, 0.2))
        ))
    }

    func deleteAnnotation(_ id: UUID) { annotations.removeAll { $0.id == id } }
    func clearAnnotations() { annotations.removeAll() }

    func updateCaption(
        _ id: UUID,
        text: String? = nil,
        start: Double? = nil,
        duration: Double? = nil,
        position: VideoTextPosition? = nil
    ) {
        guard let index = captions.firstIndex(where: { $0.id == id }) else { return }
        registerTimelineChange()
        if let text {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            captions[index].text = clean.isEmpty ? captions[index].text : clean
        }
        if let start {
            captions[index].start = min(max(start, 0), projectDuration)
        }
        if let duration {
            let remaining = max(0.2, projectDuration - captions[index].start)
            captions[index].duration = min(max(duration, 0.2), remaining)
        }
        if let position {
            captions[index].position = position
        }
        captions.sort { $0.start < $1.start }
    }

    func insertFreezeFrame(at time: Double, duration freezeDuration: Double = 1) async throws {
        guard let selectedClip, let index = selectedClipIndex else { return }
        let image = try await ffmpeg.thumbnails(
            url: selectedClip.sourceURL,
            at: [min(max(time, selectedClip.start), selectedClip.end)],
            maximumSize: CGSize(width: 2560, height: 2560)
        ).first
        guard let image else { throw VideoProcessingError.thumbnailUnavailable }
        try SharedStorage.prepare()
        let output = SharedStorage.exportDirectory
            .appendingPathComponent("Freeze-\(UUID().uuidString).mov")
        try await Self.writeFreezeVideo(
            image: image,
            outputURL: output,
            duration: min(max(freezeDuration, 0.2), 10),
            frameRate: max(15, Int(frameRate.rounded()))
        )
        registerTimelineChange()
        let clip = VideoClip(
            sourceURL: output,
            sourceDuration: min(max(freezeDuration, 0.2), 10),
            start: 0,
            end: min(max(freezeDuration, 0.2), 10),
            isMuted: true
        )
        clips.insert(clip, at: index + 1)
        selectClip(clip.id)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(makeSnapshot())
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(makeSnapshot())
        restore(next)
    }

    func resetTimeline() {
        registerTimelineChange()
        let clip = VideoClip(
            sourceURL: sourceURL,
            sourceDuration: duration,
            start: 0,
            end: duration
        )
        clips = [clip]
        selectClip(clip.id)
    }

    func saveDraft() {
        guard !isRestoringDraft else { return }
        do {
            try VideoProjectStore.save(snapshot: makeSnapshot(), for: sourceURL)
            draftError = nil
        } catch {
            draftError = "草稿保存失败：\(error.localizedDescription)"
        }
    }

    func snapped(_ time: Double) -> Double {
        let sourceDuration = selectedClip?.sourceDuration ?? duration
        let frame = (min(max(time, 0), sourceDuration) * frameRate).rounded()
        return min(sourceDuration, max(0, frame / frameRate))
    }

    func timecode(_ time: Double) -> String {
        let roundedRate = max(1, Int(frameRate.rounded()))
        let totalFrames = max(0, Int((max(0, time.isFinite ? time : 0) * frameRate).rounded()))
        let frames = totalFrames % roundedRate
        let totalSeconds = totalFrames / roundedRate
        return String(
            format: "%02d:%02d:%02d:%02d",
            totalSeconds / 3600,
            (totalSeconds / 60) % 60,
            totalSeconds % 60,
            frames
        )
    }

    var hasVisualAdjustments: Bool {
        abs(brightness) > 0.001
            || abs(contrast - 1) > 0.001
            || abs(saturation - 1) > 0.001
            || abs(exposure) > 0.001
            || abs(warmth) > 0.001
            || abs(sharpness) > 0.001
            || abs(vignette) > 0.001
    }

    var hasVideoComposition: Bool {
        hasVisualAdjustments
            || rotationSteps % 4 != 0
            || isMirrored
            || canvasRatio != .original
            || !overlayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !captions.isEmpty
            || !annotations.isEmpty
            || !redactions.isEmpty
            || exportSize != .source
            || exportFrameRate > 0
    }

    func apply(_ look: VideoLook) {
        registerTimelineChange()
        self.look = look
        let controls = look.controls
        brightness = controls.brightness
        contrast = controls.contrast
        saturation = controls.saturation
        warmth = controls.warmth
        vignette = controls.vignette
    }

    func resetVisualAdjustments() {
        apply(.original)
        exposure = 0
        sharpness = 0
    }

    func rotateClockwise() { registerTimelineChange(); rotationSteps = (rotationSteps + 1) % 4 }

    func effectiveTransitionDuration(after index: Int) -> Double {
        guard clips.indices.contains(index), clips.indices.contains(index + 1),
              clips[index].transition != .none else { return 0 }
        return min(
            clips[index].transitionDuration,
            clips[index].timelineDuration * 0.45,
            clips[index + 1].timelineDuration * 0.45
        )
    }

    func projectTime(forSelectedSourceTime sourceTime: Double) -> Double {
        guard let selectedIndex = selectedClipIndex else { return 0 }
        var value = 0.0
        if selectedIndex > 0 {
            for index in 0..<selectedIndex {
                value += clips[index].timelineDuration
                if clips.indices.contains(index + 1) {
                    value -= effectiveTransitionDuration(after: index)
                }
            }
        }
        let clip = clips[selectedIndex]
        value += max(0, min(sourceTime, clip.end) - clip.start) / max(clip.speed, 0.05)
        return min(max(value, 0), projectDuration)
    }

    var technicalSummary: String? {
        guard let videoInfo else { return nil }
        let codec = videoInfo.videoCodec.uppercased()
        let fps = Int(videoInfo.frameRate.rounded())
        return "\(videoInfo.width)×\(videoInfo.height)  \(fps) FPS  \(codec)"
    }

    func loadFFmpegPreview(frameCount: Int = 18) async {
        let previewURL = selectedSourceURL
        guard previewedSourceURL != previewURL || timelineFrames.isEmpty else { return }
        previewedSourceURL = previewURL
        timelineFrames = []
        do {
            async let info = ffmpeg.inspect(url: previewURL)
            let count = max(frameCount, 2)
            let previewDuration = selectedClip?.sourceDuration ?? duration
            let finalFrameTime = max(0, previewDuration - 1 / 600)
            let times = (0..<count).map { finalFrameTime * Double($0) / Double(count - 1) }
            async let frames = ffmpeg.thumbnails(
                url: previewURL,
                at: times,
                maximumSize: CGSize(width: 240, height: 160)
            )
            let (loadedInfo, loadedFrames) = try await (info, frames)
            try Task.checkCancellation()
            guard selectedSourceURL == previewURL else { return }
            videoInfo = loadedInfo
            timelineFrames = zip(times, loadedFrames).enumerated().map { index, item in
                VideoTimelineFrame(id: index, time: item.0, image: UIImage(cgImage: item.1))
            }
            setTrimStart(trimStart)
            setTrimEnd(trimEnd)
        } catch {
            // The native editor remains available when an uncommon codec cannot provide thumbnails.
        }
    }

    func makeVideoComposition(for asset: AVAsset) async throws -> AVVideoComposition {
        let targetSize = try await renderSize(for: asset)
        let brightness = Float(brightness)
        let contrast = Float(contrast)
        let saturation = Float(saturation)
        let exposure = Float(exposure)
        let warmth = Float(warmth)
        let sharpness = Float(sharpness)
        let vignette = Float(vignette)
        let rotationSteps = rotationSteps
        let mirrored = isMirrored
        let ratio = canvasRatio.value
        let text = overlayText.trimmingCharacters(in: .whitespacesAndNewlines)
        let textPosition = overlayPosition
        let textOpacity = Float(overlayOpacity)
        let textImage = Self.makeTextImage(text, renderSize: targetSize, opacity: textOpacity)
        let redactions = redactions
        let captionImages = captions.compactMap { caption -> (TimedCaption, CIImage)? in
            guard let image = Self.makeTextImage(caption.text, renderSize: targetSize, opacity: 1) else { return nil }
            return (caption, image)
        }

        let composition = AVMutableVideoComposition(asset: asset) { request in
            let sourceExtent = request.sourceImage.extent
            var image = request.sourceImage.clampedToExtent()
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: brightness,
                kCIInputContrastKey: contrast,
                kCIInputSaturationKey: saturation
            ])
            if abs(exposure) > 0.001 {
                image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposure])
            }
            if abs(warmth) > 0.001 {
                let neutral = CIVector(x: 6500, y: 0)
                let target = CIVector(x: CGFloat(6500 - warmth * 2400), y: 0)
                image = image.applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": neutral,
                    "inputTargetNeutral": target
                ])
            }
            if sharpness > 0.001 {
                image = image.applyingFilter("CISharpenLuminance", parameters: [
                    kCIInputSharpnessKey: sharpness
                ])
            }
            if vignette > 0.001 {
                image = image.applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: vignette,
                    kCIInputRadiusKey: max(sourceExtent.width, sourceExtent.height) * 0.65
                ])
            }

            image = image.cropped(to: sourceExtent)
            image = Self.orient(image, rotationSteps: rotationSteps, mirrored: mirrored)
            let crop = Self.cropRect(in: image.extent, ratio: ratio)
            image = image.cropped(to: crop)
            let scaleX = targetSize.width / max(crop.width, 1)
            let scaleY = targetSize.height / max(crop.height, 1)
            image = image.transformed(by: CGAffineTransform(
                translationX: -crop.minX,
                y: -crop.minY
            )).transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

            let time = request.compositionTime.seconds
            for mask in redactions where time >= mask.start && time < mask.start + mask.duration {
                image = mask.applied(to: image, size: targetSize)
            }
            for (caption, bitmap) in captionImages where time >= caption.start && time < caption.start + caption.duration {
                let y: CGFloat
                switch caption.position {
                case .top: y = targetSize.height * 0.93 - bitmap.extent.height
                case .center: y = (targetSize.height - bitmap.extent.height) / 2
                case .bottom: y = targetSize.height * 0.07
                }
                image = bitmap.transformed(by: CGAffineTransform(
                    translationX: (targetSize.width - bitmap.extent.width) / 2, y: y)).composited(over: image)
            }
            if let textImage {
                let y: CGFloat
                switch textPosition {
                case .top: y = targetSize.height - textImage.extent.height - targetSize.height * 0.07
                case .center: y = (targetSize.height - textImage.extent.height) / 2
                case .bottom: y = targetSize.height * 0.07
                }
                let x = (targetSize.width - textImage.extent.width) / 2
                let placed = textImage.transformed(by: CGAffineTransform(translationX: x, y: y))
                image = placed.composited(over: image)
            }
            request.finish(with: image.cropped(to: CGRect(origin: .zero, size: targetSize)), context: nil)
        }
        composition.renderSize = targetSize
        let fps = exportFrameRate > 0 ? exportFrameRate : max(1, Int(frameRate.rounded()))
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        if !annotations.isEmpty {
            configureTimedOverlays(on: composition, renderSize: targetSize)
        }
        return composition
    }


    /// Project seconds and source seconds are deliberately separate.
    func clipOffset(at index: Int) -> Double {
        guard index > 0 else { return 0 }
        return (0..<min(index, clips.count)).reduce(0) { $0 + clips[$1].timelineDuration - effectiveTransitionDuration(after: $1) }
    }

    func sourcePosition(at projectTime: Double) -> (id: UUID, time: Double)? {
        guard !clips.isEmpty else { return nil }
        let t = min(max(0, projectTime), projectDuration)
        let index = clips.indices.last { clipOffset(at: $0) <= t } ?? 0
        let clip = clips[index]
        return (clip.id, min(clip.end, clip.start + (t - clipOffset(at: index)) * clip.speed))
    }

    func splitProject(at time: Double) -> Bool {
        guard let position = sourcePosition(at: time) else { return false }
        selectClip(position.id)
        return split(at: position.time)
    }

    func checkpoint() { registerTimelineChange() }

    func appendCaptions(_ additions: [TimedCaption]) {
        guard !additions.isEmpty else { return }
        registerTimelineChange()
        captions.append(contentsOf: additions)
        captions.sort { $0.start < $1.start }
    }

    @discardableResult
    func addRedaction(at time: Double) -> UUID {
        registerTimelineChange()
        let start = min(max(0, time), max(0, projectDuration - 0.1))
        let mask = VideoRedaction(start: start, duration: min(3, projectDuration - start))
        redactions.append(mask)
        return mask.id
    }

    func updateRedaction(_ mask: VideoRedaction, recordUndo: Bool = true) {
        guard let index = redactions.firstIndex(where: { $0.id == mask.id }) else { return }
        if recordUndo { registerTimelineChange() }
        var value = mask
        value.width = min(1, max(0.03, value.width)); value.height = min(1, max(0.03, value.height))
        value.x = min(1 - value.width, max(0, value.x)); value.y = min(1 - value.height, max(0, value.y))
        value.start = min(max(0, value.start), max(0, projectDuration - 0.1))
        value.duration = min(max(0.1, value.duration), projectDuration - value.start)
        redactions[index] = value
    }

    func deleteRedaction(_ id: UUID) {
        registerTimelineChange()
        redactions.removeAll { $0.id == id }
    }

    private var previewTimelineURL: URL?
    private var previewTimelineKey: Data?
    private struct TimelineKey: Encodable {
        let clips: [VideoClip]
        let audio: [ProjectAudioTrack]
        let fadeIn: Double
        let fadeOut: Double
        let fps: Int
    }

    func makePreview() async throws -> AVPlayerItem {
        let key = try JSONEncoder().encode(TimelineKey(clips: clips, audio: audioTracks,
                                  fadeIn: fadeIn, fadeOut: fadeOut, fps: exportFrameRate))
        if previewTimelineKey != key || previewTimelineURL == nil {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("EditorPreview-\(UUID()).mov")
            do {
                try await renderTimeline(to: url)
                try Task.checkCancellation()
                if let old = previewTimelineURL { try? FileManager.default.removeItem(at: old) }
                previewTimelineURL = url
                previewTimelineKey = key
            } catch {
                try? FileManager.default.removeItem(at: url)
                throw error
            }
        }
        guard let url = previewTimelineURL else { throw ExportError.exportFailed }
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.videoComposition = try await makeVideoComposition(for: asset)
        return item
    }

    func cleanupPreview() {
        if let url = previewTimelineURL { try? FileManager.default.removeItem(at: url) }
        previewTimelineURL = nil
        previewTimelineKey = nil
    }

    func transcriptionAudio() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TranscriptTimeline-\(UUID()).mov")
        do { try await renderTimeline(to: url); return url }
        catch { try? FileManager.default.removeItem(at: url); throw error }
    }

    func export() async throws -> URL {
        isExporting = true
        exportProgress = 0.05
        defer {
            isExporting = false
            exportProgress = 0
        }

        try SharedStorage.prepare()
        let output = SharedStorage.exportDirectory
            .appendingPathComponent("Edit-\(UUID().uuidString).mp4")
        let timelineOutput = SharedStorage.exportDirectory
            .appendingPathComponent("Timeline-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: output)
        try? FileManager.default.removeItem(at: timelineOutput)
        defer { try? FileManager.default.removeItem(at: timelineOutput) }

        if let only = clips.first,
           clips.count == 1,
           only.sourceURL == sourceURL,
           only.start <= 0.001,
           only.speed == 1,
           only.transition == .none,
           only.motion == nil,
           !only.isMuted,
           abs(only.volume - 1) < 0.001,
           !hasVideoComposition,
           audioTracks.isEmpty,
           captions.isEmpty,
           annotations.isEmpty,
           fadeIn == 0,
           fadeOut == 0,
           exportCodec == .source {
            let result = try await ffmpeg.fastExport(
                    inputURL: sourceURL,
                    outputURL: output,
                    startTime: only.start,
                    endTime: only.end,
                    keepAudio: true
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in self?.exportProgress = progress }
                }
            return result.url
        }

        try await renderTimeline(to: timelineOutput)
        exportProgress = 0.68

        let timelineAsset = AVURLAsset(url: timelineOutput)
        let preset = exportCodec == .hevc
            ? AVAssetExportPresetHEVCHighestQuality
            : AVAssetExportPresetHighestQuality
        guard let exporter = AVAssetExportSession(asset: timelineAsset, presetName: preset) else {
            throw ExportError.exportFailed
        }
        if hasVideoComposition || !captions.isEmpty || !annotations.isEmpty {
            exporter.videoComposition = try await makeVideoComposition(for: timelineAsset)
        }
        exporter.shouldOptimizeForNetworkUse = true
        exportProgress = 0.78
        try await exporter.export(to: output, as: .mp4)
        exportProgress = 1
        return output
    }

    private struct PlacedClip {
        let videoTrack: AVMutableCompositionTrack
        let audioTrack: AVMutableCompositionTrack?
        let start: CMTime
        let duration: CMTime
        let transform: CGAffineTransform
        let volume: Float
        let isMuted: Bool
        let motion: ClipMotion?

        var end: CMTime { start + duration }
    }

    private func renderTimeline(to output: URL) async throws {
        let composition = AVMutableComposition()
        guard let firstClip = clips.first else { throw ExportError.missingVideo }
        let baseSize = try await sourceRenderSize(for: firstClip.sourceURL)
        var placements: [PlacedClip] = []
        var cursor = CMTime.zero

        for (index, clip) in clips.enumerated() where clip.duration >= frameDuration {
            let source = AVURLAsset(url: clip.sourceURL)
            guard let sourceVideo = try await source.loadTracks(withMediaType: .video).first,
                  let videoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else { throw ExportError.missingVideo }
            let overlap = index > 0 ? effectiveTransitionDuration(after: index - 1) : 0
            let insertionTime = cursor - CMTime(seconds: overlap, preferredTimescale: 60_000)
            let range = CMTimeRange(
                start: CMTime(seconds: clip.start, preferredTimescale: 60_000),
                duration: CMTime(seconds: clip.duration, preferredTimescale: 60_000)
            )
            try videoTrack.insertTimeRange(range, of: sourceVideo, at: insertionTime)
            let targetDuration = CMTimeMultiplyByFloat64(range.duration, multiplier: 1 / clip.speed)
            if abs(clip.speed - 1) > 0.001 {
                videoTrack.scaleTimeRange(
                    CMTimeRange(start: insertionTime, duration: range.duration),
                    toDuration: targetDuration
                )
            }

            var insertedAudioTrack: AVMutableCompositionTrack?
            if !clip.isMuted,
               let sourceAudio = try await source.loadTracks(withMediaType: .audio).first,
               let audioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                try audioTrack.insertTimeRange(range, of: sourceAudio, at: insertionTime)
                if abs(clip.speed - 1) > 0.001 {
                    audioTrack.scaleTimeRange(
                        CMTimeRange(start: insertionTime, duration: range.duration),
                        toDuration: targetDuration
                    )
                }
                insertedAudioTrack = audioTrack
            }

            placements.append(PlacedClip(
                videoTrack: videoTrack,
                audioTrack: insertedAudioTrack,
                start: insertionTime,
                duration: targetDuration,
                transform: try await aspectFillTransform(for: sourceVideo, targetSize: baseSize),
                volume: Float(clip.volume),
                isMuted: clip.isMuted,
                motion: clip.motion
            ))
            cursor = insertionTime + targetDuration
        }
        guard cursor.seconds > 0 else { throw ExportError.exportFailed }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = baseSize
        let fps = max(1, exportFrameRate > 0 ? exportFrameRate : Int(frameRate.rounded()))
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        videoComposition.customVideoCompositorClass = EditorVideoCompositor.self
        videoComposition.instructions = makeTimelineInstructions(placements: placements)

        let audioMix = AVMutableAudioMix()
        var audioParameters = makeClipAudioParameters(placements: placements)
        audioParameters.append(contentsOf: try await insertBackgroundAudio(
            into: composition,
            projectDuration: cursor
        ))
        audioMix.inputParameters = audioParameters

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else { throw ExportError.exportFailed }
        exporter.videoComposition = videoComposition
        if !audioParameters.isEmpty { exporter.audioMix = audioMix }
        try await exporter.export(to: output, as: .mov)
    }

    private func makeTimelineInstructions(
        placements: [PlacedClip]
    ) -> [AVVideoCompositionInstructionProtocol] {
        func layer(_ index: Int) -> EditorVideoLayer {
            let clip = placements[index]
            return EditorVideoLayer(trackID: clip.videoTrack.trackID, transform: clip.transform,
                                    start: clip.start.seconds, duration: clip.duration.seconds, motion: clip.motion)
        }
        var instructions: [EditorVideoInstruction] = []
        for index in placements.indices {
            let incoming = index > 0 ? effectiveTransitionDuration(after: index - 1) : 0
            let outgoing = index < placements.count - 1 ? effectiveTransitionDuration(after: index) : 0
            let start = placements[index].start + CMTime(seconds: incoming, preferredTimescale: 60_000)
            let end = placements[index].end - CMTime(seconds: outgoing, preferredTimescale: 60_000)
            if end > start {
                instructions.append(EditorVideoInstruction(range: CMTimeRange(start: start, end: end), layers: [layer(index)]))
            }
            if outgoing > 0, placements.indices.contains(index + 1) {
                instructions.append(EditorVideoInstruction(range: CMTimeRange(start: placements[index + 1].start,
                    duration: CMTime(seconds: outgoing, preferredTimescale: 60_000)),
                    layers: [layer(index), layer(index + 1)], transition: clips[index].transition))
            }
        }
        return instructions.sorted { $0.timeRange.start < $1.timeRange.start }
    }

    private func makeClipAudioParameters(
        placements: [PlacedClip]
    ) -> [AVAudioMixInputParameters] {
        var result: [AVAudioMixInputParameters] = []
        for index in placements.indices {
            guard let track = placements[index].audioTrack, !placements[index].isMuted else { continue }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            let target = placements[index].volume
            parameters.setVolume(target, at: placements[index].start)
            let incoming = index > 0 ? effectiveTransitionDuration(after: index - 1) : 0
            let outgoing = index < placements.count - 1 ? effectiveTransitionDuration(after: index) : 0
            if incoming > 0 {
                parameters.setVolumeRamp(
                    fromStartVolume: 0,
                    toEndVolume: target,
                    timeRange: CMTimeRange(
                        start: placements[index].start,
                        duration: CMTime(seconds: incoming, preferredTimescale: 60_000)
                    )
                )
            }
            if outgoing > 0 {
                parameters.setVolumeRamp(
                    fromStartVolume: target,
                    toEndVolume: 0,
                    timeRange: CMTimeRange(
                        start: placements[index].end - CMTime(seconds: outgoing, preferredTimescale: 60_000),
                        duration: CMTime(seconds: outgoing, preferredTimescale: 60_000)
                    )
                )
            }
            if index == 0, fadeIn > 0 {
                parameters.setVolumeRamp(
                    fromStartVolume: 0,
                    toEndVolume: target,
                    timeRange: CMTimeRange(
                        start: .zero,
                        duration: CMTime(seconds: min(fadeIn, placements[index].duration.seconds / 2), preferredTimescale: 600)
                    )
                )
            }
            if index == placements.count - 1, fadeOut > 0 {
                let fade = CMTime(
                    seconds: min(fadeOut, placements[index].duration.seconds / 2),
                    preferredTimescale: 600
                )
                parameters.setVolumeRamp(
                    fromStartVolume: target,
                    toEndVolume: 0,
                    timeRange: CMTimeRange(start: placements[index].end - fade, duration: fade)
                )
            }
            result.append(parameters)
        }
        return result
    }

    private func insertBackgroundAudio(
        into composition: AVMutableComposition,
        projectDuration: CMTime
    ) async throws -> [AVAudioMixInputParameters] {
        var parameters: [AVAudioMixInputParameters] = []
        for background in audioTracks {
            let asset = AVURLAsset(url: background.sourceURL)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first,
                  let track = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else { continue }
            var cursor = CMTime(seconds: background.timelineStart, preferredTimescale: 60_000)
            var insertedRanges: [CMTimeRange] = []
            repeat {
                let remaining = projectDuration.seconds - cursor.seconds
                guard remaining > 0.01 else { break }
                let insertDuration = min(background.duration, remaining)
                let range = CMTimeRange(
                    start: CMTime(seconds: background.trimStart, preferredTimescale: 60_000),
                    duration: CMTime(seconds: insertDuration, preferredTimescale: 60_000)
                )
                try track.insertTimeRange(range, of: source, at: cursor)
                insertedRanges.append(CMTimeRange(start: cursor, duration: range.duration))
                cursor = cursor + range.duration
            } while background.loop
            let input = AVMutableAudioMixInputParameters(track: track)
            configureBackgroundVolume(input, track: background, insertedRanges: insertedRanges)
            parameters.append(input)
        }
        return parameters
    }

    private func configureBackgroundVolume(
        _ input: AVMutableAudioMixInputParameters,
        track: ProjectAudioTrack,
        insertedRanges: [CMTimeRange]
    ) {
        let target = Float(track.volume)
        input.setVolume(target, at: .zero)
        guard !insertedRanges.isEmpty else { return }

        let first = insertedRanges[0]
        if track.fadeIn > 0 {
            let fade = CMTime(
                seconds: min(track.fadeIn, first.duration.seconds / 2),
                preferredTimescale: 600
            )
            input.setVolumeRamp(
                fromStartVolume: 0,
                toEndVolume: target,
                timeRange: CMTimeRange(start: first.start, duration: fade)
            )
        }

        guard track.fadeOut > 0, let last = insertedRanges.last else { return }
        let fade = CMTime(
            seconds: min(track.fadeOut, last.duration.seconds / 2),
            preferredTimescale: 600
        )
        input.setVolumeRamp(
            fromStartVolume: target,
            toEndVolume: 0,
            timeRange: CMTimeRange(start: last.end - fade, duration: fade)
        )
    }

    private func sourceRenderSize(for url: URL) async throws -> CGSize {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.missingVideo
        }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let rect = CGRect(origin: .zero, size: natural).applying(transform)
        var size = CGSize(width: abs(rect.width), height: abs(rect.height))
        let maxEdge = max(size.width, size.height)
        if maxEdge > 2560 {
            let scale = 2560 / maxEdge
            size = CGSize(width: size.width * scale, height: size.height * scale)
        }
        return CGSize(width: Self.even(size.width), height: Self.even(size.height))
    }

    private func aspectFillTransform(
        for track: AVAssetTrack,
        targetSize: CGSize
    ) async throws -> CGAffineTransform {
        let natural = try await track.load(.naturalSize)
        let preferred = try await track.load(.preferredTransform)
        let orientedRect = CGRect(origin: .zero, size: natural).applying(preferred)
        let orientedSize = CGSize(width: abs(orientedRect.width), height: abs(orientedRect.height))
        let scale = max(
            targetSize.width / max(orientedSize.width, 1),
            targetSize.height / max(orientedSize.height, 1)
        )
        let centeredX = (targetSize.width - orientedSize.width * scale) / 2
        let centeredY = (targetSize.height - orientedSize.height * scale) / 2
        let videoTransform = preferred
            .concatenating(CGAffineTransform(
                translationX: -orientedRect.minX,
                y: -orientedRect.minY
            ))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: centeredX, y: centeredY))
        // AVFoundation track transforms use top-left coordinates; Core Image uses
        // bottom-left. Convert both spaces explicitly, especially for 90/270° clips.
        return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: natural.height)
            .concatenating(videoTransform)
            .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: targetSize.height))
    }

    private func renderSize(for asset: AVAsset) async throws -> CGSize {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.missingVideo
        }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformed = natural.applying(transform)
        var size = CGSize(width: abs(transformed.width), height: abs(transformed.height))
        if size.width < 2 || size.height < 2 {
            size = CGSize(width: abs(natural.width), height: abs(natural.height))
        }
        if rotationSteps % 2 != 0 {
            size = CGSize(width: size.height, height: size.width)
        }
        if let ratio = canvasRatio.value {
            if size.width / size.height > ratio {
                size.width = size.height * ratio
            } else {
                size.height = size.width / ratio
            }
        }
        if let longEdge = exportSize.longEdge {
            let scale = longEdge / max(size.width, size.height)
            size = CGSize(width: size.width * scale, height: size.height * scale)
        }
        return CGSize(width: Self.even(size.width), height: Self.even(size.height))
    }

    private var isContinuousEdit = false
    func beginContinuousEdit() {
        guard !isContinuousEdit else { return }
        registerTimelineChange(); isContinuousEdit = true
    }
    func endContinuousEdit() { isContinuousEdit = false }

    private func registerTimelineChange() {
        guard !isContinuousEdit else { return }
        undoStack.append(makeSnapshot())
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func restore(_ snapshot: VideoProjectSnapshot) {
        applySnapshot(snapshot)
        scheduleDraftSave()
    }

    private func syncSelectedClipSettings() {
        guard !isSynchronizingSelection, let index = selectedClipIndex else { return }
        clips[index].speed = min(max(speed, 0.25), 4)
        clips[index].volume = min(max(volume, 0), 2)
        clips[index].isMuted = isMuted
        clips[index].transition = transition
        clips[index].transitionDuration = min(max(transitionDuration, 0.1), 2)
    }

    private func scheduleDraftSave() {
        guard !isRestoringDraft else { return }
        revision &+= 1
        draftSaveTask?.cancel()
        draftSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.saveDraft()
        }
    }

    private func restoreDraftIfAvailable() {
        guard let snapshot = VideoProjectStore.load(for: sourceURL) else { return }
        applySnapshot(snapshot)
    }

    private func applySnapshot(_ snapshot: VideoProjectSnapshot) {
        let availableClips = snapshot.clips.filter {
            FileManager.default.fileExists(atPath: $0.sourceURL.path)
        }
        guard !availableClips.isEmpty else { return }

        isRestoringDraft = true
        clips = availableClips
        selectedClipID = clips.contains(where: { $0.id == snapshot.selectedClipID })
            ? snapshot.selectedClipID
            : clips[0].id
        audioTracks = snapshot.audioTracks.filter {
            FileManager.default.fileExists(atPath: $0.sourceURL.path)
        }
        captions = snapshot.captions
        redactions = snapshot.redactions ?? []
        annotations = snapshot.annotations ?? []
        fadeIn = snapshot.fadeIn
        fadeOut = snapshot.fadeOut
        look = snapshot.look
        brightness = snapshot.brightness
        contrast = snapshot.contrast
        saturation = snapshot.saturation
        exposure = snapshot.exposure
        warmth = snapshot.warmth
        sharpness = snapshot.sharpness
        vignette = snapshot.vignette
        rotationSteps = snapshot.rotationSteps
        isMirrored = snapshot.isMirrored
        canvasRatio = snapshot.canvasRatio
        overlayText = snapshot.overlayText
        overlayPosition = snapshot.overlayPosition
        overlayOpacity = snapshot.overlayOpacity
        exportSize = snapshot.exportSize
        exportCodec = snapshot.exportCodec
        exportFrameRate = snapshot.exportFrameRate
        selectClip(selectedClipID)
        isRestoringDraft = false
    }

    private func makeSnapshot() -> VideoProjectSnapshot {
        VideoProjectSnapshot(
            clips: clips,
            selectedClipID: selectedClipID,
            audioTracks: audioTracks,
            captions: captions,
            annotations: annotations,
            redactions: redactions,
            fadeIn: fadeIn,
            fadeOut: fadeOut,
            look: look,
            brightness: brightness,
            contrast: contrast,
            saturation: saturation,
            exposure: exposure,
            warmth: warmth,
            sharpness: sharpness,
            vignette: vignette,
            rotationSteps: rotationSteps,
            isMirrored: isMirrored,
            canvasRatio: canvasRatio,
            overlayText: overlayText,
            overlayPosition: overlayPosition,
            overlayOpacity: overlayOpacity,
            exportSize: exportSize,
            exportCodec: exportCodec,
            exportFrameRate: exportFrameRate
        )
    }

    private func configureTimedOverlays(
        on composition: AVMutableVideoComposition,
        renderSize: CGSize
    ) {
        let parentLayer = CALayer()
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)

        for annotation in annotations where annotation.points.count > 1 {
            let path = UIBezierPath()
            let first = annotation.points[0]
            path.move(to: CGPoint(
                x: first.x * renderSize.width,
                y: (1 - first.y) * renderSize.height
            ))
            for point in annotation.points.dropFirst() {
                path.addLine(to: CGPoint(
                    x: point.x * renderSize.width,
                    y: (1 - point.y) * renderSize.height
                ))
            }
            let shape = CAShapeLayer()
            shape.path = path.cgPath
            shape.fillColor = UIColor.clear.cgColor
            shape.strokeColor = annotation.color.uiColor.cgColor
            shape.lineWidth = max(2, renderSize.width * CGFloat(annotation.width / 390))
            shape.lineCap = .round
            shape.lineJoin = .round
            shape.opacity = 0

            let visibility = CAKeyframeAnimation(keyPath: "opacity")
            visibility.values = [0, 1, 1, 0]
            visibility.keyTimes = [0, 0.03, 0.97, 1]
            visibility.beginTime = AVCoreAnimationBeginTimeAtZero + annotation.start
            visibility.duration = max(0.2, annotation.duration)
            visibility.fillMode = .both
            visibility.isRemovedOnCompletion = false
            shape.add(visibility, forKey: "annotationVisibility")
            parentLayer.addSublayer(shape)
        }
        composition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    nonisolated private static func writeFreezeVideo(
        image: CGImage,
        outputURL: URL,
        duration: Double,
        frameRate: Int
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try? FileManager.default.removeItem(at: outputURL)
            let width = max(2, image.width / 2 * 2)
            let height = max(2, image.height / 2 * 2)
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: max(4_000_000, width * height * 3),
                    AVVideoExpectedSourceFrameRateKey: frameRate
                ]
            ])
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height
                ]
            )
            guard writer.canAdd(input) else { throw ExportError.exportFailed }
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? ExportError.exportFailed }
            writer.startSession(atSourceTime: .zero)
            guard let pool = adaptor.pixelBufferPool else { throw ExportError.exportFailed }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                  let buffer else { throw ExportError.exportFailed }
            CIContext(options: [.cacheIntermediates: false]).render(
                CIImage(cgImage: image),
                to: buffer,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            let frameCount = max(1, Int((duration * Double(frameRate)).rounded()))
            for frame in 0..<frameCount {
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(2))
                }
                guard adaptor.append(
                    buffer,
                    withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(frameRate))
                ) else { throw writer.error ?? ExportError.exportFailed }
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? ExportError.exportFailed }
        }.value
    }

    nonisolated private static func even(_ value: CGFloat) -> CGFloat {
        max(2, CGFloat(Int(value.rounded()) / 2 * 2))
    }

    nonisolated private static func orient(
        _ input: CIImage,
        rotationSteps: Int,
        mirrored: Bool
    ) -> CIImage {
        var image = input
        if mirrored {
            let extent = image.extent
            image = image.transformed(by: CGAffineTransform(
                a: -1,
                b: 0,
                c: 0,
                d: 1,
                tx: extent.minX + extent.maxX,
                ty: 0
            ))
        }
        let steps = ((rotationSteps % 4) + 4) % 4
        if steps > 0 {
            let angle = CGFloat(steps) * -.pi / 2
            let extent = image.extent
            let center = CGPoint(x: extent.midX, y: extent.midY)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: angle)
                .translatedBy(x: -center.x, y: -center.y)
            image = image.transformed(by: transform)
            let rotatedExtent = image.extent
            image = image.transformed(by: CGAffineTransform(
                translationX: -rotatedExtent.minX,
                y: -rotatedExtent.minY
            ))
        }
        return image
    }

    nonisolated private static func cropRect(in extent: CGRect, ratio: CGFloat?) -> CGRect {
        guard let ratio else { return extent }
        var size = extent.size
        if size.width / size.height > ratio {
            size.width = size.height * ratio
        } else {
            size.height = size.width / ratio
        }
        return CGRect(
            x: extent.midX - size.width / 2,
            y: extent.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func makeTextImage(_ text: String, renderSize: CGSize, opacity: Float) -> CIImage? {
        guard !text.isEmpty else { return nil }
        let fontSize = max(6, min(renderSize.width, renderSize.height) * 0.055)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributed = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor.white.withAlphaComponent(CGFloat(opacity)),
            .strokeColor: UIColor.black.withAlphaComponent(CGFloat(opacity) * 0.75),
            .strokeWidth: -3,
            .paragraphStyle: paragraph
        ])
        let maxWidth = renderSize.width * 0.86
        let bounds = attributed.boundingRect(with: CGSize(width: maxWidth, height: renderSize.height * 0.7),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: ceil(maxWidth), height: ceil(bounds.height) + 12)
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            attributed.draw(with: CGRect(x: 0, y: 6, width: size.width, height: size.height - 12),
                            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        return rendered.cgImage.map { CIImage(cgImage: $0) }
    }
}
