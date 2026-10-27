import SwiftUI

// Mono Spatial: white space + two accents. Glass is reserved for controls.
enum SpatialColor {
    static let ice = Color(red: 0.42, green: 0.72, blue: 0.91)
    static let iceDeep = Color(red: 0.13, green: 0.50, blue: 0.76)
    static let sea = Color(red: 0.18, green: 0.80, blue: 0.68)
    static let seaDeep = Color(red: 0.04, green: 0.57, blue: 0.49)
    static let ink = Color(red: 0.08, green: 0.12, blue: 0.16)
    static let quiet = Color(red: 0.43, green: 0.49, blue: 0.55)
    static let frost = Color.white.opacity(0.72)
}

struct SpatialBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                (scheme == .dark ? Color(red: 0.025, green: 0.055, blue: 0.075) : Color(red: 0.965, green: 0.985, blue: 0.995))
                GeometryReader { proxy in
                    Image("SpatialIceBackdrop")
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .scaleEffect(1.10)
                        .blur(radius: 18)
                        .opacity(scheme == .dark ? 0.10 : 0.20)
                }
                LinearGradient(
                    colors: scheme == .dark
                        ? [SpatialColor.iceDeep.opacity(0.19), .clear, SpatialColor.seaDeep.opacity(0.13)]
                        : [SpatialColor.ice.opacity(0.20), .clear, SpatialColor.sea.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                fluidBlob(SpatialColor.ice, size: 390, x: 185 + sin(t * 0.12) * 28, y: -330 + cos(t * 0.10) * 22)
                fluidBlob(SpatialColor.sea, size: 300, x: -190 + cos(t * 0.09) * 28, y: 300 + sin(t * 0.11) * 30)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func fluidBlob(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(color.opacity(0.20))
            .frame(width: size, height: size)
            .blur(radius: 92)
            .offset(x: x, y: y)
    }
}

struct SpatialHeading: View {
    let title: String
    var detail: String? = nil
    var accessory: AnyView? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-1.35)
                if let detail {
                    Text(detail)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
        .foregroundStyle(scheme == .dark ? .white : SpatialColor.ink)
    }
}

struct SpatialGlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 1), value: configuration.isPressed)
    }
}

struct SpatialWave: View {
    var active: Bool
    var phase: TimeInterval
    var tint: Color = SpatialColor.sea
    var count = 38

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { index in
                let idle = CGFloat(7 + (index * 13) % 20)
                let live = CGFloat(9 + abs(sin(phase * 3.1 + Double(index) * 0.61)) * 52)
                Capsule()
                    .fill(index.isMultiple(of: 7) ? tint : SpatialColor.ice)
                    .frame(maxWidth: .infinity)
                    .frame(height: active ? live : idle)
                    .animation(.easeOut(duration: 0.16), value: live)
            }
        }
        .frame(height: 72)
        .accessibilityHidden(true)
    }
}

extension View {
    func spatialGlass<S: Shape>(
        _ shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        Group {
            if let tint {
                glassEffect(
                    interactive ? .regular.tint(tint).interactive() : .regular.tint(tint),
                    in: shape
                )
            } else {
                glassEffect(
                    interactive ? .clear.interactive() : .clear,
                    in: shape
                )
            }
        }
        .overlay {
            shape
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), .clear, Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        }
        .overlay {
            shape.stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.92), Color.white.opacity(0.20), Color.white.opacity(0.66)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.85
            )
            .allowsHitTesting(false)
        }
        .shadow(color: SpatialColor.iceDeep.opacity(0.13), radius: 18, y: 10)
    }
}
