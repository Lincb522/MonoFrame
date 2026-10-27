import AppIntents
import SwiftUI
import WidgetKit

@main
struct MonoControlsBundle: WidgetBundle {
    var body: some Widget {
        MonoScreenRecordingControl()
    }
}

struct MonoScreenRecordingControl: ControlWidget {
    static let kind = "com.linchengbo.mono.screenaudio.screen-control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenMonoCaptureIntent()) {
                PearlControlLabel("MonoFrame 录屏")
            }
        }
        .displayName("MonoFrame 录屏")
        .description("打开录屏控制")
    }
}

private struct PearlControlLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: 7) {
            PearlGlyph(.record, size: 18, weight: 1.8)
            Text(title)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

struct OpenMonoCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "打开 MonoFrame 录屏"
    static let description = IntentDescription("打开 MonoFrame 并显示系统录屏面板")
    static var openAppWhenRun: Bool { true }
    static var supportedModes: IntentModes { .foreground(.immediate) }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "mono://capture")!))
    }
}
