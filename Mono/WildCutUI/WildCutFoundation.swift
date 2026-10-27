import SwiftUI

enum WildAppearance {
    static let storageKey = "wildAppearanceV1"
    static let defaultValue = "light"
}

enum WildColor {
    static let acid = Color(red: 0.79, green: 0.82, blue: 1.00)
    static let blue = Color(red: 0.27, green: 0.29, blue: 1.00)
    static let orange = Color(red: 1.00, green: 0.30, blue: 0.25)
    static let violet = Color(red: 0.27, green: 0.29, blue: 1.00)
    static let mint = Color(red: 0.14, green: 0.86, blue: 0.61)

    // Foregrounds are semantic to the accent, not to light/dark appearance.
    static let onAcid = Color.black
    static let onBlue = Color.white
    static let onOrange = Color.black
    static let onViolet = Color.white
    static let onMint = Color.black

    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.035, green: 0.038, blue: 0.045) : Color(red: 0.955, green: 0.955, blue: 0.945)
    }
    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.97, green: 0.97, blue: 0.98) : Color(red: 0.035, green: 0.04, blue: 0.05)
    }
    static func paper(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.085, green: 0.09, blue: 0.105) : Color.white
    }
    static func raised(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.15, green: 0.155, blue: 0.17) : Color(red: 0.86, green: 0.86, blue: 0.81)
    }
    static func secondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.56)
    }
    static func rule(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.13)
    }
    static func stage(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.045, green: 0.048, blue: 0.057) : Color.white
    }
    static func stageInk(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white : Color(red: 0.035, green: 0.04, blue: 0.05)
    }
    static func stageSecondary(_ scheme: ColorScheme) -> Color {
        stageInk(scheme).opacity(scheme == .dark ? 0.56 : 0.62)
    }
    static func stageRule(_ scheme: ColorScheme) -> Color {
        stageInk(scheme).opacity(scheme == .dark ? 0.14 : 0.10)
    }
    static func signalInk(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? orange : Color(red: 0.72, green: 0.12, blue: 0.09)
    }
    static func successInk(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? mint : Color(red: 0.00, green: 0.46, blue: 0.25)
    }
}

enum WildSpace {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 34
}

struct WildPanelShape: Shape {
    var cut: CGFloat = 14
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: min(cut, min(rect.width, rect.height) / 2), style: .continuous)
    }
}

struct WildTicketShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: min(11, rect.height / 2), style: .continuous)
    }
}

struct WildBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        WildColor.canvas(scheme).ignoresSafeArea()
    }
}

struct WildHeader<Trailing: View>: View {
    let kicker: String
    let title: String
    @ViewBuilder let trailing: Trailing
    @Environment(\.colorScheme) private var scheme

    init(_ title: String, kicker: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.kicker = kicker; self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker.uppercased())
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(WildColor.secondary(scheme))
                Text(title)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .tracking(-1.3)
                    .foregroundStyle(WildColor.ink(scheme))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            trailing
        }
    }
}

extension WildHeader where Trailing == EmptyView {
    init(_ title: String, kicker: String) { self.init(title, kicker: kicker) { EmptyView() } }
}

struct WildSectionLabel: View {
    let index: String
    let title: String
    var detail: String? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(index)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(WildColor.onBlue)
                .frame(width: 27, height: 20)
                .background(WildColor.blue)
                .clipShape(WildTicketShape())
            Text(title).font(.system(.headline, design: .rounded, weight: .black))
            Spacer()
            if let detail {
                Text(detail).font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(WildColor.secondary(scheme))
            }
        }
        .foregroundStyle(WildColor.ink(scheme))
    }
}

struct WildSurface<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme
    init(tint: Color? = nil, @ViewBuilder content: () -> Content) { self.tint = tint; self.content = content() }
    var body: some View {
        content
            .background(tint?.opacity(scheme == .dark ? 0.14 : 0.10) ?? WildColor.paper(scheme))
            .clipShape(WildPanelShape())
            .overlay { WildPanelShape().stroke(WildColor.rule(scheme), lineWidth: 1) }
    }
}

struct WildRule: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Rectangle().fill(WildColor.rule(scheme)).frame(height: 1) }
}

struct WildStamp: View {
    let text: String
    var tint: Color = WildColor.acid
    var foreground: Color = WildColor.onAcid
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(foreground)
            .padding(.horizontal, 9).frame(minHeight: 28)
            .background(tint).clipShape(WildTicketShape())
    }
}

