import OSLog
import ReplayKit
import SwiftUI

enum PearlBroadcastError: LocalizedError {
    case unavailable
    var errorDescription: String? { "无法打开系统录屏面板，请重试或从控制中心选择 MonoFrame。" }
}

struct PearlBroadcastPicker<Label: View>: View {
    let launchToken: Int
    let accessibilityLabel: String
    let onResult: (Result<Void, PearlBroadcastError>) -> Void
    @ViewBuilder let label: () -> Label
    var body: some View {
        ZStack {
            label().allowsHitTesting(false).accessibilityHidden(true)
            PearlBroadcastControl(token: launchToken, label: accessibilityLabel, result: onResult)
        }.frame(minHeight: 44).contentShape(Rectangle())
    }
}

private struct PearlBroadcastControl: UIViewRepresentable {
    let token: Int
    let label: String
    let result: (Result<Void, PearlBroadcastError>) -> Void
    func makeUIView(context: Context) -> PearlNativeBroadcastPicker {
        let view = PearlNativeBroadcastPicker()
        view.preferredExtension = "com.linchengbo.mono.screenaudio.broadcast"
        view.showsMicrophoneButton = true
        view.backgroundColor = .clear
        return view
    }
    func updateUIView(_ view: PearlNativeBroadcastPicker, context: Context) {
        view.controlLabel = label
        view.result = result
        view.request(token: token)
        view.setNeedsLayout()
    }
}

private final class PearlNativeBroadcastPicker: RPSystemBroadcastPickerView {
    private static let logger = Logger(subsystem: "com.linchengbo.mono.screenaudio", category: "broadcast-control")
    var controlLabel = "打开系统录屏面板"
    var result: ((Result<Void, PearlBroadcastError>) -> Void)?
    private var requestedToken = 0
    private var deliveredToken = 0
    private weak var nativeButton: UIButton?
    private var delivery: Task<Void, Never>?

    override func layoutSubviews() {
        super.layoutSubviews()
        prepare()
        deliverIfReady()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { delivery?.cancel(); delivery = nil }
        else { setNeedsLayout() }
    }
    func request(token: Int) { requestedToken = token }

    private func prepare() {
        guard let button = findButton(in: self) else { return }
        button.frame = bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        button.imageView?.isHidden = true
        button.backgroundColor = .clear
        button.accessibilityLabel = controlLabel
        button.accessibilityIdentifier = "pearl.capture.broadcastButton"
        if nativeButton !== button {
            nativeButton?.removeTarget(self, action: #selector(activated), for: .touchUpInside)
            button.addTarget(self, action: #selector(activated), for: .touchUpInside)
            nativeButton = button
        }
    }

    private func deliverIfReady() {
        guard window != nil, bounds.width > 0, requestedToken > deliveredToken, delivery == nil else { return }
        let token = requestedToken
        // UIKit has mounted the real ReplayKit control; no timed retries or synthetic overlay taps.
        delivery = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            defer { delivery = nil }
            guard window != nil else { return }
            deliveredToken = token
            prepare()
            guard let button = nativeButton, button.isEnabled else {
                Self.logger.error("System broadcast control is unavailable")
                result?(.failure(.unavailable)); return
            }
            button.sendActions(for: .touchUpInside)
        }
    }

    @objc private func activated() {
        Self.logger.debug("System broadcast panel requested")
        result?(.success(()))
    }
    private func findButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton { return button }
        for child in view.subviews { if let button = findButton(in: child) { return button } }
        return nil
    }
}
