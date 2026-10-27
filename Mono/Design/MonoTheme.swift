import SwiftUI

enum MonoTheme {
    // Compatibility bridge for feature-rich detail pages. Keeping these names
    // lets the editors retain their behavior while sharing Signal's palette.
    static let primary = SignalColor.acid
    static let mint = SignalColor.success
    static let lavender = SignalColor.violet
    static let peach = SignalColor.coral
    static let butter = SignalColor.mango
    static let recording = SignalColor.coral
    static let coral = SignalColor.coral
    static let electric = SignalColor.cobalt
    static let cyan = SignalColor.acid
    static let success = SignalColor.success
    static let stage = SignalColor.stage
    static let canvas = Color(red: 0.965, green: 0.965, blue: 0.97)
    static let paper = Color.white

    static func background(_ scheme: ColorScheme) -> Color {
        SignalColor.canvas(scheme)
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        SignalColor.ink(scheme)
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        SignalColor.surface(scheme)
    }

    static func surfaceMuted(_ scheme: ColorScheme) -> Color {
        SignalColor.raised(scheme)
    }

    static func muted(_ scheme: ColorScheme) -> Color {
        SignalColor.secondary(scheme)
    }

    static func divider(_ scheme: ColorScheme) -> Color {
        SignalColor.rule(scheme)
    }
}

struct MonoImmersiveBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        SignalColor.canvas(scheme)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct MonoPanel: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(SignalColor.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct MonoLiquidGlass: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(tint?.opacity(0.10) ?? SignalColor.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SignalColor.rule(scheme), lineWidth: 1)
            }
    }
}

extension View {
    func monoPanel() -> some View { modifier(MonoPanel()) }
    func monoLiquidGlass(cornerRadius: CGFloat = 28, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(MonoLiquidGlass(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
}
