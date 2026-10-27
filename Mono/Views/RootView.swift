import SwiftUI
import UIKit

struct RootView: View {
    enum Section: String, CaseIterable {
        case home = "录屏"
        case library = "作品"
        case studio = "剪辑"
        case transcode = "转码"
        case settings = "设置"

        var icon: String {
            switch self {
            case .home: "record.circle"
            case .library: "rectangle.stack"
            case .studio: "timeline.selection"
            case .transcode: "arrow.triangle.2.circlepath"
            case .settings: "slider.horizontal.3"
            }
        }
    }

    @State private var section: Section
    @State private var broadcastLaunchToken = 0
    @State private var isOnboardingPresented = false
    @Namespace private var tabSelectionNamespace
    @AppStorage("didCompleteWelcomeV1") private var didCompleteWelcome = false
    @AppStorage("didCompleteInitialPermissionSetupV2")
    private var didCompleteInitialPermissionSetup = false
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tabOrder: [Section] = [.library, .studio, .home, .transcode, .settings]

    init() {
        #if DEBUG
        let screenshotSection = ProcessInfo.processInfo.environment["MONO_SCREENSHOT_SECTION"]
        let initialSection: Section = switch screenshotSection {
        case "library": .library
        case "studio": .studio
        case "transcode": .transcode
        case "settings": .settings
        default: .home
        }
        _section = State(initialValue: initialSection)
        #else
        _section = State(initialValue: .home)
        #endif
    }

    var body: some View {
        ZStack {
            MonoImmersiveBackground()
            NavigationStack {
                Group {
                    switch section {
                    case .home:
                        RecordView(
                            broadcastLaunchToken: broadcastLaunchToken,
                            openStudio: { select(.studio) },
                            openLibrary: { select(.library) }
                        )
                    case .library: LibraryView()
                    case .studio: StudioView()
                    case .transcode: TranscodeView()
                    case .settings: SettingsView()
                    }
                }
                .id(section)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Recording.self) { recording in
                    EditorView(recording: recording)
                }
                .navigationDestination(for: AudioRecording.self) { recording in
                    AudioEditorView(recording: recording)
                }
                .background(Color.clear)
            }
        }
        .onAppear {
            isOnboardingPresented = !didCompleteWelcome || !didCompleteInitialPermissionSetup
        }
        .fullScreenCover(isPresented: $isOnboardingPresented) {
            OnboardingFlowView(
                needsWelcome: !didCompleteWelcome,
                needsPermissions: !didCompleteInitialPermissionSetup,
                welcomeCompleted: { didCompleteWelcome = true },
                completion: {
                    didCompleteWelcome = true
                    didCompleteInitialPermissionSetup = true
                    isOnboardingPresented = false
                }
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await library.reload() } }
        }
        .sensoryFeedback(.selection, trigger: section)
        .onOpenURL { url in
            guard url.scheme == "mono" else { return }
            switch url.host {
            case "capture":
                section = .home
                broadcastLaunchToken &+= 1
            case "library": select(.library)
            case "studio": select(.studio)
            case "transcode": select(.transcode)
            case "settings": select(.settings)
            default: select(.home)
            }
        }
    }

    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 8) {
            ForEach(tabOrder, id: \.self) { item in
                item == .home ? AnyView(captureTab(item)) : AnyView(standardTab(item))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassEffect(.regular.interactive(), in: .capsule)
        .shadow(color: MonoTheme.stage.opacity(scheme == .dark ? 0.30 : 0.10), radius: 22, y: 12)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 5)
    }

    private func standardTab(_ item: Section) -> some View {
        let selected = section == item
        return Button { select(item) } label: {
            HStack(spacing: selected ? 6 : 0) {
                MonoIcon(item.icon, size: 18, weight: selected ? 2.2 : 1.75)
                if selected {
                    Text(item.rawValue)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .frame(minWidth: selected ? 66 : 42, minHeight: 44)
            .foregroundStyle(selected ? MonoTheme.ink(scheme) : MonoTheme.muted(scheme))
            .background {
                if selected {
                    Capsule()
                        .fill(MonoTheme.primary.opacity(0.13))
                        .matchedGeometryEffect(id: "tab-selection", in: tabSelectionNamespace)
                }
            }
            .clipShape(Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(MonoSpringPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func captureTab(_ item: Section) -> some View {
        let selected = section == item
        return Button { select(item) } label: {
            ZStack {
                Circle()
                    .fill(selected ? MonoTheme.primary.opacity(0.72) : MonoTheme.coral.opacity(0.12))
                Circle()
                    .stroke(selected ? Color.white.opacity(0.65) : MonoTheme.coral.opacity(0.32), lineWidth: 2)
                    .padding(5)
                Circle()
                    .fill(selected ? Color.white : MonoTheme.coral)
                    .frame(width: 17, height: 17)
            }
            .frame(width: 54, height: 54)
            .glassEffect(.regular.tint(selected ? MonoTheme.primary : MonoTheme.coral.opacity(0.25)).interactive(), in: .circle)
            .shadow(color: MonoTheme.primary.opacity(selected ? 0.24 : 0), radius: 8, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(MonoSpringPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func select(_ destination: Section) {
        if reduceMotion { section = destination }
        else { withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) { section = destination } }
    }
}
