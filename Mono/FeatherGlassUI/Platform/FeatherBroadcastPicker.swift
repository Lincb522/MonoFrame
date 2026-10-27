import OSLog
import ReplayKit
import SwiftUI
import UIKit

struct FeatherBroadcastPicker: UIViewRepresentable {
    let extensionBundleIdentifier: String
    var launchToken: Int = 0
    var accessibilityLabel: String
    var onFailure: ((String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> FeatherFullSizeBroadcastPicker {
        let picker = FeatherFullSizeBroadcastPicker()
        picker.preferredExtension = extensionBundleIdentifier
        picker.showsMicrophoneButton = true
        picker.backgroundColor = .clear
        picker.accessibilityLabel = accessibilityLabel
        picker.accessibilityIdentifier = "feather.capture.broadcastPicker"
        picker.onMissingButton = { message in onFailure?(message) }
        return picker
    }

    func updateUIView(_ picker: FeatherFullSizeBroadcastPicker, context: Context) {
        picker.preferredExtension = extensionBundleIdentifier
        picker.accessibilityLabel = accessibilityLabel
        picker.onMissingButton = { message in onFailure?(message) }
        picker.prepareButtonHierarchy()

        guard launchToken > 0, context.coordinator.lastLaunchToken != launchToken else { return }
        context.coordinator.lastLaunchToken = launchToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            picker.trigger()
        }
    }

    final class Coordinator {
        var lastLaunchToken = 0
    }
}

final class FeatherFullSizeBroadcastPicker: RPSystemBroadcastPickerView {
    private static let logger = Logger(subsystem: "com.linchengbo.mono.screenaudio", category: "broadcast-picker")
    var onMissingButton: ((String) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        prepareButtonHierarchy()
    }

    func prepareButtonHierarchy() {
        guard let button = firstButton(in: self) else { return }
        button.frame = bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        button.backgroundColor = .clear
        button.tintColor = .clear
        button.imageView?.alpha = 0.001
        button.accessibilityLabel = accessibilityLabel
    }

    func trigger() {
        guard let button = firstButton(in: self) else {
            let message = "无法打开系统录屏面板，请重试或从控制中心启动 MonoFrame 录屏。"
            Self.logger.error("RPSystemBroadcastPickerView has no UIButton in its hierarchy")
            onMissingButton?(message)
            return
        }
        button.sendActions(for: .touchUpInside)
    }

    private func firstButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton { return button }
        for child in view.subviews {
            if let button = firstButton(in: child) { return button }
        }
        return nil
    }
}
