import SwiftUI

struct FeatherGlassRootView: View {
    enum Tab: String, CaseIterable, Hashable {
        case capture
        case studio
        case library
        case transcode
        case settings

        var title: String {
            switch self {
            case .capture: "录制"
            case .studio: "编辑"
            case .library: "作品"
            case .transcode: "转码"
            case .settings: "设置"
            }
        }

        var asset: String {
            switch self {
            case .capture: "mono-record"
            case .studio: "mono-scissors"
            case .library: "mono-library"
            case .transcode: "mono-transcode"
            case .settings: "mono-settings"
            }
        }
    }

    @State private var selectedTab: Tab
    @State private var captureLaunchToken = 0
    @State private var presentsOnboarding = false
    @AppStorage("didCompleteWelcomeV1") private var didCompleteWelcome = false
    @AppStorage("didCompleteInitialPermissionSetupV2") private var didCompletePermissions = false
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme

    init() {
        #if DEBUG
        let section = ProcessInfo.processInfo.environment["MONO_SCREENSHOT_SECTION"]
        let initial: Tab
        switch section {
        case "studio": initial = .studio
        case "library": initial = .library
        case "transcode": initial = .transcode
        case "settings": initial = .settings
        default: initial = .capture
        }
        _selectedTab = State(initialValue: initial)
        #else
        _selectedTab = State(initialValue: .capture)
        #endif
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FeatherBackdrop()
                screenshotOverride
            }
            .navigationDestination(for: Recording.self) { recording in
                FeatherVideoEditorView(recording: recording)
            }
            .navigationDestination(for: AudioRecording.self) { recording in
                FeatherAudioEditorView(recording: recording)
            }
        }
        .tint(FeatherColor.accent(scheme))
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["MONO_SCREENSHOT_SECTION"] == nil {
                presentsOnboarding = !didCompleteWelcome || !didCompletePermissions
            }
            #else
            presentsOnboarding = !didCompleteWelcome || !didCompletePermissions
            #endif
        }
        .fullScreenCover(isPresented: $presentsOnboarding) {
            FeatherOnboardingFlow(
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await library.reload() } }
        }
        .onOpenURL(perform: handleDeepLink)
    }

    @ViewBuilder private var screenshotOverride: some View {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["MONO_SCREENSHOT_SECTION"] {
        case "audio": FeatherAudioRecorderView()
        case "onboarding": FeatherOnboardingFlow(needsWelcome: true, needsPermissions: false, welcomeCompleted: {}, completion: {})
        case "permissions": FeatherOnboardingFlow(needsWelcome: false, needsPermissions: true, welcomeCompleted: {}, completion: {})
        default: tabs
        }
        #else
        tabs
        #endif
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            FeatherCaptureView(launchToken: captureLaunchToken)
                .tag(Tab.capture)
                .tabItem { tabLabel(.capture) }

            FeatherStudioView()
                .tag(Tab.studio)
                .tabItem { tabLabel(.studio) }

            FeatherLibraryView()
                .tag(Tab.library)
                .tabItem { tabLabel(.library) }

            FeatherTranscodeView()
                .tag(Tab.transcode)
                .tabItem { tabLabel(.transcode) }

            FeatherSettingsView()
                .tag(Tab.settings)
                .tabItem { tabLabel(.settings) }
        }
        .toolbarBackground(.automatic, for: .tabBar)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }

    private func tabLabel(_ tab: Tab) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            Image(tab.asset).renderingMode(.template)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "mono" else { return }
        switch url.host {
        case "capture":
            selectedTab = .capture
            captureLaunchToken &+= 1
        case "studio": selectedTab = .studio
        case "library": selectedTab = .library
        case "transcode": selectedTab = .transcode
        case "settings": selectedTab = .settings
        default: break
        }
    }
}
