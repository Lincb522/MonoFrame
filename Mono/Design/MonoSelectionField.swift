import SwiftUI

struct MonoSelectionOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var detail: String? = nil
    var symbol: String? = nil

    var id: Value { value }
}

enum MonoSelectionLayout {
    case compact
    case detailed
}

struct MonoSelectionField<Value: Hashable>: View {
    let title: String
    let symbol: String
    @Binding var selection: Value
    let options: [MonoSelectionOption<Value>]
    var layout: MonoSelectionLayout = .compact
    var maxVisibleOptions = 6

    @State private var isExpanded = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedOption: MonoSelectionOption<Value>? {
        options.first { $0.value == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                toggle()
            } label: {
                collapsedLabel
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(selectedOption?.title ?? "未选择")
            .accessibilityHint(isExpanded ? "收起选项" : "展开选项")

            if isExpanded {
                Divider()
                    .overlay(MonoTheme.muted(scheme).opacity(0.2))
                optionContainer
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var collapsedLabel: some View {
        switch layout {
        case .compact:
            HStack(spacing: 12) {
                MonoIcon(symbol, size: 16, weight: 2.1)
                    .frame(width: 24)
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                Spacer(minLength: 10)
                Text(selectedOption?.title ?? "选择")
                    .font(.system(.caption, design: .rounded, weight: .black))
                    .foregroundStyle(MonoTheme.muted(scheme))
                    .lineLimit(1)
                chevron
            }
            .foregroundStyle(MonoTheme.ink(scheme))
            .frame(minHeight: 58)

        case .detailed:
            HStack(spacing: 12) {
                MonoIcon(symbol, size: 19, weight: 2.1)
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
                    .background(MonoTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedOption?.title ?? title)
                        .font(.system(.body, design: .rounded, weight: .black))
                        .lineLimit(1)
                    if let detail = selectedOption?.detail {
                        Text(detail)
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .foregroundStyle(MonoTheme.muted(scheme))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 10)
                chevron
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(MonoTheme.ink(scheme))
            .frame(minHeight: 58)
        }
    }

    private var chevron: some View {
        MonoIcon("chevron.down", size: 13, weight: 2.2)
            .foregroundStyle(MonoTheme.muted(scheme))
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
    }

    @ViewBuilder
    private var optionContainer: some View {
        if options.count > maxVisibleOptions {
            ScrollView {
                LazyVStack(spacing: 2) { optionRows }
                    .padding(4)
            }
            .scrollIndicators(.hidden)
            .frame(height: CGFloat(maxVisibleOptions) * 52)
            .background(MonoTheme.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(MonoTheme.divider(scheme), lineWidth: 1)
            }
        } else {
            VStack(spacing: 2) { optionRows }
                .padding(4)
                .background(MonoTheme.surface(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(MonoTheme.divider(scheme), lineWidth: 1)
                }
        }
    }

    private var optionRows: some View {
        ForEach(options) { option in
            let selected = option.value == selection
            Button {
                selection = option.value
                close()
            } label: {
                HStack(spacing: 10) {
                    if let symbol = option.symbol {
                        MonoIcon(symbol, size: 15, weight: 2)
                            .frame(width: 24)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.title)
                            .font(.system(.subheadline, design: .rounded, weight: .black))
                        if let detail = option.detail {
                            Text(detail)
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                .foregroundStyle(MonoTheme.muted(scheme))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    MonoIcon(selected ? "checkmark.square.fill" : "square", size: 17, weight: 2.1)
                        .foregroundStyle(selected ? MonoTheme.primary : MonoTheme.muted(scheme).opacity(0.45))
                }
                .foregroundStyle(MonoTheme.ink(scheme))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(selected ? MonoTheme.primary.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    private func toggle() {
        if reduceMotion { isExpanded.toggle() }
        else {
            withAnimation(.easeOut(duration: 0.18)) { isExpanded.toggle() }
        }
    }

    private func close() {
        if reduceMotion { isExpanded = false }
        else {
            withAnimation(.easeOut(duration: 0.18)) { isExpanded = false }
        }
    }
}
