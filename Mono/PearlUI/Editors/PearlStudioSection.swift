import SwiftUI

/// Studio-specific density; the audio editor retains its original shared section styling.
struct PearlStudioSection<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(detail).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(.bottom, 8)
            content()
        }
    }
}
struct StudioEditingGestureKey: EnvironmentKey { static let defaultValue: ((Bool) -> Void)? = nil }
extension EnvironmentValues {
    var studioEditingGesture: ((Bool) -> Void)? {
        get { self[StudioEditingGestureKey.self] }
        set { self[StudioEditingGestureKey.self] = newValue }
    }
}
