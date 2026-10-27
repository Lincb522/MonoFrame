import SwiftUI

enum PearlRoute: Hashable {
    case settings, recordingSettings, permissions
    case legal(LegalDocument)
}

enum PearlTab: String, CaseIterable, Identifiable {
    case capture, library, studio, transcode
    var id: String { rawValue }
    var title: String {
        switch self { case .capture: "录制"; case .library: "素材"; case .studio: "剪辑"; case .transcode: "转码" }
    }
    var glyph: PearlGlyphName {
        switch self { case .capture: .record; case .library: .library; case .studio: .edit; case .transcode: .transcode }
    }
}

struct PearlRootView: View {
    @State private var selection: PearlTab = .capture
    @State private var path = NavigationPath()
    @State private var launchToken = 0
    @State private var audioPresented = false
    @State private var onboardingPresented = false
    @AppStorage("didCompleteWelcomeV1") private var welcomeComplete = false
    @AppStorage("didCompleteInitialPermissionSetupV2") private var permissionsComplete = false
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { container in
                let sidebar = !dynamicTypeSize.isAccessibilitySize && (container.size.width >= 900 || (sizeClass == .regular && container.size.width >= 740))
                HStack(spacing: 0) {
                    if sidebar {
                        PearlSidebar(selection: $selection).frame(width: 190)
                        Rectangle().fill(PearlColor.hairline(scheme)).frame(width: 1)
                    }
                    ZStack {
                        // Stable page identities preserve conversion and import state across tabs.
                        PearlCaptureView(launchToken: launchToken, openAudio: { audioPresented = true })
                            .modifier(PearlTabVisibility(visible: selection == .capture))
                        PearlLibraryView().modifier(PearlTabVisibility(visible: selection == .library))
                        PearlStudioView().modifier(PearlTabVisibility(visible: selection == .studio))
                        PearlTranscodeView().modifier(PearlTabVisibility(visible: selection == .transcode))
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if !sidebar { PearlTabBar(selection: $selection) }
                    }
                }
                .background(PearlBackdrop())
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Recording.self) { PearlVideoEditorView(recording: $0) }
            .navigationDestination(for: AudioRecording.self) { PearlAudioEditorView(recording: $0) }
            .navigationDestination(for: PearlMediaItem.self) { item in
                switch item {
                case .video(let recording): PearlVideoEditorView(recording: recording)
                case .audio(let recording): PearlAudioEditorView(recording: recording)
                }
            }
            .navigationDestination(for: PearlRoute.self) { route in
                switch route {
                case .settings: PearlSettingsView()
                case .recordingSettings: PearlRecordingSettingsView()
                case .permissions: PearlPermissionView()
                case .legal(let document): PearlLegalView(document: document)
                }
            }
        }
        .tint(PearlColor.accent(scheme))
        .fullScreenCover(isPresented: $audioPresented) { PearlAudioRecorderView() }
        .fullScreenCover(isPresented: $onboardingPresented) {
            PearlOnboardingView(needsWelcome: !welcomeComplete, completeWelcome: { welcomeComplete = true }) {
                welcomeComplete = true; permissionsComplete = true; onboardingPresented = false
            }
        }
        .onAppear(perform: initialRoute)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await library.reload() } }
        }
        .onOpenURL(perform: open)

    }

    private func initialRoute() {
        #if DEBUG
        if let section = ProcessInfo.processInfo.environment["MONO_SCREENSHOT_SECTION"] {
            if let tab = PearlTab(rawValue: section) { selection = tab }
            switch section {
            case "settings": path.append(PearlRoute.settings)
            case "recordingSettings": path.append(PearlRoute.recordingSettings)
            case "permissions": path.append(PearlRoute.permissions)
            case "legal": path.append(PearlRoute.legal(.userAgreement))
            case "audio": audioPresented = true
            case "onboarding": onboardingPresented = true
            default: break
            }
            return
        }
        #endif
        onboardingPresented = !welcomeComplete || !permissionsComplete
    }

    private func open(_ url: URL) {
        guard url.scheme == "mono" else { return }
        if let tab = PearlTab(rawValue: url.host ?? "") { path = NavigationPath(); selection = tab }
        switch url.host {
        case "capture": launchToken &+= 1
        case "audio": audioPresented = true
        case "settings": path.append(PearlRoute.settings)
        default: break
        }
    }
}

private struct PearlTabVisibility: ViewModifier {
    let visible: Bool
    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : 0).allowsHitTesting(visible).accessibilityHidden(!visible).zIndex(visible ? 1 : 0)
    }
}

private struct PearlTabBar: View {
    @Binding var selection: PearlTab
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 3) {
            PearlHairline()
            HStack(spacing: 0) {
                ForEach(PearlTab.allCases) { tab in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { selection = tab }
                    } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                Circle().fill(selection == tab ? PearlColor.ink(scheme) : .clear)
                                PearlGlyph(tab.glyph, size: 22)
                                    .foregroundStyle(selection == tab ? PearlColor.background(scheme) : PearlColor.secondary(scheme))
                            }.frame(width: 42, height: 42)
                            Text(tab.title).font(.caption.weight(selection == tab ? .bold : .medium))
                                .foregroundStyle(PearlColor.ink(scheme))
                        }.frame(maxWidth: .infinity).padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(PearlPressStyle())
                        .accessibilityLabel(tab.title).accessibilityAddTraits(selection == tab ? .isSelected : [])
                        .accessibilityIdentifier("pearl.tab.\(tab.rawValue)")
                }
            }
        }.padding(.horizontal, 20).background(PearlColor.background(scheme))
            .sensoryFeedback(.selection, trigger: selection)
            .accessibilityElement(children: .contain).accessibilityLabel("主导航")
    }
}

private struct PearlSidebar: View {
    @Binding var selection: PearlTab
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    Text("MonoFrame").font(.title2.weight(.bold)).padding(.vertical, 24)
                    ForEach(PearlTab.allCases) { tab in
                        Button { selection = tab } label: {
                            HStack(spacing: 14) {
                                PearlGlyph(tab.glyph, size: 22)
                                Text(tab.title).font(.headline)
                                Spacer(minLength: 0)
                                if selection == tab { Circle().fill(PearlColor.action(scheme)).frame(width: 8, height: 8) }
                            }.foregroundStyle(PearlColor.ink(scheme)).frame(minHeight: 48)
                        }.buttonStyle(PearlPressStyle()).accessibilityAddTraits(selection == tab ? .isSelected : [])
                            .accessibilityIdentifier("pearl.tab.\(tab.rawValue)")
                    }
                }
            }.scrollIndicators(.hidden)
            PearlSettingsLink()
        }.padding(.horizontal, 22).padding(.bottom, 20)
    }
}

struct PearlSettingsLink: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        NavigationLink(value: PearlRoute.settings) {
            PearlGlyph(.settings, size: 24).foregroundStyle(PearlColor.ink(scheme)).frame(width: 44, height: 44)
        }.buttonStyle(PearlPressStyle()).accessibilityLabel("设置").accessibilityIdentifier("pearl.openSettings")
    }
}
