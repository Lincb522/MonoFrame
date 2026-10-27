import SwiftUI

struct SignalRootView: View {
    enum Destination: String, CaseIterable {
        case capture = "录屏"
        case studio = "创作"
        case library = "作品"
        case transcode = "转码"
        case settings = "设置"

        var symbol: String {
            switch self {
            case .capture: "record.circle"
            case .studio: "scissors"
            case .library: "rectangle.stack"
            case .transcode: "arrow.triangle.2.circlepath"
            case .settings: "slider.horizontal.3"
            }
        }
    }

    @State private var destination: Destination
    @State private var broadcastLaunchToken = 0
    @State private var presentsOnboarding = false
    @State private var transitionDirection: CGFloat = 1
    @State private var dockPresented = false
    @Namespace private var dockSpace
    @AppStorage("didCompleteWelcomeV1") private var didCompleteWelcome = false
    @AppStorage("didCompleteInitialPermissionSetupV2") private var didCompletePermissionSetup = false
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let leftDockItems: [Destination] = [.studio, .library]
    private let rightDockItems: [Destination] = [.transcode, .settings]

    init() {
        #if DEBUG
        let requested = ProcessInfo.processInfo.environment["MONO_SCREENSHOT_SECTION"]
        let initial: Destination = switch requested {
        case "studio": .studio
        case "library": .library
        case "transcode": .transcode
        case "settings": .settings
        default: .capture
        }
        _destination = State(initialValue: initial)
        #else
        _destination = State(initialValue: .capture)
        #endif
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                SignalPageBackground()
                if horizontalSizeClass == .regular {
                    HStack(spacing: 0) {
                        sidebar
                        SignalRule().frame(width: 1)
                        content
                    }
                } else {
                    content
                    dock
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Recording.self) { EditorView(recording: $0) }
            .navigationDestination(for: AudioRecording.self) { AudioEditorView(recording: $0) }
        }
        .onAppear {
            #if !DEBUG
            presentsOnboarding = !didCompleteWelcome || !didCompletePermissionSetup
            #endif
            if reduceMotion {
                dockPresented = true
            } else if !dockPresented {
                withAnimation(.spring(response: 0.62, dampingFraction: 0.72).delay(0.6)) {
                    dockPresented = true
                }
            }
        }
        .fullScreenCover(isPresented: $presentsOnboarding) {
            OnboardingFlowView(
                needsWelcome: !didCompleteWelcome,
                needsPermissions: !didCompletePermissionSetup,
                welcomeCompleted: { didCompleteWelcome = true },
                completion: {
                    didCompleteWelcome = true
                    didCompletePermissionSetup = true
                    presentsOnboarding = false
                }
            )
        }
        .sensoryFeedback(.selection, trigger: destination)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await library.reload() } }
        }
        .onOpenURL { url in
            guard url.scheme == "mono" else { return }
            switch url.host {
            case "capture":
                select(.capture)
                broadcastLaunchToken &+= 1
            case "studio": select(.studio)
            case "library": select(.library)
            case "transcode": select(.transcode)
            case "settings": select(.settings)
            default: break
            }
        }
    }

    @ViewBuilder private var content: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MONO_SCREENSHOT_SECTION"] == "audio" {
            AudioRecorderView()
        } else {
            destinationContent
        }
        #else
        destinationContent
        #endif
    }

    @ViewBuilder private var destinationContent: some View {
        Group {
            switch destination {
            case .capture:
                SignalCaptureView(
                    launchToken: broadcastLaunchToken,
                    openAudio: { select(.studio) },
                    openLibrary: { select(.library) }
                )
            case .studio: SignalStudioView()
            case .library: SignalLibraryView()
            case .transcode: SignalTranscodeView()
            case .settings: SignalSettingsView()
            }
        }
        .id(destination)
        .transition(
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .opacity.combined(with: .offset(x: transitionDirection * 22)),
                    removal: .opacity.combined(with: .scale(scale: 0.992))
                )
        )
    }

    private var sidebar: some View {
        VStack(spacing: SignalSpace.xs) {
            Text("M")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(SignalColor.inverseInk(scheme))
                .frame(width: 48, height: 48)
                .background(SignalColor.ink(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .padding(.bottom, SignalSpace.lg)

            ForEach(Destination.allCases, id: \.self) { item in
                navigationButton(item, compact: false)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, SignalSpace.md)
        .frame(width: 92)
        .background(SignalColor.surface(scheme))
    }

    private var dock: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 4) {
                ForEach(leftDockItems, id: \.self) { transportButton($0) }
                Color.clear.frame(width: 72)
                ForEach(rightDockItems, id: \.self) { transportButton($0) }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
            .frame(height: 70)

            transportCaptureButton
                .offset(y: -20)
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .padding(.bottom, 7)
        .offset(y: dockPresented || reduceMotion ? 0 : 120)
        .opacity(dockPresented ? 1 : 0)
    }

    private func transportButton(_ item: Destination) -> some View {
        let selected = destination == item
        return Button { select(item) } label: {
            VStack(spacing: 4) {
                Image(systemName: item.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .symbolEffect(.bounce, value: selected)
                Text(item.rawValue)
                    .font(.system(size: 10, weight: selected ? .bold : .semibold, design: .rounded))
            }
            .foregroundStyle(selected ? SignalColor.acid : SignalColor.secondary(scheme))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .fill(SignalColor.ink(scheme))
                        .matchedGeometryEffect(id: "transport-selection", in: dockSpace)
                } else {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .fill(SignalColor.surface(scheme).opacity(0.58))
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 19))
                }
            }
            .padding(.horizontal, 2)
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.20 : 0.08), radius: 8, y: 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(SignalPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var transportCaptureButton: some View {
        let selected = destination == .capture
        return Button { select(.capture) } label: {
            TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { context in
                SignalDockCaptureOrb(
                    selected: selected,
                    phase: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                )
            }
            .frame(width: 76, height: 76)
        }
        .buttonStyle(SignalPressStyle())
        .accessibilityLabel("录屏")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func navigationButton(_ item: Destination, compact: Bool) -> some View {
        let selected = destination == item
        return Button { select(item) } label: {
            VStack(spacing: 5) {
                ZStack {
                    if item == .capture && selected {
                        Circle().fill(SignalColor.coral).frame(width: 30, height: 30)
                    }
                    Image(systemName: item.symbol)
                        .font(.system(size: item == .capture ? 19 : 17, weight: .bold))
                        .foregroundStyle(item == .capture && selected ? .white : selected ? SignalColor.ink(scheme) : SignalColor.secondary(scheme))
                }
                .frame(height: 30)
                Text(item.rawValue)
                    .font(.system(size: 10, weight: selected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(selected ? SignalColor.ink(scheme) : SignalColor.secondary(scheme))
            }
            .frame(maxWidth: compact ? .infinity : 72, minHeight: compact ? 52 : 58)
            .background(selected && !compact ? SignalColor.raised(scheme) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: compact ? .top : .leading) {
                if selected && item != .capture {
                    Rectangle().fill(SignalColor.coral)
                        .frame(width: compact ? 18 : 3, height: compact ? 2 : 18)
                }
            }
        }
        .buttonStyle(SignalPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func select(_ target: Destination) {
        guard target != destination else {
            if target == .capture { broadcastLaunchToken &+= 1 }
            return
        }
        let all = Destination.allCases
        let currentIndex = all.firstIndex(of: destination) ?? 0
        let targetIndex = all.firstIndex(of: target) ?? currentIndex
        transitionDirection = targetIndex >= currentIndex ? 1 : -1
        if reduceMotion { destination = target }
        else { withAnimation(.spring(response: 0.34, dampingFraction: 1)) { destination = target } }
    }
}

private struct SignalDockCaptureOrb: View {
    let selected: Bool
    let phase: TimeInterval
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let breathing = reduceMotion || !selected ? 1 : 1 + CGFloat(sin(phase * 2.4)) * 0.035
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(SignalColor.canvas(scheme))
                .frame(width: 76, height: 76)

            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(SignalColor.ink(scheme))
                .frame(width: 66, height: 66)

            Circle()
                .fill(selected ? SignalColor.coral.opacity(0.24) : SignalColor.acid.opacity(0.15))
                .frame(width: 50, height: 50)

            YouthRingSegment(
                from: 0.05,
                to: 0.95,
                animationProgress: selected ? 0.95 : 0.36,
                tint: SignalColor.acid,
                lineWidth: 3
            )
            .rotationEffect(.degrees(-90 + (selected && !reduceMotion ? phase * 12 : 0)))
            .frame(width: 54, height: 54)

            RoundedRectangle(cornerRadius: selected ? 12 : 18, style: .continuous)
                .fill(SignalColor.coral)
                .frame(width: selected ? 34 : 30, height: selected ? 34 : 30)
                .scaleEffect(breathing)

            Circle()
                .stroke(Color.white.opacity(0.92), lineWidth: 3)
                .frame(width: 14, height: 14)
        }
        .rotationEffect(.degrees(selected && !reduceMotion ? sin(phase * 1.4) * 1.5 : 0))
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: selected)
    }
}
