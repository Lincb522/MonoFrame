import SwiftUI

enum PearlAppearance {
    // Keep the user's explicit appearance selection across the redesign.
    static let storageKey = "canvasAppearanceV1"
    static let defaultValue = "light"
    static let options = [("system", "跟随系统"), ("light", "浅色"), ("dark", "深色")]
}

enum PearlColor {
    static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
    static func background(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0x201F1C : 0xE5E1D8) }
    static func surface(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0x2A2925 : 0xEDEAE3) }
    static func elevated(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0x37352F : 0xD8D3C9) }
    static func ink(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0xF0EDE5 : 0x20211E) }
    static func secondary(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0xBDB8AB : 0x665F53) }
    static func tertiary(_ scheme: ColorScheme) -> Color { secondary(scheme) }
    static func accent(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0xFF784C : 0xA33316) }
    static func onAccent(_ scheme: ColorScheme) -> Color { rgb(0x201B15) }
    static func display(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0xFF784C : 0xD84920) }
    static func action(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0xFF784C : 0xF56335) }
    static func danger(_ scheme: ColorScheme) -> Color { rgb(scheme == .dark ? 0xFF9884 : 0xAA2920) }
    static let coral = rgb(0xF56335)
    static func hairline(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color.white.opacity(0.13) : rgb(0xBEB8AB) }
}

struct PearlBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { PearlColor.background(scheme).ignoresSafeArea() }
}

struct PearlPage<Content: View>: View {
    var horizontalPadding: CGFloat = 20
    var topPadding: CGFloat = 12
    var maxWidth: CGFloat = 960
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView {
            content()
                .frame(maxWidth: maxWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(PearlBackdrop())
    }
}

struct PearlSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        content().background(PearlColor.surface(scheme), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PearlPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(!enabled ? 0.42 : configuration.isPressed ? 0.76 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PearlHairline: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { PearlColor.hairline(scheme).frame(height: 0.7).accessibilityHidden(true) }
}

struct PearlIconButton: View {
    let title: String
    let glyph: PearlGlyphName
    var filled = false
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            PearlGlyph(glyph, size: 22)
                .foregroundStyle(PearlColor.ink(scheme))
                .frame(width: 44, height: 44)
                .background(filled ? PearlColor.surface(scheme) : .clear, in: Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(PearlPressStyle())
        .accessibilityLabel(title)
    }
}

struct PearlPrimaryLabel: View {
    let title: String
    var glyph: PearlGlyphName? = nil
    var busy = false
    var recording = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 14) {
            if busy { ProgressView().tint(PearlColor.onAccent(scheme)) }
            else if recording {
                Circle().strokeBorder(PearlColor.onAccent(scheme), lineWidth: 2)
                    .frame(width: 25, height: 25)
                    .overlay { Circle().fill(PearlColor.onAccent(scheme)).frame(width: 13, height: 13) }
            } else if let glyph { PearlGlyph(glyph, size: 21) }
            Text(title).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if !busy { PearlGlyph(.chevronRight, size: 18) }
        }
        .foregroundStyle(PearlColor.onAccent(scheme))
        .padding(.horizontal, 22).padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: recording ? 72 : 56)
        .background(PearlColor.action(scheme), in: Capsule())
        .contentShape(Capsule())
    }
}

struct PearlRootHeader<Trailing: View>: View {
    let title: String
    var brand = false
    @ViewBuilder let trailing: () -> Trailing
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                if brand { Text("MonoFrame").font(.subheadline.weight(.semibold)).foregroundStyle(PearlColor.secondary(scheme)) }
                Text(title).font(.largeTitle.weight(.heavy)).tracking(-0.7)
                    .foregroundStyle(PearlColor.ink(scheme)).accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.bottom, 8)
    }
}

