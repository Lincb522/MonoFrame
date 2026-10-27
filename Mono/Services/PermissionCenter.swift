import AVFoundation
import Photos

@MainActor
final class PermissionCenter: ObservableObject {
    enum AccessState: Equatable {
        case notDetermined
        case allowed
        case limited
        case denied

        var title: String {
            switch self {
            case .notDetermined: "未开启"
            case .allowed: "已开启"
            case .limited: "有限访问"
            case .denied: "已关闭"
            }
        }

        var symbol: String {
            switch self {
            case .notDetermined: "circle"
            case .allowed: "checkmark.circle.fill"
            case .limited: "exclamationmark.circle.fill"
            case .denied: "xmark.circle.fill"
            }
        }
    }

    @Published private(set) var photo: AccessState = .notDetermined
    @Published private(set) var microphone: AccessState = .notDetermined
    @Published private(set) var isRequesting = false

    var hasDeniedAccess: Bool {
        photo == .denied || photo == .limited || microphone == .denied
    }

    var hasUndeterminedAccess: Bool {
        photo == .notDetermined || microphone == .notDetermined
    }

    init() {
        refresh()
    }

    func refresh() {
        photo = Self.photoState(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        microphone = Self.microphoneState(AVAudioApplication.shared.recordPermission)
    }

    func requestAccess() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }

        if photo == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            refresh()
        }
        if microphone == .notDetermined {
            _ = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        refresh()
    }

    private static func photoState(_ status: PHAuthorizationStatus) -> AccessState {
        switch status {
        case .authorized: .allowed
        case .limited: .limited
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    private static func microphoneState(_ status: AVAudioApplication.recordPermission) -> AccessState {
        switch status {
        case .granted: .allowed
        case .denied: .denied
        case .undetermined: .notDetermined
        @unknown default: .denied
        }
    }
}
