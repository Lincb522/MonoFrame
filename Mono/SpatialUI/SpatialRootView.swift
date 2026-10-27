import SwiftUI

struct SpatialRootView: View {
    enum Section: String, CaseIterable {
        case capture = "录屏"
        case studio = "创作"
        case library = "作品"
        case transcode = "转码"
        case settings = "设置"

        var symbol: String {
            switch self {
            case .capture: "record.circle"
            case .studio: "scissors"
            case .library: "square.stack.3d.up"
            case .transcode: "arrow.triangle.2.circlepath"
            case .settings: "slider.horizontal.3"
            }
        }
    }

    @State private var section: Section
    @State private var broadcastLaunchToken = 0
    @Namespace private var dockSpace
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        #if DEBUG
        let requested = ProcessInfo.processInfo.environment["MONO_SCREENSHOT_SECTION"]
        let value: Section
        switch requested {
        case "studio": value = .studio
        case "library": value = .library
        case "transcode": value = .transcode
        case "settings": value = .settings
        default: value = .capture
        }
        _section = State(initialValue: value)
        #else
        _section = State(initialValue: .capture)
        #endif
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SpatialBackdrop()
                Group {
                    switch section {
                    case .capture: SpatialCaptureView(launchToken: broadcastLaunchToken)
                    case .studio: SpatialStudioView()
                    case .library: SpatialLibraryView()
                    case .transcode: SpatialTranscodeView()
                    case .settings: SpatialSettingsView()
                    }
                }
                .id(section)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if section == .library { libraryDock }
                    else if section != .capture && section != .studio { contextualDock }
                }
                .toolbar(.hidden, for: .navigationBar)
                .gesture(
                    DragGesture(minimumDistance: 42)
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let all = Section.allCases
                            guard let index = all.firstIndex(of: section) else { return }
                            let next = value.translation.width < 0 ? min(all.count - 1, index + 1) : max(0, index - 1)
                            if next != index { select(all[next]) }
                        }
                )
            }
            .navigationDestination(for: Recording.self) { EditorView(recording: $0) }
            .navigationDestination(for: AudioRecording.self) { AudioEditorView(recording: $0) }
        }
        .sensoryFeedback(.selection, trigger: section)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await library.reload() } }
        }
        .onOpenURL { url in
            guard url.scheme == "mono" else { return }
            switch url.host {
            case "capture": select(.capture); broadcastLaunchToken &+= 1
            case "studio": select(.studio)
            case "library": select(.library)
            case "transcode": select(.transcode)
            case "settings": select(.settings)
            default: break
            }
        }
    }

    private var libraryDock: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 14) {
                Button { select(.studio) } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .spatialGlass(Circle(), interactive: true)
                }
                Button { select(.capture) } label: {
                    ZStack {
                        Circle().fill(SpatialColor.sea.opacity(0.44)).frame(width: 58, height: 58)
                        Circle().fill(.white.opacity(0.72)).frame(width: 29, height: 29)
                        Circle().fill(SpatialColor.sea).frame(width: 15, height: 15)
                    }
                    .frame(width: 64, height: 64)
                    .spatialGlass(Circle(), tint: SpatialColor.sea.opacity(0.13), interactive: true)
                }
                Button { select(.settings) } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .spatialGlass(Circle(), interactive: true)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .spatialGlass(Capsule(), interactive: true)
        }
        .padding(.bottom, 5)
    }

    private var contextualDock: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(Section.allCases, id: \.self) { item in
                    Button { select(item) } label: {
                        HStack(spacing: section == item ? 6 : 0) {
                            Image(systemName: item.symbol)
                                .font(.system(size: item == .capture ? 20 : 17, weight: .semibold))
                            if section == item {
                                Text(item.rawValue)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                            }
                        }
                        .foregroundStyle(section == item ? .white : .primary)
                        .frame(minWidth: section == item ? 67 : 41, minHeight: 45)
                        .spatialGlass(
                            Capsule(),
                            tint: section == item ? SpatialColor.seaDeep : nil,
                            interactive: true
                        )
                        .glassEffectID(item, in: dockSpace)
                    }
                    .buttonStyle(SpatialGlassButtonStyle())
                }
            }
            .padding(7)
            .spatialGlass(Capsule(), interactive: true)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 5)
    }

    private func select(_ target: Section) {
        if reduceMotion { section = target }
        else { withAnimation(.spring(response: 0.40, dampingFraction: 1)) { section = target } }
    }
}
