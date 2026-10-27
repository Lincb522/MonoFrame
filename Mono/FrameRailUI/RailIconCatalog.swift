import SwiftUI

enum RailIconCatalog {
    static let aliases: [String: String] = [
        "arrow.clockwise": "rail-refresh",
        "arrow.left.arrow.right": "rail-transcode",
        "arrow.right": "rail-arrow-right",
        "arrow.turn.down.right": "rail-turn-down",
        "arrow.up.forward.app": "rail-export",
        "arrow.up.forward.app.fill": "rail-export",
        "arrow.up.right": "rail-external-link",
        "arrow.uturn.backward": "rail-undo",
        "arrow.uturn.forward": "rail-redo",
        "camera.filters": "rail-filters",
        "captions.bubble": "rail-captions",
        "captions.bubble.fill": "rail-captions",
        "checkmark": "rail-check",
        "checkmark.circle.fill": "rail-status-ok",
        "chevron.left.forwardslash.chevron.right": "rail-code",
        "chevron.right": "rail-arrow-right",
        "circle": "rail-status-pending",
        "clock.arrow.circlepath": "rail-recent",
        "cpu": "rail-chip",
        "dial.medium": "rail-frame-rate",
        "doc.text": "rail-document",
        "exclamationmark.circle.fill": "rail-status-warning",
        "exclamationmark.shield": "rail-shield-warning",
        "film": "rail-video",
        "film.stack": "rail-video-stack",
        "folder": "rail-folder",
        "gearshape": "rail-settings",
        "gobackward.5": "rail-rewind",
        "goforward.5": "rail-forward",
        "hand.raised": "rail-privacy",
        "iphone": "rail-device",
        "magnifyingglass": "rail-search",
        "memorychip": "rail-chip",
        "mic": "rail-microphone",
        "music.note": "rail-music",
        "pause.fill": "rail-pause",
        "photo.on.rectangle": "rail-photo",
        "play.fill": "rail-play",
        "plus": "rail-add",
        "plus.square": "rail-import",
        "plus.square.on.square": "rail-duplicate",
        "record.circle": "rail-capture",
        "rectangle.dashed": "rail-empty-frame",
        "rectangle.stack": "rail-library",
        "scissors": "rail-trim",
        "scissors.badge.ellipsis": "rail-trim",
        "slider.horizontal.below.square.filled.and.square": "rail-studio",
        "slider.vertical.3": "rail-tune",
        "speaker.wave.2": "rail-speaker",
        "speedometer": "rail-speed",
        "square.and.arrow.up": "rail-export",
        "text.quote": "rail-quote",
        "textformat": "rail-text",
        "timer": "rail-timer",
        "trash": "rail-delete",
        "tray.and.arrow.down": "rail-import",
        "wand.and.stars": "rail-magic",
        "waveform": "rail-audio",
        "waveform.badge.magnifyingglass": "rail-audio-search",
        "waveform.badge.plus": "rail-audio-add",
        "xmark": "rail-close",
        "xmark.circle.fill": "rail-clear",
    ]

    static func assetName(for systemName: String) -> String {
        guard let name = aliases[systemName] else {
            assertionFailure("Missing Pebble Rail icon mapping for \(systemName)")
            return "rail-status-warning"
        }
        return name
    }
}

struct RailGlyph: View {
    let systemName: String
    var size: CGFloat = 20

    var body: some View {
        Image(RailIconCatalog.assetName(for: systemName))
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct RailLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label { Text(title) } icon: { RailGlyph(systemName: systemImage) }
    }
}

