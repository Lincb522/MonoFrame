import SwiftUI
import UIKit

/// Appearance storage for the Canvas Glass interface.
///
/// Canvas starts in its authored light appearance. Existing preferences from
/// retired interfaces are intentionally not imported into the new design.
enum CanvasAppearancePreference {
    static let storageKey = "canvasAppearanceV1"
    static let defaultValue = "light"
    static let options: [(value: String, title: String)] = [
        ("light", "浅色"),
        ("dark", "深色"),
        ("system", "跟随系统")
    ]
}

enum CanvasColor {
    /// Filled controls only. Text and small glyphs use `accent(_:)`.
    static let lagoon = Color(red: 5 / 255, green: 120 / 255, blue: 138 / 255)
    static let coral = Color(red: 1.00, green: 0.27, blue: 0.23)

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.045, green: 0.050, blue: 0.056)
            : Color(red: 244 / 255, green: 244 / 255, blue: 246 / 255)
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.090, green: 0.098, blue: 0.108)
            : Color(red: 0.995, green: 0.997, blue: 1.000)
    }

    static func elevated(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.135, green: 0.145, blue: 0.160)
            : Color(red: 0.930, green: 0.940, blue: 0.950)
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.955, green: 0.965, blue: 0.975)
            : Color(red: 17 / 255, green: 18 / 255, blue: 20 / 255)
    }

    static func secondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.700, green: 0.725, blue: 0.755)
            : Color(red: 0.385, green: 0.410, blue: 0.450)
    }

    static func tertiary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.505, green: 0.530, blue: 0.565)
            : Color(red: 0.395, green: 0.420, blue: 0.460)
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.055)
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.35, green: 0.88, blue: 0.91)
            : lagoon
    }

    static func danger(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 1.00, green: 0.46, blue: 0.42)
            : Color(red: 0.72, green: 0.10, blue: 0.08)
    }

    static func glassFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.60)
    }

    static func glassEdge(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.13) : Color.white.opacity(0.80)
    }
}

struct CanvasBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        CanvasColor.background(scheme).ignoresSafeArea()
    }
}

struct CanvasPage<Content: View>: View {
    var horizontalPadding: CGFloat = 20
    var topPadding: CGFloat = 8
    private let content: Content

    init(
        horizontalPadding: CGFloat = 20,
        topPadding: CGFloat = 8,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: 720, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(CanvasBackdrop())
    }
}

struct CanvasHairline: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        CanvasColor.hairline(scheme)
            .frame(height: 1 / max(displayScale, 1))
            .accessibilityHidden(true)
    }
}

struct CanvasPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.70 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

struct CanvasPlainRow<Trailing: View>: View {
    let title: String
    var accessibilityValue: String?
    private let trailing: Trailing

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        _ title: String,
        accessibilityValue: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.accessibilityValue = accessibilityValue
        self.trailing = trailing()
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                    trailing.frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.vertical, 13)
            } else {
                HStack(spacing: 14) {
                    Text(title)
                    Spacer(minLength: 12)
                    trailing
                }
                .frame(minHeight: 50)
            }
        }
        .font(.body)
        .foregroundStyle(CanvasColor.ink(scheme))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue ?? "")
    }
}

