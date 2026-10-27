import Foundation

enum ScreenRecordingPreferenceKey {
    static let resolution = "screenResolution"
    static let frameRate = "screenFrameRate"
    static let orientation = "screenOrientation"
    static let bitratePreset = "screenBitratePreset"
    static let isActive = "screenRecordingIsActive"
    static let startedAt = "screenRecordingStartedAt"
    static let heartbeatAt = "screenRecordingHeartbeatAt"
    static let lastCompletedAt = "screenRecordingLastCompletedAt"
    static let lastError = "screenRecordingLastError"
    static let lastErrorAt = "screenRecordingLastErrorAt"
}

struct ScreenRecordingSnapshot {
    let isActive: Bool
    let startedAt: Date?
    let lastCompletedAt: Date?

    func elapsed(at date: Date) -> TimeInterval {
        guard isActive, let startedAt else { return 0 }
        return max(0, date.timeIntervalSince(startedAt))
    }

    static func read(
        at date: Date = Date(),
        defaults: UserDefaults? = UserDefaults(suiteName: "group.com.linchengbo.mono.screenaudio")
    ) -> ScreenRecordingSnapshot {
        guard let defaults else {
            return ScreenRecordingSnapshot(isActive: false, startedAt: nil, lastCompletedAt: nil)
        }
        let heartbeat = defaults.double(forKey: ScreenRecordingPreferenceKey.heartbeatAt)
        let heartbeatIsFresh = heartbeat > 0 && date.timeIntervalSince1970 - heartbeat < 6
        let active = defaults.bool(forKey: ScreenRecordingPreferenceKey.isActive) && heartbeatIsFresh
        let started = defaults.double(forKey: ScreenRecordingPreferenceKey.startedAt)
        let completed = defaults.double(forKey: ScreenRecordingPreferenceKey.lastCompletedAt)
        return ScreenRecordingSnapshot(
            isActive: active,
            startedAt: started > 0 ? Date(timeIntervalSince1970: started) : nil,
            lastCompletedAt: completed > 0 ? Date(timeIntervalSince1970: completed) : nil
        )
    }
}

enum ScreenResolutionPreset: String, CaseIterable, Identifiable {
    case native
    case p240
    case p360
    case p480
    case p720
    case p1080
    case p2K

    var id: String { rawValue }

    var title: String {
        switch self {
        case .native: "设备屏幕"
        case .p240: "240p"
        case .p360: "360p"
        case .p480: "480p"
        case .p720: "720p"
        case .p1080: "1080p"
        case .p2K: "2K"
        }
    }

    private var maximumLongEdge: Int? {
        switch self {
        case .native: nil
        case .p240: 426
        case .p360: 640
        case .p480: 854
        case .p720: 1_280
        case .p1080: 1_920
        case .p2K: 2_560
        }
    }

    func dimensions(sourceWidth: Int, sourceHeight: Int) -> (width: Int, height: Int) {
        let sourceWidth = max(2, sourceWidth)
        let sourceHeight = max(2, sourceHeight)
        guard let maximumLongEdge else {
            return (Self.even(sourceWidth), Self.even(sourceHeight))
        }
        let scale = Double(maximumLongEdge) / Double(max(sourceWidth, sourceHeight))
        return (
            Self.even(Int((Double(sourceWidth) * scale).rounded())),
            Self.even(Int((Double(sourceHeight) * scale).rounded()))
        )
    }

    private static func even(_ value: Int) -> Int {
        max(2, value - value % 2)
    }
}

enum ScreenFrameRateLimit {
    static let minimum = 15
    static let maximum = 60

    static func clamp(_ value: Int) -> Int {
        min(maximum, max(minimum, value))
    }
}

enum ScreenOrientationPreset: String, CaseIterable, Identifiable {
    case automatic
    case portrait
    case landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "自动"
        case .portrait: "竖屏"
        case .landscape: "横屏"
        }
    }
}

enum ScreenBitratePreset: String, CaseIterable, Identifiable {
    case highest
    case mbps12
    case mbps25
    case mbps50
    case mbps80
    case mbps120

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highest: "最高"
        case .mbps12: "12M"
        case .mbps25: "25M"
        case .mbps50: "50M"
        case .mbps80: "80M"
        case .mbps120: "120M"
        }
    }

    func bitsPerSecond(width: Int, height: Int, frameRate: Int, isHEVC: Bool) -> Int {
        let fixedMbps: Int?
        switch self {
        case .highest: fixedMbps = nil
        case .mbps12: fixedMbps = 12
        case .mbps25: fixedMbps = 25
        case .mbps50: fixedMbps = 50
        case .mbps80: fixedMbps = 80
        case .mbps120: fixedMbps = 120
        }
        if let fixedMbps { return fixedMbps * 1_000_000 }

        let bitsPerPixel = isHEVC ? 0.42 : 0.58
        let calculated = Double(width * height * frameRate) * bitsPerPixel
        return min(120_000_000, max(12_000_000, Int(calculated.rounded())))
    }
}
