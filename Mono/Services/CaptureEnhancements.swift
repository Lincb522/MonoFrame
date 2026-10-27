import AVFoundation
import Foundation
import Speech
import UserNotifications

struct LiveCaptionSegment: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let start: TimeInterval
    let duration: TimeInterval

    init(id: UUID = UUID(), text: String, start: TimeInterval, duration: TimeInterval) {
        self.id = id
        self.text = text
        self.start = start
        self.duration = duration
    }
}

@MainActor
final class LiveCaptionService: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var segments: [LiveCaptionSegment] = []
    @Published private(set) var savedTranscriptURL: URL?

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var sessionStartedAt = Date()

    var isListening: Bool { state == .listening }
    var latestLine: String {
        let value = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 54 else { return value }
        return "…" + value.suffix(54)
    }

    func start(locale: Locale = Locale(identifier: "zh-CN")) async {
        guard !isListening else { return }
        state = .requestingPermission
        let authorization = await requestAuthorization()
        guard authorization == .authorized else {
            state = .failed(authorization == .denied ? "请在系统设置中允许语音识别" : "语音识别暂不可用")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            state = .failed("当前语言的语音识别暂不可用")
            return
        }

        do {
            try stopAudioEngine()
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request
            transcript = ""
            segments = []
            savedTranscriptURL = nil
            sessionStartedAt = .now

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw LiveCaptionError.microphoneUnavailable
            }
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        self.apply(result)
                        if result.isFinal { self.finishRecognition(save: true) }
                    } else if let error, self.isListening {
                        self.finishRecognition(save: true)
                        self.state = .failed(error.localizedDescription)
                    }
                }
            }
            state = .listening
        } catch {
            finishRecognition(save: false)
            state = .failed(error.localizedDescription)
        }
    }

    func stop(save: Bool = true) {
        finishRecognition(save: save)
        state = .idle
    }

    private func apply(_ result: SFSpeechRecognitionResult) {
        transcript = result.bestTranscription.formattedString
        segments = result.bestTranscription.segments.map {
            LiveCaptionSegment(text: $0.substring, start: $0.timestamp, duration: max(0.12, $0.duration))
        }
    }

    private func finishRecognition(save: Bool) {
        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        try? stopAudioEngine()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if save, !segments.isEmpty { savedTranscriptURL = try? persistTranscript() }
    }

    private func stopAudioEngine() throws {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func persistTranscript() throws -> URL {
        try SharedStorage.prepare()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = SharedStorage.lyricDirectory
            .appendingPathComponent("LiveCaption-\(formatter.string(from: sessionStartedAt)).srt")
        let body = segments.enumerated().map { index, segment in
            "\(index + 1)\n\(Self.srtTime(segment.start)) --> \(Self.srtTime(segment.start + segment.duration))\n\(segment.text)\n"
        }.joined(separator: "\n")
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func srtTime(_ seconds: TimeInterval) -> String {
        let milliseconds = max(0, Int((seconds * 1_000).rounded()))
        return String(
            format: "%02d:%02d:%02d,%03d",
            milliseconds / 3_600_000,
            milliseconds / 60_000 % 60,
            milliseconds / 1_000 % 60,
            milliseconds % 1_000
        )
    }

    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
}

private enum LiveCaptionError: LocalizedError {
    case microphoneUnavailable
    var errorDescription: String? { "麦克风输入不可用" }
}

@MainActor
final class CaptureScheduler: ObservableObject {
    @Published private(set) var scheduledDate: Date?
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var fireToken = 0
    @Published private(set) var authorizationDenied = false

    private var ticker: Task<Void, Never>?
    private let defaultsKey = "scheduledCaptureDateV1"
    private let notificationID = "monoframe.scheduled-capture"

    init() {
        if let date = UserDefaults.standard.object(forKey: defaultsKey) as? Date, date > .now {
            scheduledDate = date
            remaining = date.timeIntervalSinceNow
            startTicker()
        }
    }

    var isArmed: Bool { scheduledDate != nil }
    var countdownText: String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func arm(after interval: TimeInterval) async {
        cancel(removeNotification: true)
        let date = Date().addingTimeInterval(max(3, interval))
        scheduledDate = date
        remaining = date.timeIntervalSinceNow
        UserDefaults.standard.set(date, forKey: defaultsKey)

        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        authorizationDenied = !granted
        if granted {
            let content = UNMutableNotificationContent()
            content.title = "定时录制已就绪"
            content.body = "返回 MonoFrame 确认系统广播即可开始。"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(3, interval), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger))
        }
        startTicker()
    }

    func cancel(removeNotification: Bool = true) {
        ticker?.cancel()
        ticker = nil
        scheduledDate = nil
        remaining = 0
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        if removeNotification {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let date = self.scheduledDate else { return }
                self.remaining = max(0, date.timeIntervalSinceNow)
                if self.remaining <= 0.05 {
                    self.fireToken &+= 1
                    self.cancel(removeNotification: false)
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}

@MainActor
final class CloudSyncService: ObservableObject {
    enum State: Equatable {
        case idle
        case syncing
        case completed(uploaded: Int, downloaded: Int)
        case unavailable
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastSyncDate: Date?

    var statusText: String {
        switch state {
        case .idle: return "等待同步"
        case .syncing: return "正在合并本地与 iCloud"
        case let .completed(uploaded, downloaded): return "上传 \(uploaded) · 下载 \(downloaded)"
        case .unavailable: return "iCloud Drive 不可用"
        case let .failed(message): return message
        }
    }

    func sync() async {
        guard state != .syncing else { return }
        state = .syncing
        do {
            try SharedStorage.prepare()
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
                state = .unavailable
                return
            }
            let result = try await Task.detached(priority: .utility) {
                try Self.performSync(container: container)
            }.value
            lastSyncDate = .now
            state = .completed(uploaded: result.uploaded, downloaded: result.downloaded)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    nonisolated private static func performSync(container: URL) throws -> (uploaded: Int, downloaded: Int) {
        let root = container.appendingPathComponent("Documents/MonoFrame", isDirectory: true)
        let pairs: [(String, URL)] = [
            ("Recordings", SharedStorage.localDirectory),
            ("Audio", SharedStorage.audioDirectory),
            ("VideoProjects", SharedStorage.projectDirectory),
            ("Lyrics", SharedStorage.lyricDirectory)
        ]
        var uploaded = 0
        var downloaded = 0
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)

        for (name, local) in pairs {
            let cloud = root.appendingPathComponent(name, isDirectory: true)
            try manager.createDirectory(at: local, withIntermediateDirectories: true)
            try manager.createDirectory(at: cloud, withIntermediateDirectories: true)
            let localFiles = regularFiles(in: local)
            let cloudFiles = regularFiles(in: cloud)
            let names = Set(localFiles.keys).union(cloudFiles.keys)
            for relativePath in names {
                let localURL = local.appendingPathComponent(relativePath)
                let cloudURL = cloud.appendingPathComponent(relativePath)
                switch (localFiles[relativePath], cloudFiles[relativePath]) {
                case let (localDate?, cloudDate?):
                    if localDate > cloudDate.addingTimeInterval(1) {
                        try replaceItem(at: cloudURL, with: localURL)
                        uploaded += 1
                    } else if cloudDate > localDate.addingTimeInterval(1) {
                        try? manager.startDownloadingUbiquitousItem(at: cloudURL)
                        try replaceItem(at: localURL, with: cloudURL)
                        downloaded += 1
                    }
                case (.some, .none):
                    try replaceItem(at: cloudURL, with: localURL)
                    uploaded += 1
                case (.none, .some):
                    try? manager.startDownloadingUbiquitousItem(at: cloudURL)
                    try replaceItem(at: localURL, with: cloudURL)
                    downloaded += 1
                default: break
                }
            }
        }
        return (uploaded, downloaded)
    }

    nonisolated private static func regularFiles(in directory: URL) -> [String: Date] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }
        var result: [String: Date] = [:]
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }
            let prefix = directory.standardizedFileURL.path + "/"
            let relative = url.standardizedFileURL.path.replacingOccurrences(of: prefix, with: "")
            result[relative] = values?.contentModificationDate ?? .distantPast
        }
        return result
    }

    nonisolated private static func replaceItem(at destination: URL, with source: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".sync-\(UUID().uuidString)")
        try manager.copyItem(at: source, to: temporary)
        if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
        try manager.moveItem(at: temporary, to: destination)
    }
}
