import SwiftUI

struct OnboardingFlowView: View {
    private enum Stage { case welcome, permissions }

    let needsPermissions: Bool
    let welcomeCompleted: () -> Void
    let completion: () -> Void
    @State private var stage: Stage

    init(
        needsWelcome: Bool,
        needsPermissions: Bool,
        welcomeCompleted: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        self.needsPermissions = needsPermissions
        self.welcomeCompleted = welcomeCompleted
        self.completion = completion
        _stage = State(initialValue: needsWelcome ? .welcome : .permissions)
    }

    var body: some View {
        Group {
            switch stage {
            case .welcome:
                WelcomeView {
                    welcomeCompleted()
                    if needsPermissions {
                        withAnimation(.easeOut(duration: 0.22)) { stage = .permissions }
                    } else {
                        completion()
                    }
                }
                .transition(.opacity)
            case .permissions:
                PermissionSetupView(completion: completion)
                    .transition(.opacity)
            }
        }
    }
}

struct WelcomeView: View {
    let completion: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MONOFRAME")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                Spacer(minLength: 0)
                SignalStatus(text: "本地处理", kind: .ready)
            }

            Spacer(minLength: 28)

            welcomeStage

            VStack(alignment: .leading, spacing: 8) {
                Text("今天，录点什么？")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .tracking(-0.8)
                Text("录屏、录音、逐帧剪辑与多格式转码，全部在设备端完成。")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(SignalColor.secondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 26)

            Spacer(minLength: 24)

            Button(action: completion) {
                HStack {
                    Text("继续")
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .bold))
                }
                .font(.system(.headline, design: .rounded, weight: .black))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 58)
            }
            .buttonStyle(SignalPrimaryButtonStyle())
        }
        .foregroundStyle(SignalColor.ink(scheme))
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background { SignalPageBackground() }
        .interactiveDismissDisabled()
    }

    private var welcomeStage: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 0.12)) { timeline in
            let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            VStack(spacing: 24) {
                HStack {
                    Label("屏幕录制", systemImage: "rectangle.inset.filled")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(SignalColor.coral).frame(width: 8, height: 8)
                        Text("READY")
                    }
                }
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundStyle(.white.opacity(0.68))

                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<27, id: \.self) { index in
                        let value = abs(sin(phase * 2.4 + Double(index) * 0.58))
                        Capsule()
                            .fill(index.isMultiple(of: 6) ? SignalColor.acid : Color.white.opacity(0.36))
                            .frame(maxWidth: .infinity)
                            .frame(height: 8 + CGFloat(value) * 46)
                    }
                }
                .frame(height: 62)

                ZStack {
                    Circle().stroke(Color.white.opacity(0.74), lineWidth: 2).frame(width: 92, height: 92)
                    Circle().fill(SignalColor.coral).frame(width: 64, height: 64)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 300)
            .background(SignalColor.stage)
            .clipShape(YouthNotchedPanelShape(cornerRadius: 34, notchWidth: 94, notchDepth: 62))
            .overlay(alignment: .topTrailing) {
                YouthStatusBubble(value: "GO", symbol: "bolt.fill")
                    .padding(8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("MonoFrame 屏幕录制")
    }
}
