import AVFoundation
import SwiftUI

@MainActor
final class PearlPlaybackController: ObservableObject {
    let player: AVPlayer
    @Published private(set) var time: Double = 0
    @Published private(set) var isPlaying = false

    private var clockTask: Task<Void, Never>?
    private var playbackRange: ClosedRange<Double>?

    init(url: URL) {
        player = AVPlayer(url: url)
    }

    func replace(item: AVPlayerItem, at seconds: Double) {
        pause()
        player.replaceCurrentItem(with: item)
        seek(to: seconds)
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

struct PearlEditorSection<Content: View>: View {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title2.weight(.bold))
                Spacer(minLength: 8)
                Text(detail).font(.caption).foregroundStyle(PearlColor.secondary(scheme))
            }.padding(.bottom, 4)
            content
        }
        .accessibilityElement(children: .contain)
    }
}

struct PearlEditorSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var valueText: String?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.studioEditingGesture) private var editingGesture

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
                    .foregroundStyle(PearlColor.tertiary(scheme))
            }
            Slider(value: $value, in: range, onEditingChanged: { editingGesture?($0) })
                .tint(PearlColor.accent(scheme))
                .frame(minHeight: 44)
        }
        .foregroundStyle(PearlColor.ink(scheme))
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }
}

struct PearlEditorAction: View {
    let title: String
    let glyph: PearlGlyphName
    var destructive = false
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                PearlGlyph(glyph, size: 18)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(destructive ? PearlColor.danger(scheme) : PearlColor.ink(scheme))
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(PearlPressStyle())
        .accessibilityLabel(title)
    }
}

struct PearlEditorActionGrid<Content: View>: View {
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

struct PearlChoiceChip: View {
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
                .foregroundStyle(selected ? PearlColor.onAccent(scheme) : PearlColor.ink(scheme))
                .padding(.horizontal, 13)
                .frame(minHeight: 44)
                .background(
                    selected ? PearlColor.action(scheme) : PearlColor.elevated(scheme),
                    in: Capsule()
                )
        }
        .buttonStyle(PearlPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PearlExportLabel: View {
    let title: String
    let active: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        PearlPrimaryLabel(title: title, glyph: .export, busy: active).padding(.top, 12)
    }
}

struct PearlShareReadyLabel: View {
    let fileName: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 11) {
            PearlGlyph(.check, size: 20)
                .foregroundStyle(PearlColor.accent(scheme))
            VStack(alignment: .leading, spacing: 2) {
                Text("导出成功")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PearlColor.ink(scheme))
                Text(fileName)
                    .font(.caption)
                    .foregroundStyle(PearlColor.tertiary(scheme))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            PearlGlyph(.share, size: 19)
                .foregroundStyle(PearlColor.accent(scheme))
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .contentShape(Rectangle())
        .padding(.top, 4)
    }
}

struct PearlEditorNotice: Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
}
