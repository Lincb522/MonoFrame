import SwiftUI
import UIKit

struct MonoPageHeader<Accessory: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let accessory: () -> Accessory
    @Environment(\.colorScheme) private var scheme

    init(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.detail = detail
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .tracking(-0.8)
                if let detail {
                    Text(detail)
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            accessory()
        }
        .frame(minHeight: 48)
        .foregroundStyle(MonoTheme.ink(scheme))
        .accessibilityElement(children: .contain)
    }
}

extension MonoPageHeader where Accessory == EmptyView {
    init(_ title: String, detail: String? = nil) {
        self.init(title, detail: detail) { EmptyView() }
    }
}

struct MonoSectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .black))
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct MonoStatusBadge: View {
    let title: String
    let symbol: String
    var active = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 7) {
            MonoIcon(symbol, size: 15, weight: 2.1)
                .foregroundStyle(active ? MonoTheme.coral : MonoTheme.muted(scheme))
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .black))
        }
        .foregroundStyle(MonoTheme.ink(scheme))
        .padding(.horizontal, 11)
        .frame(minHeight: 36)
        .background(SignalColor.surface(scheme))
        .clipShape(Capsule())
        .overlay { Capsule().stroke(SignalColor.rule(scheme), lineWidth: 1) }
    }
}

struct MonoPrimaryButtonLabel: View {
    let title: String
    var detail: String?
    var symbol = "arrow.right"
    var isLoading = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            if isLoading { ProgressView().tint(.white) }
            Text(title)
            Spacer(minLength: 12)
            if let detail {
                Text(detail)
                    .font(.system(.caption, design: .monospaced, weight: .black))
                    .opacity(0.8)
            }
            MonoIcon(symbol, size: 16, weight: 2.2)
        }
        .font(.system(.body, design: .rounded, weight: .black))
        .foregroundStyle(.black)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(SignalColor.acid)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct MonoHairline: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(MonoTheme.divider(scheme))
            .frame(height: 1 / UIScreen.main.scale)
            .accessibilityHidden(true)
    }
}

struct MonoSpringPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.86), value: configuration.isPressed)
    }
}