struct CanvasSectionLabel: View {
    let title: String
    @Environment(\.colorScheme) private var scheme

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(CanvasColor.secondary(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CanvasInlineNotice: View {
    enum Tone { case info, warning, error }

    let message: String
    var tone: Tone = .info
    @Environment(\.colorScheme) private var scheme

    private var color: Color {
        switch tone {
        case .info: CanvasColor.accent(scheme)
        case .warning: scheme == .dark ? .orange : Color(red: 0.55, green: 0.29, blue: 0)
        case .error: CanvasColor.danger(scheme)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 7, height: 7).padding(.top, 6)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(CanvasColor.ink(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(color.opacity(scheme == .dark ? 0.13 : 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct CanvasWaveform: View {
    var active: Bool
    var phase: TimeInterval
    var sampleCount = 66

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwiftUI.Canvas { context, size in
            let midY = size.height / 2
            let gap = size.width / CGFloat(max(sampleCount - 1, 1))

            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: midY))
            baseline.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(
                baseline,
                with: .color(CanvasColor.secondary(scheme).opacity(0.24)),
                style: StrokeStyle(lineWidth: 1, dash: [1.4, 2.8])
            )

            for index in 0..<sampleCount {
                let position = CGFloat(index) * gap
                let seed = CGFloat((index * 17 + 5) % 23) / 22
                let motion = CGFloat(abs(sin((reduceMotion ? 0 : phase) * 2.2 + Double(index) * 0.47)))
                let envelope = 0.30 + 0.70 * sin(.pi * CGFloat(index) / CGFloat(max(sampleCount - 1, 1)))
                let amplitude = max(2, (active ? motion : seed) * envelope * (size.height * 0.42))
                var tick = Path()
                tick.move(to: CGPoint(x: position, y: midY - amplitude))
                tick.addLine(to: CGPoint(x: position, y: midY + amplitude))
                context.stroke(
                    tick,
                    with: .color(CanvasColor.secondary(scheme).opacity(active ? 0.58 : 0.38)),
                    style: StrokeStyle(lineWidth: index.isMultiple(of: 7) ? 1.4 : 0.9, lineCap: .round)
                )
            }

            var playhead = Path()
            playhead.move(to: CGPoint(x: size.width / 2, y: 0))
            playhead.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            context.stroke(playhead, with: .color(CanvasColor.coral), lineWidth: 1.2)
        }
        .accessibilityHidden(true)
    }
}

enum CanvasGlassRole: Sendable, Equatable {
    case tab
    case control
    case search
    case segmented

    var material: Material {
        switch self {
        case .tab: .regularMaterial
        case .control: .ultraThinMaterial
        case .search: .thinMaterial
        case .segmented: .thinMaterial
        }
    }

    func fallback(_ scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.tab, .light):
            // Deliberately neutral rather than white: the fallback must still
            // read as a floating rail when transparency is reduced.
            Color(red: 240 / 255, green: 239 / 255, blue: 241 / 255)
        case (.tab, .dark):
            Color(red: 0.105, green: 0.112, blue: 0.124)
        case (.control, _):
            CanvasColor.surface(scheme)
        case (.search, .light):
            Color(red: 0.925, green: 0.930, blue: 0.940)
        case (.search, .dark):
            Color(red: 0.115, green: 0.123, blue: 0.136)
        case (.segmented, .light):
            Color(red: 0.915, green: 0.922, blue: 0.932)
        case (.segmented, .dark):
            Color(red: 0.125, green: 0.134, blue: 0.148)
        @unknown default:
            CanvasColor.surface(scheme)
        }
    }

    func tint(_ scheme: ColorScheme) -> Color {
        switch self {
        case .tab:
            scheme == .dark ? Color.white.opacity(0.035) : Color.white.opacity(0.18)
        case .control:
            CanvasColor.accent(scheme).opacity(scheme == .dark ? 0.035 : 0.018)
        case .search:
            scheme == .dark ? Color.white.opacity(0.025) : Color.white.opacity(0.10)
        case .segmented:
            CanvasColor.accent(scheme).opacity(scheme == .dark ? 0.025 : 0.016)
        }
    }

    func edge(_ scheme: ColorScheme) -> Color {
        switch self {
        case .tab:
            scheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.58)
        case .control:
            CanvasColor.glassEdge(scheme)
        case .search, .segmented:
            scheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.46)
        }
    }
}

struct CanvasGlassSurface<Content: View>: View {
    var role: CanvasGlassRole = .control
    var cornerRadius: CGFloat = 24
    private let content: Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        role: CanvasGlassRole = .control,
        cornerRadius: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        self.role = role
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    shape.fill(role.fallback(scheme))
                } else {
                    ZStack {
                        shape.fill(role.material)
                        shape.fill(role.tint(scheme))
                    }
                }
            }
            .overlay(alignment: .top) {
                shape
                    .stroke(role.edge(scheme), lineWidth: role == .tab ? 0.65 : 0.7)
                    .mask(alignment: .top) {
                        LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
                    }
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func canvasNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
    }
}
