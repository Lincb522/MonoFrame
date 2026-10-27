import SwiftUI

@main
struct MonoApp: App {
    @StateObject private var library = RecordingLibrary()
    @StateObject private var cloudSync = CloudSyncService()
    @AppStorage(PearlAppearance.storageKey) private var appearance = PearlAppearance.defaultValue
    @AppStorage("iCloudSyncEnabledV1") private var iCloudSyncEnabled = false

    var body: some Scene {
        WindowGroup {
            PearlRootView()
                .environmentObject(library)
                .environmentObject(cloudSync)
                .preferredColorScheme(preferredScheme)
                .task {
                    if iCloudSyncEnabled { await cloudSync.sync() }
                    await library.reload()
                }
        }
    }

    private var preferredScheme: ColorScheme? {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["MONO_SCREENSHOT_STYLE"] {
        case "light": return .light
        case "dark": return .dark
        default: break
        }
        #endif
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
