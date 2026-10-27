import SwiftUI

struct FrameRailRootView: View {
    enum Destination: String, CaseIterable, Hashable {
        case capture = "录制"
        case studio = "创作"
        case library = "作品"
        case transcode = "转码"
        case settings = "设置"

        var symbol: String {
            switch self {
            case .capture: "record.circle"
            case .studio: "slider.horizontal.below.square.filled.and.square"
            case .library: "rectangle.stack"
            case .transcode: "arrow.left.arrow.right"
            case .settings: "gearshape"
            }
        }
    }

    @State private var destination: Destination
    @State private var launchToken = 0
    @State private var presentsOnboarding = false
    @State private var previousDestination: Destination = .capture
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
                RailBackground()
                if sizeClass == .regular {
                    HStack(spacing: 0) {
                        sideRail
                        RailHairline().frame(width: 1)
                        content
                    }
                } else {
                    content
                    floatingDock
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Recording.self) { RailVideoEditorView(recording: $0) }
            .navigationDestination(for: AudioRecording.self) { RailAudioEditorView(recording: $0) }
        }
        .onAppear {
            #if !DEBUG
            presentsOnboarding = !didCompleteWelcome || !didCompletePermissions
            #endif
        }
        .fullScreenCover(isPresented: $presentsOnboarding) {
            RailOnboardingFlow(
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await library.reload() } }
        }
        .onOpenURL { url in
            guard url.scheme == "mono" else { return }
            switch url.host {
            case "capture": select(.capture); launchToken &+= 1
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
            RailAudioRecorderView()
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
                RailCaptureView(launchToken: launchToken)
            case .studio: RailStudioView()
            case .library: RailLibraryView()
            case .transcode: RailTranscodeView()
            case .settings: RailSettingsView()
            }
        }
        .id(destination)
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(x: direction * 18)),
            removal: .opacity
        ))
    }

    private var direction: CGFloat {
        let values = Destination.allCases
        return (values.firstIndex(of: destination) ?? 0) >= (values.firstIndex(of: previousDestination) ?? 0) ? 1 : -1
    }

    private var floatingDock: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(Destination.allCases, id: \.self) { item in
                    dockItem(item)
                }
            }
            .padding(6)
            .frame(maxWidth: 470)
            .glassEffect(.regular, in: .rect(cornerRadius: 25))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func dockItem(_ item: Destination) -> some View {
        let selected = destination == item
        let selectedForeground = item == .capture ? RailColor.coral : RailColor.onSelection(scheme)
        return Button {
            if item == .capture, selected { launchToken &+= 1 }
            select(item)
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    if item == .capture {
                        Circle()
                            .fill(RailColor.coral)
                            .frame(width: selected ? 34 : 28, height: selected ? 34 : 28)
                    }
                    RailGlyph(systemName: item.symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(item == .capture ? .white : selected ? selectedForeground : RailColor.secondary(scheme))
                }
                if selected {
                    Text(item.rawValue)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(selected ? selectedForeground : RailColor.secondary(scheme))
            .padding(.horizontal, selected ? 11 : 8)
            .frame(minHeight: 46)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(item == .capture ? RailColor.coral.opacity(0.16) : RailColor.selection(scheme))
                        .matchedGeometryEffect(id: "dock-focus", in: dockNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RailPressStyle())
        .accessibilityLabel(item.rawValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var sideRail: some View {
        VStack(spacing: 12) {
            Text("M")
                .font(.system(size: 21, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(RailColor.coral)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding(.bottom, 22)
            ForEach(Destination.allCases, id: \.self) { item in
                Button { select(item) } label: {
                    VStack(spacing: 5) {
                        RailGlyph(systemName: item.symbol).font(.system(size: 18, weight: .bold))
                        Text(item.rawValue).font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(destination == item ? RailColor.coral : RailColor.secondary(scheme))
                    .frame(width: 68, height: 58)
                    .background(destination == item ? RailColor.raised(scheme) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(RailPressStyle())
            }
            Spacer()
        }
        .padding(.vertical, 18)
        .frame(width: 92)
        .background(RailColor.surface(scheme))
    }

    private func select(_ item: Destination) {
        guard item != destination else { return }
        previousDestination = destination
        if reduceMotion { destination = item }
        else { withAnimation(.smooth(duration: 0.32)) { destination = item } }
    }
}
