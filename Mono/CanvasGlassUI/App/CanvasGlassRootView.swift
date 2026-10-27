import SwiftUI

struct CanvasGlassRootView: View {
    enum Tab: String, CaseIterable, Hashable, Identifiable {
        case capture
        case studio
        case library
        case transcode
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .capture: "录制"
            case .studio: "编辑"
            case .library: "作品"
            case .transcode: "转码"
            case .settings: "设置"
            }
        }

        var glyph: CanvasGlyphName {
            switch self {
            case .capture: .record
            case .studio: .edit
            case .library: .library
            case .transcode: .transcode
            case .settings: .settings
            }
        }
    }

    @State private var selectedTab: Tab
    @State private var captureLaunchToken = 0
    @State private var presentsAudioRecorder = false
    @State private var presentsOnboarding = false
    @AppStorage("didCompleteWelcomeV1") private var didCompleteWelcome = false
    @AppStorage("didCompleteInitialPermissionSetupV2") private var didCompletePermissions = false
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                CanvasBackdrop()
                screenshotOverride
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.995)))
                    .id(selectedTab)

            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsTabBar {
                    CanvasTabBar(selection: $selectedTab)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                        .ignoresSafeArea(.keyboard)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Recording.self) { recording in
                CanvasVideoEditorView(recording: recording)
            }
            .navigationDestination(for: AudioRecording.self) { recording in
                CanvasAudioEditorView(recording: recording)
            }
        }
        .tint(CanvasColor.accent(scheme))
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: selectedTab
        )
        .sensoryFeedback(.selection, trigger: selectedTab)
        .sheet(isPresented: $presentsAudioRecorder) {
            NavigationStack {
                CanvasAudioRecorderView()
            }
            .preferredColorScheme(nil)
        }
        .fullScreenCover(isPresented: $presentsOnboarding) {
            CanvasOnboardingFlow(
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
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["MONO_SCREENSHOT_SECTION"] == nil {
                presentsOnboarding = !didCompleteWelcome || !didCompletePermissions
            }
            #else
            presentsOnboarding = !didCompleteWelcome || !didCompletePermissions
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await library.reload() } }
        }
        .onOpenURL(perform: handleDeepLink)
        .accessibilityIdentifier("canvas.root")
    }

    @ViewBuilder private var screenshotOverride: some View {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["MONO_SCREENSHOT_SECTION"] {
        case "audio": CanvasAudioRecorderView()
        case "onboarding":
            CanvasOnboardingFlow(
                needsWelcome: true,
                needsPermissions: false,
                welcomeCompleted: {},
                completion: {}
            )
        case "permissions":
            CanvasOnboardingFlow(
                needsWelcome: false,
                needsPermissions: true,
                welcomeCompleted: {},
                completion: {}
            )
        default: selectedPage
        }
        #else
        selectedPage
        #endif
    }

    private var showsTabBar: Bool {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["MONO_SCREENSHOT_SECTION"] {
        case "audio", "onboarding", "permissions": false
        default: true
        }
        #else
        true
        #endif
    }

    @ViewBuilder private var selectedPage: some View {
        switch selectedTab {
        case .capture:
            CanvasCaptureView(
                launchToken: captureLaunchToken,
                openAudioRecorder: { presentsAudioRecorder = true }
            )
        case .studio:
            CanvasStudioView()
        case .library:
            CanvasLibraryView()
        case .transcode:
            CanvasTranscodeView()
        case .settings:
            CanvasSettingsView()
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
        case "audio": presentsAudioRecorder = true
        default: break
        }
    }
}

private struct CanvasTabBar: View {
    @Binding var selection: CanvasGlassRootView.Tab
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        CanvasGlassSurface(role: .tab, cornerRadius: 32) {
            HStack(spacing: 0) {
                ForEach(CanvasGlassRootView.Tab.allCases) { tab in
                    Button {
                        selection = tab
                    } label: {
                        VStack(spacing: 3) {
                            CanvasGlyph(tab.glyph, size: 23, weight: 1.72)
                            if !dynamicTypeSize.isAccessibilitySize {
                                Text(tab.title)
                                    .font(.caption2.weight(selection == tab ? .semibold : .medium))
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(
                            selection == tab
                                ? CanvasColor.accent(scheme)
                                : CanvasColor.secondary(scheme)
                        )
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CanvasPressStyle())
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                    .accessibilityIdentifier("canvas.tab.\(tab.rawValue)")
                }
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: 430)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 68 : 64)
        }
        .shadow(
            color: Color.black.opacity(scheme == .dark ? 0.26 : 0.09),
            radius: 6,
            y: 3
        )
        .frame(maxWidth: 430)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("主导航")
    }
}
