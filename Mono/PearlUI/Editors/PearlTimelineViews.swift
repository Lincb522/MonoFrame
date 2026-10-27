import AVFoundation
import SwiftUI

struct PearlPlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }
    func updateUIView(_ view: Surface, context: Context) { view.playerLayer.player = player }
    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

struct PearlTrimTimeline: View {
    let frames: [VideoTimelineFrame]
    let duration: Double
    @Binding var start: Double
    @Binding var end: Double
    @Binding var position: Double
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 9) {
            PearlTimelineRuler(duration: duration)
            PearlRangeTrack(duration: duration, start: $start, end: $end, position: $position) {
                GeometryReader { geometry in
                    if frames.isEmpty {
                        PearlColor.elevated(scheme).overlay { ProgressView().accessibilityLabel("正在读取时间线") }
                    } else {
                        HStack(spacing: 0) {
                            ForEach(frames) { frame in
                                Image(uiImage: frame.image).resizable().scaledToFill()
                                    .frame(width: geometry.size.width / CGFloat(frames.count), height: geometry.size.height).clipped().accessibilityHidden(true)
                            }
                        }
                    }
                }
            }.frame(height: 86)
        }
    }
}

struct PearlAudioSelection: View {
    let samples: [Float]
    let duration: Double
    @Binding var start: Double
    @Binding var end: Double
    @Binding var position: Double
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 15) {
            PearlRangeTrack(duration: duration, start: $start, end: $end, position: $position) {
                PearlWaveform(samples: samples, progress: position / max(0.1, duration)).padding(.vertical, 15)
                    .background(PearlColor.surface(scheme).opacity(0.4))
            }.frame(height: 162)
            PearlTimelineRuler(duration: duration)
        }
    }
}

private struct PearlTimelineRuler: View {
    let duration: Double
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(time(0)); Spacer(); Text(time(duration / 2)); Spacer(); Text(time(duration))
            }.font(.caption2.monospacedDigit()).foregroundStyle(PearlColor.secondary(scheme))
            Canvas { context, size in
                for i in 0...20 {
                    let x = CGFloat(i) * size.width / 20
                    var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: i.isMultiple(of: 5) ? 9 : 5))
                    context.stroke(line, with: .color(PearlColor.secondary(scheme).opacity(0.4)), lineWidth: 0.7)
                }
            }.frame(height: 9).accessibilityHidden(true)
        }.padding(.horizontal, 22)
    }
    private func time(_ value: Double) -> String { let s = max(0, Int(value)); return String(format: "%02d:%02d", s / 60, s % 60) }
}

private struct PearlRangeTrack<Content: View>: View {
    let duration: Double
    @Binding var start: Double
    @Binding var end: Double
    @Binding var position: Double
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 44)
            let height = max(30, geometry.size.height - 18)
            let startX = 22 + width * fraction(start)
            let endX = 22 + width * fraction(end)
            ZStack(alignment: .topLeading) {
                content().frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 10)).offset(x: 22, y: 9)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { event in position = time(event.location.x, width: width) })
                    .accessibilityElement(children: .ignore).accessibilityLabel("播放位置")
                    .accessibilityValue(String(format: "%.1f 秒", position))
                    .accessibilityAdjustableAction { direction in
                        position = min(duration, max(0, position + (direction == .increment ? 0.1 : -0.1)))
                    }
                RoundedRectangle(cornerRadius: 10).fill(PearlColor.accent(scheme).opacity(0.09))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(PearlColor.accent(scheme).opacity(0.75), lineWidth: 2) }
                    .frame(width: max(6, endX - startX), height: height + 4).offset(x: startX, y: 7).allowsHitTesting(false)
                handle("入点", at: startX, height: height, value: $start, width: width)
                handle("出点", at: endX, height: height, value: $end, width: width)
                VStack(spacing: 0) {
                    Circle().frame(width: 7, height: 7)
                    Rectangle().frame(width: 1.4)
                }.foregroundStyle(PearlColor.accent(scheme)).frame(height: height + 18)
                    .position(x: 22 + width * fraction(position), y: geometry.size.height / 2).allowsHitTesting(false)
            }.coordinateSpace(name: "pearlRange")
        }
    }
    private func handle(_ title: String, at x: CGFloat, height: CGFloat, value: Binding<Double>, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(PearlColor.accent(scheme))
            .frame(width: 7, height: min(38, height))
            .frame(width: 44, height: height + 18).contentShape(Rectangle())
            .position(x: x, y: (height + 18) / 2)
            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("pearlRange"))
                .onChanged { event in value.wrappedValue = time(event.location.x - 22, width: width) })
            .accessibilityElement(children: .ignore).accessibilityLabel(title)
            .accessibilityValue(String(format: "%.1f 秒", value.wrappedValue))
            .accessibilityAdjustableAction { direction in
                value.wrappedValue = min(duration, max(0, value.wrappedValue + (direction == .increment ? 0.1 : -0.1)))
            }
    }
    private func fraction(_ value: Double) -> Double { min(1, max(0, value / max(duration, 0.1))) }
    private func time(_ x: CGFloat, width: CGFloat) -> Double { min(duration, max(0, Double(x / width) * duration)) }
}

struct PearlEqualizerFader: View {
    let title: String
    @Binding var value: Double
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 9) {
            GeometryReader { geometry in
                Slider(value: $value, in: -12...12, step: 0.5)
                    .frame(width: geometry.size.height).rotationEffect(.degrees(-90))
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .tint(PearlColor.accent(scheme)).accessibilityLabel(title)
                    .accessibilityValue(String(format: "%+.1f 分贝", value))
            }.frame(height: 136)
            Text(title).font(.caption).foregroundStyle(PearlColor.secondary(scheme))
            Text(String(format: "%+.1f dB", value)).font(.caption.monospacedDigit()).foregroundStyle(PearlColor.ink(scheme))
        }.frame(maxWidth: .infinity)
    }
}