struct WildPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct WildActionStyle: ButtonStyle {
    var tint: Color = WildColor.blue
    var foreground: Color = WildColor.onBlue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(tint.brightness(configuration.isPressed ? -0.08 : 0))
            .clipShape(WildPanelShape(cut: 11))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct WildIconButton: View {
    let symbol: String
    var tint: Color = WildColor.acid
    var foreground: Color = WildColor.onAcid
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            RailGlyph(systemName: symbol).font(.system(size: 16, weight: .black))
                .foregroundStyle(foreground)
                .frame(width: 46, height: 46)
                .background(tint).clipShape(WildTicketShape())
        }.buttonStyle(WildPressStyle())
    }
}

struct WildSegmented<Value: Hashable>: View {
    let values: [(Value, String)]
    @Binding var selection: Value
    @Namespace private var ns
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            ForEach(values, id: \.0) { value, label in
                Button {
                    if reduceMotion { selection = value } else { withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { selection = value } }
                } label: {
                    Text(label).font(.system(.caption, design: .rounded, weight: .black))
                        .foregroundStyle(selection == value ? WildColor.onAcid : WildColor.secondary(scheme))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background {
                            if selection == value {
                                WildTicketShape().fill(WildColor.acid).matchedGeometryEffect(id: "wild-segment", in: ns)
                            }
                        }
                }.buttonStyle(.plain)
            }
        }
        .padding(4).background(WildColor.raised(scheme)).clipShape(WildPanelShape(cut: 10))
    }
}

struct WildWaveform: View {
    let samples: [Float]
    var tint: Color = WildColor.acid
    var playhead: Double? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { proxy in
            let values = samples.isEmpty ? Array(repeating: Float(0.18), count: 48) : samples
            ZStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, sample in
                        Rectangle().fill(index.isMultiple(of: 7) ? tint : tint.opacity(0.40))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(3, CGFloat(min(1, abs(sample))) * proxy.size.height))
                    }
                }
                if let playhead {
                    Rectangle().fill(WildColor.stageInk(scheme)).frame(width: 2)
                        .offset(x: max(0, min(proxy.size.width - 2, proxy.size.width * playhead)))
                }
            }
        }.accessibilityHidden(true)
    }
}

struct WildMiniTrack: View {
    let seed: Int
    var tint = WildColor.orange
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<16, id: \.self) { index in
                Rectangle().fill(index.isMultiple(of: 5) ? tint : tint.opacity(0.34))
                    .frame(maxWidth: .infinity).frame(height: CGFloat(5 + abs((seed &+ index * 17) % 30)))
            }
        }.accessibilityHidden(true)
    }
}

struct WildTimelineTicks: View {
    var count = 18
    var tint: Color = WildColor.orange
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                Rectangle().fill(index.isMultiple(of: 5) ? tint : WildColor.rule(scheme))
                    .frame(maxWidth: .infinity).frame(height: index.isMultiple(of: 5) ? 10 : 4)
            }
        }.frame(height: 10, alignment: .top).accessibilityHidden(true)
    }
}

struct WildEmptyState: View {
    let title: String
    let detail: String
    let symbol: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 16) {
            RailGlyph(systemName: symbol).font(.system(size: 25, weight: .black))
                .foregroundStyle(WildColor.onAcid).frame(width: 58, height: 58).background(WildColor.acid).clipShape(WildTicketShape())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(.headline, design: .rounded, weight: .black))
                Text(detail).font(.system(.caption, design: .rounded)).foregroundStyle(WildColor.secondary(scheme))
            }
            Spacer()
        }.foregroundStyle(WildColor.ink(scheme)).padding(18).frame(maxWidth: .infinity, minHeight: 104)
    }
}

struct WildToast: View {
    let message: String
    var body: some View {
        Text(message).font(.system(.caption, design: .rounded, weight: .black))
            .foregroundStyle(WildColor.onAcid).padding(.horizontal, 16).frame(minHeight: 42)
            .background(WildColor.acid).clipShape(WildTicketShape()).shadow(color: .black.opacity(0.22), radius: 8, y: 5)
            .padding(.top, 8)
    }
}

extension View {
    func wildPage() -> some View { padding(.horizontal, 18).padding(.top, 16) }
    func wildEntrance(_ delay: Double = 0) -> some View { modifier(WildEntrance(delay: delay)) }
}

private struct WildEntrance: ViewModifier {
    let delay: Double
    func body(content: Content) -> some View {
        content
            .transition(.opacity.combined(with: .offset(x: -18, y: 8)))
            .animation(.spring(response: 0.42 + delay, dampingFraction: 0.78), value: delay)
    }
}
