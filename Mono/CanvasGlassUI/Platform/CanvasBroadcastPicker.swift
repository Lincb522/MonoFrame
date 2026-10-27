import OSLog
import ReplayKit
import SwiftUI
import UIKit

/// A visible SwiftUI control backed by ReplayKit's system broadcast picker.
///
/// The supplied label is visual-only. The native ReplayKit button stays above it,
/// owns the complete 88×88 hit region, and remains the accessibility element.
struct CanvasBroadcastPicker<Label: View>: View {
    let launchToken: Int
    let accessibilityLabel: String
    let onResult: (Result<Void, CanvasBroadcastPickerError>) -> Void
    private let label: Label

    init(
        launchToken: Int = 0,
        accessibilityLabel: String,
        onResult: @escaping (Result<Void, CanvasBroadcastPickerError>) -> Void = { _ in },
        @ViewBuilder label: () -> Label
    ) {
        self.launchToken = launchToken
        self.accessibilityLabel = accessibilityLabel
        self.onResult = onResult
        self.label = label()
    }

    var body: some View {
        ZStack {
            label
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            CanvasBroadcastPickerRepresentable(
                launchToken: launchToken,
                accessibilityLabel: accessibilityLabel,
                onResult: onResult
            )
        }
        .frame(minWidth: 88, minHeight: 88)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }
}

enum CanvasBroadcastPickerError: LocalizedError, Equatable {
    case nativeButtonUnavailable

    var errorDescription: String? {
        switch self {
        case .nativeButtonUnavailable:
            return "无法打开系统录屏面板，请重试或从控制中心启动 MonoFrame 录屏。"
        }
    }
}

private struct CanvasBroadcastPickerRepresentable: UIViewRepresentable {
    private static let extensionBundleIdentifier = "com.linchengbo.mono.screenaudio.broadcast"

    let launchToken: Int
    let accessibilityLabel: String
    let onResult: (Result<Void, CanvasBroadcastPickerError>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> CanvasNativeBroadcastPicker {
        let picker = CanvasNativeBroadcastPicker()
        picker.preferredExtension = Self.extensionBundleIdentifier
        picker.showsMicrophoneButton = true
        picker.backgroundColor = .clear
        picker.accessibilityIdentifier = "canvas.capture.broadcastPicker"
        picker.canvasAccessibilityLabel = accessibilityLabel
        picker.onActivation = { onResult(.success(())) }
        picker.onFailure = { onResult(.failure($0)) }
        picker.prepareNativeButton()
        return picker
    }

    func updateUIView(_ picker: CanvasNativeBroadcastPicker, context: Context) {
        // Keep this assignment in updateUIView so a reused view can never retain
        // another extension selected by ReplayKit or a previous configuration.
        picker.preferredExtension = Self.extensionBundleIdentifier
        picker.canvasAccessibilityLabel = accessibilityLabel
        picker.onActivation = { onResult(.success(())) }
        picker.onFailure = { onResult(.failure($0)) }
        picker.prepareNativeButton()

        guard launchToken > 0, launchToken != context.coordinator.lastLaunchToken else {
            return
        }

        context.coordinator.lastLaunchToken = launchToken
        scheduleTrigger(on: picker, remainingAttempts: 3)
    }

    private func scheduleTrigger(
        on picker: CanvasNativeBroadcastPicker,
        remainingAttempts: Int
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            switch picker.trigger(reportMissingButton: remainingAttempts == 1) {
            case .success:
                break
            case .failure where remainingAttempts > 1:
                scheduleTrigger(on: picker, remainingAttempts: remainingAttempts - 1)
            case .failure:
                break
            }
        }
    }

    final class Coordinator {
        var lastLaunchToken = 0
    }
}

private final class CanvasNativeBroadcastPicker: RPSystemBroadcastPickerView {
    private static let logger = Logger(
        subsystem: "com.linchengbo.mono.screenaudio",
        category: "canvas-broadcast-picker"
    )

    var canvasAccessibilityLabel = "开始屏幕录制"
    var onActivation: (() -> Void)?
    var onFailure: ((CanvasBroadcastPickerError) -> Void)?

    private weak var observedButton: UIButton?

    override func layoutSubviews() {
        super.layoutSubviews()
        prepareNativeButton()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // The SwiftUI wrapper normally supplies 88×88. This expansion also keeps
        // the native control usable if a parent proposes a smaller UIKit bound.
        let minimumHitSize = CGSize(width: 88, height: 88)
        let dx = max(0, minimumHitSize.width - bounds.width) / 2
        let dy = max(0, minimumHitSize.height - bounds.height) / 2
        return bounds.insetBy(dx: -dx, dy: -dy).contains(point)
    }

    func prepareNativeButton() {
        guard let button = firstButton(in: self) else { return }

        button.frame = bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        button.isUserInteractionEnabled = true
        button.accessibilityLabel = canvasAccessibilityLabel
        button.accessibilityIdentifier = "canvas.capture.broadcastButton"

        // Hide ReplayKit's stock artwork without reducing view opacity or
        // disabling interaction. The custom SwiftUI label below remains visible.
        button.imageView?.isHidden = true
        button.backgroundColor = .clear

        if observedButton !== button {
            observedButton?.removeTarget(self, action: #selector(nativeButtonActivated), for: .touchUpInside)
            button.addTarget(self, action: #selector(nativeButtonActivated), for: .touchUpInside)
            observedButton = button
        }
    }

    @discardableResult
    func trigger(
        reportMissingButton: Bool = true
    ) -> Result<Void, CanvasBroadcastPickerError> {
        prepareNativeButton()

        guard let button = firstButton(in: self), button.isEnabled else {
            let error = CanvasBroadcastPickerError.nativeButtonUnavailable
            if reportMissingButton {
                #if DEBUG
                Self.logger.error("ReplayKit broadcast button is unavailable")
                #endif
                onFailure?(error)
            }
            return .failure(error)
        }

        button.sendActions(for: .touchUpInside)
        return .success(())
    }

    @objc private func nativeButtonActivated() {
        #if DEBUG
        Self.logger.debug("ReplayKit broadcast picker activation requested")
        #endif
        onActivation?()
    }

    private func firstButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton {
            return button
        }

        for child in view.subviews {
            if let button = firstButton(in: child) {
                return button
            }
        }

        return nil
    }
}
