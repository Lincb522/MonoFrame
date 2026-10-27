import SwiftUI

struct WildCutRootView: View {
    enum Destination: String, CaseIterable, Hashable {
        case capture = "开拍"
        case studio = "混剪"
        case library = "片库"
        case transcode = "变形"
        case settings = "控制"

        var symbol: String {
            switch self {
            case .capture: "record.circle"
            case .studio: "slider.horizontal.below.square.filled.and.square"
            case .library: "rectangle.stack"
            case .transcode: "arrow.left.arrow.right"
            case .settings: "gearshape"
            }
        }
        var code: String { String(format: "%02d", Self.allCases.firstIndex(of: self)! + 1) }
        var tint: Color {
            switch self {
            case .capture: WildColor.orange
            case .studio: WildColor.blue
            case .library: WildColor.blue
            case .transcode: WildColor.blue
            case .settings: WildColor.blue
            }
        }
    }

    @State private var destination: Destination
    @State private var previous: Destination = .capture
    @State private var launchToken = 0
    @State private var presentsOnboarding = false
    @Namespace private var dockNamespace
    @AppStorage("didCompleteWelcomeV1") private var didCompleteWelcome = false
    @AppStorage("didCompleteInitialPermissionSetupV2") private var didCompletePermissions = false
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        #if DEBUG
        let section = ProcessInfo.processInfo.environment["MONO_SCREENSHOT_SECTION"]
        let initial: Destination
        switch section {
        case "studio": initial = .studio
        case "library": initial = .library
        case "transcode": initial = .transcode
        case "settings": initial = .settings
        default: initial = .capture
        }
        _destination = State(initialValue: initial)
        #else
        _destination = State(initialValue: .capture)
        #endif
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                WildBackground()
                if sizeClass == .regular {
                    HStack(spacing: 0) { sideDeck; content }
                } else {
                    content
                    bottomDeck
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Recording.self) { WildVideoEditorView(recording: $0) }
            .navigationDestination(for: AudioRecording.self) { WildAudioEditorView(recording: $0) }
        }
        .onAppear {
            #if !DEBUG
            presentsOnboarding = !didCompleteWelcome || !didCompletePermissions
            #endif
        }
        .fullScreenCover(isPresented: $presentsOnboarding) {
            WildOnboardingFlow(
                needsWelcome: !didCompleteWelcome,
                needsPermissions: !didCompletePermissions,
                welcomeCompleted: { didCompleteWelcome = true },
                completion: {
                    didCompleteWelcome = true
                    didCompletePermissions = true
                    presentsOnboarding = false
                }
            )
        }
        .sensoryFeedback(.selection, trigger: destination)
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await library.reload() } } }
        .onOpenURL { url in
            guard url.scheme == "mono" else { return }
            switch url.host {
            case "capture": choose(.capture); launchToken &+= 1
            case "studio": choose(.studio)
            case "library": choose(.library)
            case "transcode": choose(.transcode)
            case "settings": choose(.settings)
            default: break
            }
        }
    }

    @ViewBuilder private var content: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MONO_SCREENSHOT_SECTION"] == "audio" { WildAudioRecorderView() }
        else { destinationContent }
        #else
        destinationContent
        #endif
    }

    @ViewBuilder private var destinationContent: some View {
        Group {
            switch destination {
            case .capture: WildCaptureView(launchToken: launchToken)
            case .studio: WildStudioView()
            case .library: WildLibraryView()
            case .transcode: WildTranscodeView()
            case .settings: WildSettingsView()
            }
        }
        .id(destination)
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(x: direction * 24)).combined(with: .scale(scale: 0.985)),
            removal: .opacity.combined(with: .offset(x: direction * -10))
        ))
    }

    private var direction: CGFloat {
        let all = Destination.allCases
        return (all.firstIndex(of: destination) ?? 0) >= (all.firstIndex(of: previous) ?? 0) ? 1 : -1
    }

    private var bottomDeck: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Destination.allCases, id: \.self) { deckItem($0) }
            }
            .padding(5)
            .frame(maxWidth: 520)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }
        .padding(.horizontal, 12).padding(.bottom, 7)
    }

    private func deckItem(_ item: Destination) -> some View {
        let selected = destination == item
        return Button {
            if selected && item == .capture { launchToken &+= 1 }
            choose(item)
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    Text(item.code).font(.system(size: 8, weight: .black, design: .monospaced)).opacity(selected ? 1 : 0)
                    RailGlyph(systemName: item.symbol).font(.system(size: 16, weight: .black))
                }
                Text(item.rawValue).font(.system(size: 10, weight: .black, design: .rounded))
            }
            .foregroundStyle(selected ? selectedForeground(for: item) : WildColor.secondary(scheme))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                if selected {
                    WildTicketShape().fill(item.tint).matchedGeometryEffect(id: "wild-dock", in: dockNamespace)
                }
            }
            .offset(y: selected ? -2 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(WildPressStyle())
        .accessibilityLabel(item.rawValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var sideDeck: some View {
        VStack(spacing: 11) {
            Text("MF").font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(WildColor.onAcid).frame(width: 54, height: 54).background(WildColor.acid).clipShape(WildTicketShape())
                .rotationEffect(.degrees(-3)).padding(.bottom, 18)
            ForEach(Destination.allCases, id: \.self) { item in
                Button { choose(item) } label: {
                    VStack(spacing: 5) {
                        RailGlyph(systemName: item.symbol).font(.system(size: 18, weight: .black))
                        Text(item.rawValue).font(.system(size: 10, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(destination == item ? selectedForeground(for: item) : WildColor.secondary(scheme))
                    .frame(width: 68, height: 60)
                    .background(destination == item ? item.tint : .clear)
                    .clipShape(WildTicketShape())
                }.buttonStyle(WildPressStyle())
            }
            Spacer()
        }
        .padding(.top, 18).frame(width: 94)
        .background(WildColor.paper(scheme).opacity(0.84))
    }

    private func choose(_ item: Destination) {
        guard item != destination else { return }
        previous = destination
        if reduceMotion { destination = item }
        else { withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { destination = item } }
    }

    private func selectedForeground(for item: Destination) -> Color {
        item == .capture ? WildColor.onOrange : WildColor.onBlue
    }
}
