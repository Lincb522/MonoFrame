import SwiftUI
import UIKit

enum SignalColor {
    // UIColor-backed semantic colors update in place when the system appearance
    // changes. This also covers surfaces that are not rebuilt by SwiftUI.
    static let coral = adaptive(
        light: UIColor(red: 1.00, green: 0.27, blue: 0.12, alpha: 1),
        dark: UIColor(red: 1.00, green: 0.40, blue: 0.24, alpha: 1)
    )
    static let acid = adaptive(
        light: UIColor(red: 0.63, green: 0.98, blue: 0.08, alpha: 1),
        dark: UIColor(red: 0.70, green: 1.00, blue: 0.18, alpha: 1)
    )
    static let cobalt = adaptive(
        light: UIColor(red: 0.25, green: 0.34, blue: 1.00, alpha: 1),
        dark: UIColor(red: 0.42, green: 0.51, blue: 1.00, alpha: 1)
    )
    static let violet = adaptive(
        light: UIColor(red: 0.52, green: 0.25, blue: 0.98, alpha: 1),
        dark: UIColor(red: 0.68, green: 0.48, blue: 1.00, alpha: 1)
    )
    static let mango = adaptive(
        light: UIColor(red: 1.00, green: 0.72, blue: 0.05, alpha: 1),
        dark: UIColor(red: 1.00, green: 0.78, blue: 0.22, alpha: 1)
    )
    static let success = adaptive(
        light: UIColor(red: 0.06, green: 0.49, blue: 0.28, alpha: 1),
        dark: UIColor(red: 0.30, green: 0.84, blue: 0.54, alpha: 1)
    )
    static let stage = adaptive(
        light: UIColor(red: 0.035, green: 0.035, blue: 0.042, alpha: 1),
        dark: UIColor(red: 0.018, green: 0.018, blue: 0.024, alpha: 1)
    )
    static let stageRaised = adaptive(
        light: UIColor(red: 0.075, green: 0.075, blue: 0.085, alpha: 1),
        dark: UIColor(red: 0.105, green: 0.105, blue: 0.122, alpha: 1)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.035, green: 0.038, blue: 0.032) : Color(red: 0.965, green: 0.972, blue: 0.956)
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.085, green: 0.090, blue: 0.078) : .white
    }

    static func raised(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.14, green: 0.145, blue: 0.125) : Color(red: 0.91, green: 0.925, blue: 0.895)
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.97, green: 0.98, blue: 0.95) : Color(red: 0.035, green: 0.04, blue: 0.03)
    }

    /// Foreground placed on an `ink` fill.
    static func inverseInk(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.035, green: 0.04, blue: 0.03) : .white
    }

    /// Accessible foreground placed on the adaptive coral accent.
    static func onAccent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.075, green: 0.045, blue: 0.035) : .white
    }

    static func secondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.54)
    }

    static func rule(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12)
    }
}

struct SignalCutCornerShape: Shape {
    var cut: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let c = min(cut, min(rect.width, rect.height) / 3)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        path.closeSubpath()
        return path
    }
}

enum SignalSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

struct SignalPageBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        SignalColor.canvas(scheme).ignoresSafeArea()
    }
}

struct SignalPageHeader: View {
    let title: String
    var detail: String? = nil
    var action: AnyView? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SignalSpace.sm) {
            VStack(alignment: .leading, spacing: SignalSpace.xxs) {
                Text(title)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .tracking(-0.9)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                if let detail {
                    Text(detail)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(SignalColor.secondary(scheme))
                }
            }
            Spacer(minLength: SignalSpace.sm)
            action
        }
        .foregroundStyle(SignalColor.ink(scheme))
        .accessibilityElement(children: .combine)
    }
}

struct SignalSectionHeader: View {
    let title: String
    var detail: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))
            Spacer()
            if let detail {
                Text(detail)
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(SignalColor.secondary(scheme))
            }
        }
        .foregroundStyle(SignalColor.ink(scheme))
    }
}

struct SignalPanel<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .background(SignalColor.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct SignalControlSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(SignalColor.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SignalColor.rule(scheme), lineWidth: 1)
            }
    }
}

struct SignalRule: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Rectangle().fill(SignalColor.rule(scheme)).frame(height: 1) }
}

struct SignalStatus: View {
    enum Kind { case ready, live, done, warning }
    let text: String
    let kind: Kind

