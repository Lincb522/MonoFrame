import SwiftUI
import UIKit

enum AppAppearancePreference {
    static let storageKey = "wildAppearanceV1"
    static let defaultValue = "light"
    static let options: [(value: String, title: String)] = [
        ("system", "自动"),
        ("light", "浅色"),
        ("dark", "深色")
    ]
}

enum FeatherColor {
    static let lagoon = Color(red: 13 / 255, green: 124 / 255, blue: 134 / 255)
    static let coral = Color(red: 1, green: 69 / 255, blue: 58 / 255)
    static let success = Color(red: 0.08, green: 0.48, blue: 0.31)
    static let warning = Color(red: 0.72, green: 0.39, blue: 0.04)

    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.055, green: 0.060, blue: 0.067)
            : Color(red: 0.973, green: 0.976, blue: 0.980)
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.105, green: 0.112, blue: 0.124)
            : .white
    }

    static func raised(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.155, green: 0.165, blue: 0.180)
            : Color(red: 230 / 255, green: 232 / 255, blue: 236 / 255)
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.955, green: 0.963, blue: 0.972)
            : Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    }

    static func secondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.73, green: 0.75, blue: 0.79)
            : Color(red: 0.31, green: 0.34, blue: 0.38)
    }

    static func rule(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.22, green: 0.24, blue: 0.27)
            : Color(red: 0.82, green: 0.84, blue: 0.87)
    }

    static func lagoonWash(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.06, green: 0.23, blue: 0.25)
            : Color(red: 0.86, green: 0.94, blue: 0.94)
    }

    /// Accent ink for text and small glyphs. Keep `lagoon` for filled controls.
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.38, green: 0.86, blue: 0.89)
            : Color(red: 0.035, green: 0.43, blue: 0.47)
    }

    /// Destructive/error ink with AA contrast on both semantic surfaces.
    static func danger(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 1.0, green: 0.43, blue: 0.39)
            : Color(red: 0.72, green: 0.12, blue: 0.10)
    }

    /// Success ink for compact status copy and small glyphs.
    static func successInk(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.38, green: 0.86, blue: 0.64)
            : Color(red: 0.03, green: 0.39, blue: 0.23)
    }

    /// Warning ink that remains legible on both content surfaces.
    static func warningInk(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 1.0, green: 0.70, blue: 0.34)
            : Color(red: 0.52, green: 0.27, blue: 0.00)
    }

    static func coralWash(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.29, green: 0.10, blue: 0.09)
            : Color(red: 1.0, green: 0.90, blue: 0.89)
    }
}

struct FeatherBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        FeatherColor.canvas(scheme).ignoresSafeArea()
    }
}

struct FeatherPage<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 118)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(FeatherBackdrop())
    }
}

struct FeatherSectionHeader: View {
    let title: String
    var detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))
            Spacer(minLength: 12)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct FeatherRule: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        FeatherColor.rule(scheme).frame(height: 1 / UIScreen.main.scale)
    }
}

struct FeatherSurface<Content: View>: View {
    var cornerRadius: CGFloat = 16
    private let content: Content
    @Environment(\.colorScheme) private var scheme

    init(cornerRadius: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background(FeatherColor.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct FeatherGlassControl<Content: View>: View {
    var cornerRadius: CGFloat = 18
    var tint: Color?
    private let content: Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(cornerRadius: CGFloat = 18, tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.content = content()
    }

    @ViewBuilder var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background(tint ?? FeatherColor.surface(scheme), in: shape)
                .overlay(shape.stroke(FeatherColor.rule(scheme), lineWidth: 1))
        } else if let tint {
            content.glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        }
    }
}

struct FeatherIcon: View {
    let name: String
    var size: CGFloat = 20

    var body: some View {
        MonoIcon(name, size: size, weight: 1.85)
    }
}

struct FeatherIconLabel: View {
    let title: String
    let icon: String
    var iconSize: CGFloat = 18

    var body: some View {
        HStack(spacing: 9) {
            FeatherIcon(name: icon, size: iconSize)
            Text(title)
        }
    }
}

struct FeatherPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

struct FeatherPrimaryButton: View {
    let title: String
    let icon: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FeatherIconLabel(title: title, icon: icon, iconSize: 17)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(FeatherPressStyle())
        .background(FeatherColor.lagoon, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(isEnabled ? 1 : 0.42)
        .disabled(!isEnabled)
    }
}

struct FeatherInlineNotice: View {
    enum Tone { case info, warning, error, success }

    let message: String
    var tone: Tone = .info
    @Environment(\.colorScheme) private var scheme

    private var color: Color {
        switch tone {
        case .info: FeatherColor.accent(scheme)
        case .warning: FeatherColor.warningInk(scheme)
        case .error: FeatherColor.danger(scheme)
        case .success: FeatherColor.successInk(scheme)
        }
    }

    private var symbol: String {
        switch tone {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "exclamationmark.circle"
        case .success: "checkmark.circle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(color)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(FeatherColor.ink(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(color.opacity(scheme == .dark ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct FeatherEmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 14) {
            FeatherIcon(name: icon, size: 32)
                .foregroundStyle(FeatherColor.secondary(scheme))
            VStack(spacing: 5) {
                Text(title).font(.headline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(FeatherColor.secondary(scheme))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FeatherColor.accent(scheme))
                    .buttonStyle(FeatherPressStyle())
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 210)
        .padding(24)
    }
}

struct FeatherWaveform: View {
    var active: Bool
    var phase: TimeInterval
    var tint: Color = FeatherColor.lagoon
    var count = 42
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                let base = Double((index * 11) % 9) / 9
                let live = abs(sin((reduceMotion ? 0 : phase) * 2.25 + Double(index) * 0.51))
                Capsule()
                    .fill(index == count / 2 ? FeatherColor.coral : tint.opacity(active ? 0.78 : 0.34))
                    .frame(maxWidth: .infinity)
                    .frame(height: 3 + CGFloat(active ? live : base) * 30)
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    func featherNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
    }
}
