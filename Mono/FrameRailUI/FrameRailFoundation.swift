import SwiftUI

enum RailColor {
    static let coral = Color(red: 1.00, green: 0.24, blue: 0.25)
    static let blue = Color(red: 0.20, green: 0.36, blue: 1.00)
    static let mint = Color(red: 0.12, green: 0.76, blue: 0.58)

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.035, green: 0.038, blue: 0.045) : Color(red: 0.965, green: 0.968, blue: 0.975)
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.075, green: 0.080, blue: 0.095) : .white
    }

    static func raised(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.115, green: 0.12, blue: 0.145) : Color(red: 0.91, green: 0.92, blue: 0.945)
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.96, green: 0.96, blue: 0.98) : Color(red: 0.055, green: 0.06, blue: 0.075)
    }

    static func selection(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.20, green: 0.21, blue: 0.26) : ink(scheme)
    }

    static func onSelection(_ scheme: ColorScheme) -> Color {
        .white
    }

    static func secondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.66, green: 0.67, blue: 0.72) : Color(red: 0.33, green: 0.35, blue: 0.41)
    }

    static func rule(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.10)
    }
}

enum RailSpace {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 34
}

struct RailBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RailColor.background(scheme).ignoresSafeArea()
    }
}

struct RailPageHeader<Trailing: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let trailing: Trailing
    @Environment(\.colorScheme) private var scheme

    init(title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .tracking(-1.0)
                    .foregroundStyle(RailColor.ink(scheme))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(RailColor.secondary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .accessibilityElement(children: .combine)
    }
}

extension RailPageHeader where Trailing == EmptyView {
    init(title: String, detail: String? = nil) {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}

struct RailSectionTitle: View {
    let title: String
    var detail: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(RailColor.ink(scheme))
            Spacer()
            if let detail {
                Text(detail)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(RailColor.secondary(scheme))
            }
        }
    }
}

struct RailSurface<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .background(RailColor.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct RailHairline: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Rectangle().fill(RailColor.rule(scheme)).frame(height: 1) }
}

struct RailStatus: View {
    let text: String
    var tint: Color = RailColor.mint

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(text)
        }
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background(tint.opacity(0.14))
        .foregroundStyle(tint)
        .clipShape(Capsule())
    }
}

struct RailPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.80 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

struct RailPrimaryButtonStyle: ButtonStyle {
    var tint: Color = RailColor.coral
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(tint.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

struct RailIconButton: View {
    let symbol: String
    var title: String? = nil
    var tint: Color = RailColor.coral
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                RailGlyph(systemName: symbol).font(.system(size: 15, weight: .bold))
                if let title { Text(title).font(.system(.caption, design: .rounded, weight: .bold)) }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, title == nil ? 0 : 12)
            .frame(minWidth: 44, minHeight: 44)
            .background(RailColor.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(RailPressStyle())
        .accessibilityLabel(title ?? symbol)
    }
}

struct RailWaveform: View {
    let samples: [Float]
    var tint: Color = RailColor.coral
    var playhead: Double? = nil

    var body: some View {
        GeometryReader { proxy in
            let values = samples.isEmpty ? Array(repeating: Float(0.18), count: 48) : samples
            ZStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, sample in
                        Capsule()
                            .fill(index.isMultiple(of: 7) ? tint : tint.opacity(0.42))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(3, CGFloat(min(1, abs(sample))) * proxy.size.height))
                    }
                }
                if let playhead {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2)
                        .offset(x: max(0, min(proxy.size.width - 2, proxy.size.width * playhead)))
                        .shadow(color: tint, radius: 4)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct RailTimelineTicks: View {
    var count = 18
    var tint: Color = RailColor.coral
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Rectangle()
                    .fill(index.isMultiple(of: 5) ? tint : RailColor.rule(scheme))
                    .frame(maxWidth: .infinity)
                    .frame(height: index.isMultiple(of: 5) ? 9 : 4)
            }
        }
        .frame(height: 10, alignment: .top)
        .accessibilityHidden(true)
    }
}

struct RailEmptyState: View {
    let title: String
    let detail: String
    let symbol: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 12) {
            RailGlyph(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(RailColor.coral)
            Text(title).font(.system(.headline, design: .rounded, weight: .bold))
            Text(detail)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(RailColor.secondary(scheme))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(RailColor.ink(scheme))
        .frame(maxWidth: .infinity, minHeight: 156)
        .padding(20)
    }
}

struct RailSegmented<Value: Hashable>: View {
    let values: [(Value, String)]
    @Binding var selection: Value
    @Namespace private var namespace
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(values, id: \.0) { value, label in
                Button {
                    if reduceMotion { selection = value }
                    else { withAnimation(.smooth(duration: 0.28)) { selection = value } }
                } label: {
                    Text(label)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(selection == value ? RailColor.onSelection(scheme) : RailColor.secondary(scheme))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if selection == value {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(RailColor.selection(scheme))
                                    .matchedGeometryEffect(id: "rail-segment", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RailColor.raised(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct RailToast: View {
    let message: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(message)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(RailColor.ink(scheme))
            .padding(.horizontal, 15)
            .frame(minHeight: 42)
            .background(RailColor.surface(scheme).opacity(0.92))
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .padding(.top, 8)
    }
}

extension View {
    func railPagePadding() -> some View {
        padding(.horizontal, 20).padding(.top, 18)
    }

    func railEntrance(delay: Double = 0) -> some View {
        modifier(RailEntranceModifier(delay: delay))
    }
}

private struct RailEntranceModifier: ViewModifier {
    let delay: Double
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 12)
            .onAppear {
                if reduceMotion { visible = true }
                else {
                    withAnimation(.easeOut(duration: 0.36).delay(delay)) { visible = true }
                }
            }
    }
}