    private var color: Color {
        switch kind {
        case .ready: .secondary
        case .live, .warning: SignalColor.coral
        case .done: SignalColor.success
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Group {
                if kind == .live {
                    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
                } else {
                    Circle().fill(color).frame(width: 8, height: 8)
                }
            }
            Text(text)
                .font(.system(.caption, design: .rounded, weight: .bold))
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }
}

struct SignalPrimaryButtonStyle: ButtonStyle {
    var tint: Color = SignalColor.acid
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.black)
            .background(configuration.isPressed ? tint.opacity(0.80) : tint)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 1), value: configuration.isPressed)
    }
}

struct SignalPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.64 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .animation(.spring(response: 0.20, dampingFraction: 1), value: configuration.isPressed)
    }
}

struct SignalIconButton: View {
    let symbol: String
    var label: String
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(SignalColor.ink(scheme))
                .frame(width: 44, height: 44)
                .background(SignalColor.surface(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(SignalColor.rule(scheme), lineWidth: 1)
                }
        }
        .buttonStyle(SignalPressStyle())
        .accessibilityLabel(label)
    }
}

struct SignalSegmentedControl<Value: Hashable>: View {
    let values: [(Value, String)]
    @Binding var selection: Value
    @Namespace private var selectionSpace
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: SignalSpace.xxs) {
            ForEach(values, id: \.0) { value, label in
                Button {
                    if reduceMotion { selection = value }
                    else { withAnimation(.spring(response: 0.32, dampingFraction: 1)) { selection = value } }
                } label: {
                    Text(label)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(selection == value ? SignalColor.acid : SignalColor.secondary(scheme))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if selection == value {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(SignalColor.stage)
                                    .matchedGeometryEffect(id: "signal-selection", in: selectionSpace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(SignalSpace.xxs)
        .background(SignalColor.raised(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Reference-led asymmetric stage: the top-right corner opens up for a
/// floating live/status bubble instead of keeping every card rectangular.
struct YouthNotchedPanelShape: Shape {
    var cornerRadius: CGFloat = 32
    var notchWidth: CGFloat = 86
    var notchDepth: CGFloat = 62

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) * 0.22)
        let notchStart = max(r, rect.maxX - notchWidth)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: notchStart, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + notchDepth),
            control1: CGPoint(x: notchStart + 24, y: rect.minY),
            control2: CGPoint(x: rect.maxX - 34, y: rect.minY + notchDepth)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct YouthStatusBubble: View {
    let value: String
    var symbol: String = "sparkles"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { context in
            let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            VStack(spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .contentTransition(.numericText())
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .black))
                    .rotationEffect(.degrees(reduceMotion ? 0 : sin(phase * 1.8) * 8))
            }
            .foregroundStyle(.black)
            .frame(width: 58, height: 58)
            .background(SignalColor.acid)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 25,
                topTrailingRadius: 25,
                style: .continuous
            ))
            .scaleEffect(reduceMotion ? 1 : 1 + CGFloat(sin(phase * 2.2)) * 0.025)
        }
        .accessibilityElement(children: .combine)
    }
}

struct YouthAccentTag: View {
    let text: String
    var tint: Color = SignalColor.acid

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(tint)
            .clipShape(Capsule())
    }
}

/// Source-reference implementation: a trim segment whose progress can be
/// interpolated by SwiftUI instead of being redrawn as a discrete state jump.
struct YouthRingSegment: View, Animatable {
    let from: Double
    let to: Double
    var animationProgress: Double
    var tint: Color = SignalColor.acid
    var lineWidth: CGFloat = 4

    var animatableData: Double {
        get { animationProgress }
        set { animationProgress = newValue }
    }

    var body: some View {
        let progress = min(max(animationProgress, 0), 1)
        let animatedTo = min(to, progress)
        let animatedFrom = min(from, animatedTo)

        Circle()
            .trim(from: animatedFrom, to: animatedTo)
            .stroke(
                tint,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
    }
}

/// Source-reference implementation: the displayed integer participates in
/// SwiftUI's interpolation so counts accelerate/decelerate with their card.
struct YouthCountingText: View, Animatable {
    var value: Double
    var suffix: String = ""

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(max(0, Int(value)).formatted())\(suffix)")
            .contentTransition(.numericText())
            .monospacedDigit()
    }
}

/// The DashboardCard code shown in the reference combines opacity, scale and
/// a hinged x-axis rotation. Keep that physical entrance reusable and provide
/// a quiet cross-fade when Reduce Motion is enabled.
private struct YouthStageEntranceModifier: ViewModifier {
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.4, anchor: .top)
            .rotation3DEffect(
                .degrees(isVisible || reduceMotion ? 0 : 90),
                axis: (x: -1, y: 0, z: 0),
                anchor: .top,
                perspective: 0.4
            )
            .onAppear {
                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.18)) { isVisible = true }
                } else {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.15)) {
                        isVisible = true
                    }
                }
            }
    }
}