struct PearlPlainRow<Trailing: View>: View {
    let title: String
    var accessibilityValue: String? = nil
    @ViewBuilder let trailing: () -> Trailing
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    init(_ title: String, accessibilityValue: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title; self.accessibilityValue = accessibilityValue; self.trailing = trailing
    }
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { Text(title); trailing() }.padding(.vertical, 13)
            } else {
                HStack(spacing: 16) { Text(title); Spacer(minLength: 8); trailing() }.frame(minHeight: 56)
            }
        }
        .font(.body).foregroundStyle(PearlColor.ink(scheme))
        .contentShape(Rectangle())
    }
}

struct PearlRowValue: View {
    let value: String
    var navigates = true
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 8) {
            if !value.isEmpty { Text(value).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
            if navigates { PearlGlyph(.chevronRight, size: 15) }
        }.foregroundStyle(PearlColor.secondary(scheme))
    }
}

struct PearlSectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View { Text(title).font(.headline).accessibilityAddTraits(.isHeader) }
}

struct PearlInlineNotice: View {
    enum Tone { case info, warning, error }
    let message: String
    var tone: Tone = .info
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PearlGlyph(tone == .info ? .info : .warning, size: 18).padding(.top, 2)
            Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(tone == .error ? PearlColor.danger(scheme) : PearlColor.ink(scheme))
        .padding(14)
        .background(PearlColor.elevated(scheme), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

struct PearlEmptyState: View {
    let glyph: PearlGlyphName
    let title: String
    let message: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 15) {
            PearlGlyph(glyph, size: 42).foregroundStyle(PearlColor.accent(scheme))
                .padding(24).background(PearlColor.elevated(scheme), in: Circle())
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(PearlColor.ink(scheme))
            Text(message).font(.subheadline).foregroundStyle(PearlColor.secondary(scheme))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 38)
    }
}

struct PearlSecondaryHeader<Trailing: View>: View {
    let title: String
    var backTitle = "返回"
    var onBack: (() -> Void)? = nil
    @ViewBuilder let trailing: () -> Trailing
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 8) {
            PearlIconButton(title: backTitle, glyph: .back) { if let onBack { onBack() } else { dismiss() } }
            Text(title).font(.headline).foregroundStyle(PearlColor.ink(scheme))
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }.padding(.horizontal, 12).padding(.vertical, 7)
    }
}

struct PearlSecondaryLayout<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            PearlSecondaryHeader(title: title) { EmptyView() }
            content()
        }
        .background(PearlBackdrop()).toolbar(.hidden, for: .navigationBar)
    }
}

struct PearlCountHeading: View {
    let count: Int
    let label: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(count.formatted(.number.precision(.integerLength(2))))
                .font(.system(size: typeSize.isAccessibilitySize ? 54 : 88, weight: .bold))
                .monospacedDigit().tracking(-3).foregroundStyle(PearlColor.display(scheme))
            Text(label).font(.title3.weight(.medium)).foregroundStyle(PearlColor.secondary(scheme))
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(count) \(label)")
    }
}

/// Each dot represents one second in the current minute, or one completed portion of a task.
struct PearlDotMatrix: View {
    let progress: Double
    var columns = 10
    var rows = 6
    var active = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { context, size in
            let cell = min(size.width / CGFloat(columns), size.height / CGFloat(rows))
            let diameter = max(2, cell - 5)
            for index in 0..<(columns * rows) {
                let rect = CGRect(x: CGFloat(index % columns) * cell + 2.5,
                                  y: CGFloat(index / columns) * cell + 2.5,
                                  width: diameter, height: diameter)
                let path = Path(ellipseIn: rect)
                let completed = index < Int(progress * Double(columns * rows))
                if completed { context.fill(path, with: .color(PearlColor.ink(scheme))) }
                else if active && index == Int(progress * Double(columns * rows)) {
                    context.fill(path, with: .color(PearlColor.action(scheme)))
                } else { context.fill(path, with: .color(PearlColor.elevated(scheme))) }
            }
        }.accessibilityHidden(true)
    }
}
