import Foundation

struct VideoProjectSnapshot: Codable {
    let version: Int
    let clips: [VideoClip]
    let selectedClipID: UUID
    let audioTracks: [ProjectAudioTrack]
    let captions: [TimedCaption]
    let annotations: [VideoAnnotationStroke]?
    let redactions: [VideoRedaction]?
    let fadeIn: Double
    let fadeOut: Double
    let look: VideoLook
    let brightness: Double
    let contrast: Double
    let saturation: Double
    let exposure: Double
    let warmth: Double
    let sharpness: Double
    let vignette: Double
    let rotationSteps: Int
    let isMirrored: Bool
    let canvasRatio: VideoCanvasRatio
    let overlayText: String
    let overlayPosition: VideoTextPosition
    let overlayOpacity: Double
    let exportSize: VideoExportSize
    let exportCodec: VideoExportCodec
    let exportFrameRate: Int

    init(
        clips: [VideoClip],
        selectedClipID: UUID,
        audioTracks: [ProjectAudioTrack],
        captions: [TimedCaption],
        annotations: [VideoAnnotationStroke],
        redactions: [VideoRedaction] = [],
        fadeIn: Double,
        fadeOut: Double,
        look: VideoLook,
        brightness: Double,
        contrast: Double,
        saturation: Double,
        exposure: Double,
        warmth: Double,
        sharpness: Double,
        vignette: Double,
        rotationSteps: Int,
        isMirrored: Bool,
        canvasRatio: VideoCanvasRatio,
        overlayText: String,
        overlayPosition: VideoTextPosition,
        overlayOpacity: Double,
        exportSize: VideoExportSize,
        exportCodec: VideoExportCodec,
        exportFrameRate: Int
    ) {
        version = 2
        self.clips = clips
        self.selectedClipID = selectedClipID
        self.audioTracks = audioTracks
        self.captions = captions
        self.annotations = annotations
        self.redactions = redactions
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.look = look
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.exposure = exposure
        self.warmth = warmth
        self.sharpness = sharpness
        self.vignette = vignette
        self.rotationSteps = rotationSteps
        self.isMirrored = isMirrored
        self.canvasRatio = canvasRatio
        self.overlayText = overlayText
        self.overlayPosition = overlayPosition
        self.overlayOpacity = overlayOpacity
        self.exportSize = exportSize
        self.exportCodec = exportCodec
        self.exportFrameRate = exportFrameRate
    }
}

enum VideoProjectStore {
    static func load(for sourceURL: URL) -> VideoProjectSnapshot? {
        let url = projectURL(for: sourceURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(VideoProjectSnapshot.self, from: data)
    }

    static func save(snapshot: VideoProjectSnapshot, for sourceURL: URL) throws {
        try SharedStorage.prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: projectURL(for: sourceURL), options: .atomic)
    }

    private static func projectURL(for sourceURL: URL) -> URL {
        let rawName = sourceURL.deletingPathExtension().lastPathComponent
        let safeName = rawName.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "-",
            options: .regularExpression
        )
        let name = safeName.isEmpty ? "Project" : safeName
        return SharedStorage.projectDirectory.appendingPathComponent("\(name).json")
    }
}