/// Matches the reference's delayed middle-content reveal (60pt rise), while
/// allowing sections to opt into a short stagger instead of animating all UI.
private struct YouthDelayedRevealModifier: ViewModifier {
    let delay: Double
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 60)
            .onAppear {
                if reduceMotion {
                    isVisible = true
                } else {
                    withAnimation(.spring(response: 0.56, dampingFraction: 0.78).delay(delay)) {
                        isVisible = true
                    }
                }
            }
    }
}

struct SignalTimecode: View {
    let seconds: TimeInterval
    var size: CGFloat = 42

    var body: some View {
        Text(Self.format(seconds))
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .tracking(-1)
            .monospacedDigit()
            .contentTransition(.numericText())
            .accessibilityLabel(Self.accessibility(seconds))
    }

    static func format(_ duration: TimeInterval) -> String {
        let value = max(0, Int(duration))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }

    private static func accessibility(_ duration: TimeInterval) -> String {
        let value = max(0, Int(duration))
        return "\(value / 3600) 小时 \(value / 60 % 60) 分 \(value % 60) 秒"
    }
}

struct SignalWaveform: View {
    var active: Bool
    var phase: TimeInterval
    var bars: Int = 28
    var tint: Color = SignalColor.coral
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<bars, id: \.self) { index in
                let idle = CGFloat(4 + (index * 11) % 17)
                let live = CGFloat(5 + abs(sin(phase * 3 + Double(index) * 0.73)) * 38)
                Capsule()
                    .fill(index.isMultiple(of: 6) ? tint : Color.white.opacity(0.48))
                    .frame(maxWidth: .infinity)
                    .frame(height: active && !reduceMotion ? live : idle)
            }
        }
        .frame(height: 48)
        .animation(.easeOut(duration: 0.16), value: phase)
        .accessibilityHidden(true)
    }
}

struct SignalIris: View {
    var active: Bool
    var phase: TimeInterval
    var size: CGFloat = 112
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let rotation = reduceMotion ? 0 : phase * (active ? 28 : 7)
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .trim(from: CGFloat(index) * 0.26, to: min(0.98, CGFloat(index) * 0.26 + 0.17))
                    .stroke(
                        index == 1 ? SignalColor.coral : Color.white.opacity(index == 0 ? 0.72 : 0.34),
                        style: StrokeStyle(lineWidth: index == 1 ? 4 : 2, lineCap: .square)
                    )
                    .rotationEffect(.degrees(rotation * (index.isMultiple(of: 2) ? 1 : -1) + Double(index * 31)))
                    .padding(CGFloat(index * 8))
            }

            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                .padding(25)

            Group {
                if active {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(SignalColor.coral)
                        .frame(width: size * 0.30, height: size * 0.30)
                } else {
                    Circle()
                        .fill(SignalColor.coral)
                        .frame(width: size * 0.46, height: size * 0.46)
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: active)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SignalCornerReticle: View {
    var color: Color = .white.opacity(0.44)

    var body: some View {
        GeometryReader { proxy in
            let length = min(proxy.size.width, proxy.size.height) * 0.08
            Path { path in
                path.move(to: CGPoint(x: 0, y: length)); path.addLine(to: .zero); path.addLine(to: CGPoint(x: length, y: 0))
                path.move(to: CGPoint(x: proxy.size.width - length, y: 0)); path.addLine(to: CGPoint(x: proxy.size.width, y: 0)); path.addLine(to: CGPoint(x: proxy.size.width, y: length))
                path.move(to: CGPoint(x: proxy.size.width, y: proxy.size.height - length)); path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height)); path.addLine(to: CGPoint(x: proxy.size.width - length, y: proxy.size.height))
                path.move(to: CGPoint(x: length, y: proxy.size.height)); path.addLine(to: CGPoint(x: 0, y: proxy.size.height)); path.addLine(to: CGPoint(x: 0, y: proxy.size.height - length))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .square))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func signalPagePadding() -> some View {
        padding(.horizontal, SignalSpace.md)
            .padding(.top, SignalSpace.md)
    }

    func signalControlSurface(cornerRadius: CGFloat = 14) -> some View {
        modifier(SignalControlSurfaceModifier(cornerRadius: cornerRadius))
    }

    func youthStageEntrance() -> some View {
        modifier(YouthStageEntranceModifier())
    }

    func youthDelayedReveal(delay: Double = 0.4) -> some View {
        modifier(YouthDelayedRevealModifier(delay: delay))
    }
}
