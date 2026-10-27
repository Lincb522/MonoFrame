import AVFoundation
import CoreFoundation
import FFmpegSwiftSDK
import Foundation

enum AudioCaptureMode: String, CaseIterable, Identifiable {
    case automatic = "自动"
    case speaker = "扬声器"
    case headphones = "耳机"

    var id: String { rawValue }
}

enum SpeakerProcessingStrength: String, CaseIterable, Identifiable {
    case natural = "自然"
    case balanced = "均衡"
    case strong = "强"

    var id: String { rawValue }
}

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: TimeInterval?
    let text: String
}

enum LyricDocumentCodec {
    static let supportedFileExtensions = ["lrc", "txt", "qlrc", "mlrc", "qrc"]

    static func normalizedFileExtension(for url: URL) -> String {
        let value = url.pathExtension.lowercased()
        return supportedFileExtensions.contains(value) ? value : "txt"
    }

    static func decode(_ data: Data) -> String? {
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, gb18030] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return nil
    }

    static func parse(_ text: String) -> [LyricLine] {
        let rawLines = unpackedText(from: text).components(separatedBy: .newlines)
        let timestampPattern = #"\[(\d{1,3}):(\d{1,2})(?:[\.:](\d{1,3}))?\]"#
        let millisecondPattern = #"^\[(\d+)(?:,(\d+))?\](.*)$"#
        let wordTimestampPattern = #"(?:\(\d+,\d+(?:,\d+)?\)|<\d{1,3}:\d{1,2}(?:[\.:]\d{1,3})?>)"#
        guard let expression = try? NSRegularExpression(pattern: timestampPattern),
              let millisecondExpression = try? NSRegularExpression(pattern: millisecondPattern),
              let wordTimestampExpression = try? NSRegularExpression(pattern: wordTimestampPattern) else { return [] }
        var timedLines: [(time: TimeInterval, text: String)] = []
        var plainLines: [String] = []
        let offset = lyricOffset(in: rawLines)

        for rawLine in rawLines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.lowercased().hasPrefix("[offset:") { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = expression.matches(in: line, range: range)
            if matches.isEmpty {
                if let match = millisecondExpression.firstMatch(in: line, range: range),
                   let startRange = Range(match.range(at: 1), in: line),
                   let contentRange = Range(match.range(at: 3), in: line),
                   let startMilliseconds = Double(line[startRange]) {
                    let rawContent = String(line[contentRange])
                    let contentRange = NSRange(rawContent.startIndex..<rawContent.endIndex, in: rawContent)
                    let content = wordTimestampExpression
                        .stringByReplacingMatches(in: rawContent, range: contentRange, withTemplate: "")
                        .trimmingCharacters(in: .whitespaces)
                    if !content.isEmpty {
                        timedLines.append((max(0, startMilliseconds / 1_000 + offset), content))
                    }
                    continue
                }
                if !line.hasPrefix("[") { plainLines.append(line) }
                continue
            }
            let withoutLineTimestamps = expression.stringByReplacingMatches(in: line, range: range, withTemplate: "")
            let contentRange = NSRange(
                withoutLineTimestamps.startIndex..<withoutLineTimestamps.endIndex,
                in: withoutLineTimestamps
            )
            let content = wordTimestampExpression
                .stringByReplacingMatches(in: withoutLineTimestamps, range: contentRange, withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { continue }
            for match in matches {
                guard let minuteRange = Range(match.range(at: 1), in: line),
                      let secondRange = Range(match.range(at: 2), in: line),
                      let minutes = Double(line[minuteRange]),
                      let seconds = Double(line[secondRange]) else { continue }
                var fraction: Double = 0
                if match.range(at: 3).location != NSNotFound,
                   let fractionRange = Range(match.range(at: 3), in: line) {
                    let digits = String(line[fractionRange])
                    fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
                }
                timedLines.append((max(0, minutes * 60 + seconds + fraction + offset), content))
            }
        }

        if !timedLines.isEmpty {
            return timedLines.sorted { $0.time < $1.time }.enumerated().map {
                LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text)
            }
        }
        return plainLines.enumerated().map { LyricLine(id: $0.offset, time: nil, text: $0.element) }
    }

    private static func lyricOffset(in lines: [String]) -> TimeInterval {
        for line in lines {
            let lowercased = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard lowercased.hasPrefix("[offset:"),
                  let value = lowercased.dropFirst(8).split(separator: "]").first.flatMap({ Double($0) }) else {
                continue
            }
            return value / 1_000
        }
        return 0
    }

    private static func unpackedText(from text: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"LyricContent\s*=\s*([\"'])([\s\S]*?)\1"#,
            options: [.caseInsensitive]
        ) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range),
              let contentRange = Range(match.range(at: 2), in: text) else { return text }
        return decodeXMLEntities(String(text[contentRange]))
    }

    private static func decodeXMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&#13;", with: "\r")
            .replacingOccurrences(of: "&#10;", with: "\n")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    static func renderLRC(_ lines: [LyricLine], offset: TimeInterval = 0) -> String {
        lines.compactMap { line in
            guard let time = line.time else { return line.text }
            let adjusted = max(0, time - offset)
            let minutes = Int(adjusted) / 60
            let seconds = adjusted - Double(minutes * 60)
            return String(format: "[%02d:%05.2f]%@", minutes, seconds, line.text)
        }
        .joined(separator: "\n") + "\n"
    }
}

@MainActor
final class AudioRecordingService: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case paused
        case processing
        case mixing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var levels: [Float] = Array(repeating: 0.08, count: 48)
    @Published private(set) var accompanimentURL: URL?
    @Published private(set) var accompanimentName: String?
    @Published private(set) var lyricsURL: URL?
    @Published private(set) var lyricsName: String?
    @Published private(set) var lyricLines: [LyricLine] = []
    @Published var lyricOffset: TimeInterval = 0
    @Published var accompanimentVolume: Double = 0.68 {
        didSet {
            accompanimentPlayer?.volume = Float(accompanimentVolume)
            engineAccompanimentPlayer?.volume = Float(accompanimentVolume)
        }
    }
    @Published var vocalVolume: Double = 1
    @Published var vocalSyncAdjustmentMilliseconds: Double = UserDefaults(
        suiteName: SharedStorage.appGroup
    )?.double(forKey: "vocalSyncAdjustmentMilliseconds") ?? 0 {
        didSet {
            UserDefaults(suiteName: SharedStorage.appGroup)?.set(
                vocalSyncAdjustmentMilliseconds,
                forKey: "vocalSyncAdjustmentMilliseconds"
            )
        }
    }
    @Published private(set) var automaticSyncCompensationMilliseconds: Double = 0
    @Published var captureMode: AudioCaptureMode = .automatic
    @Published var speakerProcessingStrength: SpeakerProcessingStrength = .balanced
    @Published private(set) var activeCaptureMode: AudioCaptureMode?

    private var recorder: AVAudioRecorder?
    private var accompanimentPlayer: AVAudioPlayer?
    private var audioEngine: AVAudioEngine?
    private var engineAccompanimentPlayer: AVAudioPlayerNode?
    private var engineAccompanimentFile: AVAudioFile?
    private var engineRecordingFile: AVAudioFile?
    private var engineOutputURL: URL?
    private var engineLevel: Float = 0.04
    private var activeAccompanimentURL: URL?
    private var activeLyricsURL: URL?
    private var activeVocalAlignmentSeconds: TimeInterval = 0
    private var meterTask: Task<Void, Never>?
    private var startedAt: Date?
    private var elapsedBeforePause: TimeInterval = 0
    private let audioTranscoder = FFmpegAudioTranscoder()

    var isActive: Bool { recorder != nil || audioEngine != nil }
    var isBusy: Bool { isActive || state == .processing || state == .mixing }
    var hasAccompaniment: Bool { accompanimentURL != nil }
    var hasLyrics: Bool { !lyricLines.isEmpty }

    var currentLyricIndex: Int? {
        let timed = lyricLines.indices.filter { lyricLines[$0].time != nil }
        guard !timed.isEmpty else { return nil }
        return timed.last { (lyricLines[$0].time ?? .greatestFiniteMagnitude) <= elapsed + lyricOffset }
    }

    var currentLyric: LyricLine? {
        currentLyricIndex.map { lyricLines[$0] }
    }

    var nextLyric: LyricLine? {
        guard let currentLyricIndex else {
            return lyricLines.first { $0.time != nil }
        }
        return lyricLines.dropFirst(currentLyricIndex + 1).first { $0.time != nil }
    }

    func importAccompaniment(from sourceURL: URL) throws {
        guard !isBusy else { return }
        try SharedStorage.prepare()

        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let fileName = sourceURL.lastPathComponent.isEmpty ? "Accompaniment.m4a" : sourceURL.lastPathComponent
        let destination = SharedStorage.accompanimentDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(fileName)")
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        if let accompanimentURL { try? FileManager.default.removeItem(at: accompanimentURL) }
        accompanimentURL = destination
        accompanimentName = fileName
        if case .failed = state { state = .idle }
    }

    func clearAccompaniment() {
        guard !isBusy else { return }
        if let accompanimentURL { try? FileManager.default.removeItem(at: accompanimentURL) }
        accompanimentURL = nil
        accompanimentName = nil
    }

    func importLyrics(from sourceURL: URL) throws {
        guard !isBusy else { return }
        try SharedStorage.prepare()

        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: sourceURL)
        guard let text = LyricDocumentCodec.decode(data), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AudioRecordingError.invalidLyrics
        }
        let lines = LyricDocumentCodec.parse(text)
        guard !lines.isEmpty else { throw AudioRecordingError.invalidLyrics }

        let sourceExtension = LyricDocumentCodec.normalizedFileExtension(for: sourceURL)
        let fileName = sourceURL.lastPathComponent.isEmpty ? "Lyrics.\(sourceExtension)" : sourceURL.lastPathComponent
        let destination = SharedStorage.lyricDirectory
            .appendingPathComponent("\(UUID().uuidString)-Lyrics.\(sourceExtension)")
        try data.write(to: destination, options: .atomic)
        if let lyricsURL { try? FileManager.default.removeItem(at: lyricsURL) }
        lyricsURL = destination
        lyricsName = fileName
        lyricLines = lines
        lyricOffset = 0
        if case .failed = state { state = .idle }
    }

    func clearLyrics() {
        guard !isBusy else { return }
        if let lyricsURL { try? FileManager.default.removeItem(at: lyricsURL) }
        lyricsURL = nil
        lyricsName = nil
        lyricLines = []
        lyricOffset = 0
    }

    func start(includeSessionMedia: Bool = false) async {
        guard !isBusy else { return }
        guard await requestPermission() else {
            state = .failed("未获得麦克风权限")
            return
        }

        do {
            try SharedStorage.prepare()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP, .mixWithOthers]
            )
            try session.setPreferredSampleRate(48_000)
            try session.setActive(true)

            let resolvedMode = resolveCaptureMode(session: session)
            if captureMode == .headphones, resolvedMode != .headphones {
                throw AudioRecordingError.headphonesUnavailable
            }
            try session.setMode(resolvedMode == .speaker ? .voiceChat : .default)
            if resolvedMode == .speaker {
                try session.overrideOutputAudioPort(.speaker)
            }

            let quality = UserDefaults(suiteName: SharedStorage.appGroup)?.string(forKey: "audioQuality") ?? "high"
            let bitrate = quality == "standard" ? 128_000 : 256_000
            let selectedAccompaniment = includeSessionMedia ? accompanimentURL : nil
            automaticSyncCompensationMilliseconds = selectedAccompaniment == nil
                ? 0
                : (session.outputLatency + session.ioBufferDuration) * 1_000
            activeVocalAlignmentSeconds = selectedAccompaniment == nil
                ? 0
                : (automaticSyncCompensationMilliseconds + vocalSyncAdjustmentMilliseconds) / 1_000
            var scheduledStartDelay: TimeInterval = 0
            if resolvedMode == .speaker || selectedAccompaniment != nil {
                let prefix = resolvedMode == .speaker ? "Speaker-Raw" : "Voice-Raw"
                let output = SharedStorage.transcodeDirectory
                    .appendingPathComponent("\(prefix)-\(Self.timestamp())-\(UUID().uuidString).caf")
                try startEngineCapture(
                    output: output,
                    accompanimentURL: selectedAccompaniment,
                    voiceProcessing: resolvedMode == .speaker
                )
            } else {
                let outputDirectory = selectedAccompaniment == nil
                    ? SharedStorage.audioDirectory
                    : SharedStorage.transcodeDirectory
                let outputPrefix = selectedAccompaniment == nil ? "Audio" : "Voice"
                let output = outputDirectory
                    .appendingPathComponent("\(outputPrefix)-\(Self.timestamp())-\(UUID().uuidString).m4a")
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: bitrate,
                    AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
                ]
                let recorder = try AVAudioRecorder(url: output, settings: settings)
                recorder.isMeteringEnabled = true
                recorder.prepareToRecord()

                var player: AVAudioPlayer?
                if let selectedAccompaniment {
                    let preparedPlayer = try AVAudioPlayer(contentsOf: selectedAccompaniment)
                    preparedPlayer.volume = Float(accompanimentVolume)
                    preparedPlayer.prepareToPlay()
                    player = preparedPlayer
                }

                player?.currentTime = 0
                if let player {
                    let startTime = max(recorder.deviceCurrentTime, player.deviceCurrentTime) + 0.12
                    guard recorder.record(atTime: startTime) else {
                        throw AudioRecordingError.cannotStart
                    }
                    player.play(atTime: startTime)
                    scheduledStartDelay = max(0, startTime - player.deviceCurrentTime)
                } else {
                    guard recorder.record() else { throw AudioRecordingError.cannotStart }
                }
                self.recorder = recorder
                accompanimentPlayer = player
            }

            activeCaptureMode = resolvedMode
            activeAccompanimentURL = selectedAccompaniment
            activeLyricsURL = includeSessionMedia ? lyricsURL : nil
            startedAt = Date().addingTimeInterval(scheduledStartDelay)
            elapsedBeforePause = 0
            elapsed = 0
            state = .recording
            startMetering()
        } catch {
            recorder?.stop()
            recorder = nil
            accompanimentPlayer?.stop()
            accompanimentPlayer = nil
            stopSpeakerCapture()
            activeCaptureMode = nil
            activeVocalAlignmentSeconds = 0
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            state = .failed(error.localizedDescription)
        }
    }

    func togglePause() {
        switch state {
        case .recording:
            recorder?.pause()
            audioEngine?.pause()
            accompanimentPlayer?.pause()
            engineAccompanimentPlayer?.pause()
            elapsedBeforePause = elapsed
            startedAt = nil
            state = .paused
        case .paused:
            do {
                var scheduledStartDelay: TimeInterval = 0
                if let recorder {
                    if let accompanimentPlayer {
                        let startTime = max(
                            recorder.deviceCurrentTime,
                            accompanimentPlayer.deviceCurrentTime
                        ) + 0.08
                        guard recorder.record(atTime: startTime) else {
                            throw AudioRecordingError.cannotStart
                        }
                        accompanimentPlayer.play(atTime: startTime)
                        scheduledStartDelay = max(0, startTime - accompanimentPlayer.deviceCurrentTime)
                    } else {
                        guard recorder.record() else { throw AudioRecordingError.cannotStart }
                    }
                } else if let audioEngine {
                    try audioEngine.start()
                    engineAccompanimentPlayer?.play()
                } else {
                    return
                }
                startedAt = Date().addingTimeInterval(scheduledStartDelay)
                state = .recording
            } catch {
                state = .failed(error.localizedDescription)
            }
        default:
            break
        }
    }

    func stop() async -> URL? {
        guard let dryOutput = recorder?.url ?? engineOutputURL else { return nil }
        let selectedAccompaniment = activeAccompanimentURL
        let selectedLyrics = activeLyricsURL
        let selectedCaptureMode = activeCaptureMode ?? .headphones
        let selectedVocalAlignment = activeVocalAlignmentSeconds
        recorder?.stop()
        accompanimentPlayer?.stop()
        stopSpeakerCapture()
        meterTask?.cancel()
        meterTask = nil
        self.recorder = nil
        accompanimentPlayer = nil
        activeAccompanimentURL = nil
        activeLyricsURL = nil
        activeCaptureMode = nil
        activeVocalAlignmentSeconds = 0
        startedAt = nil
        elapsedBeforePause = 0

        var vocalURL = dryOutput
        var speakerProcessingFailed = false
        if selectedCaptureMode == .speaker {
            state = .processing
            do {
                vocalURL = try await processSpeakerRecording(
                    dryURL: dryOutput,
                    temporary: selectedAccompaniment != nil
                )
                try? FileManager.default.removeItem(at: dryOutput)
            } catch {
                speakerProcessingFailed = true
            }
        }

        guard let selectedAccompaniment else {
            if selectedCaptureMode == .speaker, speakerProcessingFailed {
                let recoveryURL = SharedStorage.audioDirectory
                    .appendingPathComponent("Speaker-\(Self.timestamp()).caf")
                try? FileManager.default.removeItem(at: recoveryURL)
                try? FileManager.default.moveItem(at: dryOutput, to: recoveryURL)
                if FileManager.default.fileExists(atPath: recoveryURL.path) {
                    vocalURL = recoveryURL
                }
            }
            state = speakerProcessingFailed ? .failed("扬声器优化失败，已保留原声") : .idle
            persistLyrics(selectedLyrics, beside: vocalURL)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return vocalURL
        }

        state = .mixing
        do {
            let output = try await mix(
                vocalURL: vocalURL,
                accompanimentURL: selectedAccompaniment,
                vocalAlignmentSeconds: selectedVocalAlignment
            )
            try? FileManager.default.removeItem(at: dryOutput)
            if vocalURL != dryOutput { try? FileManager.default.removeItem(at: vocalURL) }
            state = .idle
            persistLyrics(selectedLyrics, beside: output)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return output
        } catch {
            let recoveryURL = SharedStorage.audioDirectory
                .appendingPathComponent("Voice-\(Self.timestamp()).\(vocalURL.pathExtension)")
            try? FileManager.default.removeItem(at: recoveryURL)
            try? FileManager.default.moveItem(at: vocalURL, to: recoveryURL)
            if vocalURL != dryOutput { try? FileManager.default.removeItem(at: dryOutput) }
            state = .failed("混音失败，已保留人声")
            persistLyrics(selectedLyrics, beside: recoveryURL)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return FileManager.default.fileExists(atPath: recoveryURL.path) ? recoveryURL : nil
        }
    }

    private func startEngineCapture(
        output: URL,
        accompanimentURL: URL?,
        voiceProcessing: Bool
    ) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if voiceProcessing {
            try input.setVoiceProcessingEnabled(true)
            input.isVoiceProcessingAGCEnabled = speakerProcessingStrength != .natural
        }

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecordingError.inputUnavailable
        }
        let recordingFile = try AVAudioFile(
            forWriting: output,
            settings: inputFormat.settings,
            commonFormat: inputFormat.commonFormat,
            interleaved: inputFormat.isInterleaved
        )
        input.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            do {
                try recordingFile.write(from: buffer)
            } catch {
                return
            }
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var power: Float = 0
            for index in 0..<Int(buffer.frameLength) {
                power += samples[index] * samples[index]
            }
            let level = max(0.04, min(1, sqrt(power / Float(buffer.frameLength)) * 5.5))
            Task { @MainActor [weak self] in
                self?.engineLevel = level
            }
        }

        var player: AVAudioPlayerNode?
        var accompanimentFile: AVAudioFile?
        if let accompanimentURL {
            let file = try AVAudioFile(forReading: accompanimentURL)
            let node = AVAudioPlayerNode()
            node.volume = Float(accompanimentVolume)
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: nil)
            node.scheduleFile(file, at: nil)
            player = node
            accompanimentFile = file
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        player?.play()

        audioEngine = engine
        engineRecordingFile = recordingFile
        engineOutputURL = output
        engineAccompanimentPlayer = player
        engineAccompanimentFile = accompanimentFile
    }

    private func stopSpeakerCapture() {
        guard let engine = audioEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engineAccompanimentPlayer?.stop()
        engine.stop()
        engine.reset()
        engineAccompanimentPlayer = nil
        engineAccompanimentFile = nil
        engineRecordingFile = nil
        engineOutputURL = nil
        audioEngine = nil
        engineLevel = 0.04
    }

    private func processSpeakerRecording(dryURL: URL, temporary: Bool) async throws -> URL {
        let directory = temporary ? SharedStorage.transcodeDirectory : SharedStorage.audioDirectory
        let prefix = temporary ? "Speaker-Voice" : "Speaker"
        let output = directory
            .appendingPathComponent("\(prefix)-\(Self.timestamp())-\(UUID().uuidString).m4a")
        let quality = UserDefaults(suiteName: SharedStorage.appGroup)?.string(forKey: "audioQuality") ?? "high"
        let bitrate = quality == "standard" ? 128_000 : 256_000
        return try await audioTranscoder.transcode(
            inputURL: dryURL,
            outputURL: output,
            muxerName: "ipod",
            encoderName: "aac",
            bitRate: bitrate,
            sampleRate: 48_000,
            channelCount: 1,
            filterDescription: speakerFilterDescription
        )
    }

    private var speakerFilterDescription: String {
        switch speakerProcessingStrength {
        case .natural:
            return "highpass=f=70:p=2,afftdn=nr=7:nf=-28:tn=1,acompressor=threshold=0.22:ratio=1.8:attack=18:release=220:makeup=1.15,alimiter=limit=0.96:attack=5:release=60:latency=1"
        case .balanced:
            return "highpass=f=85:p=2,afftdn=nr=12:nf=-30:tn=1,equalizer=f=240:t=q:w=1.1:g=-2,equalizer=f=3000:t=q:w=1:g=2,acompressor=threshold=0.18:ratio=2.5:attack=15:release=220:makeup=1.35,alimiter=limit=0.94:attack=5:release=70:latency=1"
        case .strong:
            return "highpass=f=100:p=2,afftdn=nr=18:nf=-32:tn=1,equalizer=f=220:t=q:w=1:g=-3.5,equalizer=f=3200:t=q:w=1:g=3,acompressor=threshold=0.14:ratio=3.5:attack=10:release=260:makeup=1.55,alimiter=limit=0.92:attack=4:release=80:latency=1"
        }
    }

    private func resolveCaptureMode(session: AVAudioSession) -> AudioCaptureMode {
        if captureMode == .speaker { return .speaker }
        let hasPrivateOutput = session.currentRoute.outputs.contains { output in
            switch output.portType {
            case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE,
                    .usbAudio, .airPlay, .carAudio, .HDMI, .lineOut:
                true
            default:
                false
            }
        }
        if captureMode == .headphones {
            return hasPrivateOutput ? .headphones : .speaker
        }
        return hasPrivateOutput ? .headphones : .speaker
    }

    private func mix(
        vocalURL: URL,
        accompanimentURL: URL,
        vocalAlignmentSeconds: TimeInterval
    ) async throws -> URL {
        let vocalAsset = AVURLAsset(url: vocalURL)
        let accompanimentAsset = AVURLAsset(url: accompanimentURL)
        let vocalTracks = try await vocalAsset.loadTracks(withMediaType: .audio)
        let accompanimentTracks = try await accompanimentAsset.loadTracks(withMediaType: .audio)
        guard let vocalSource = vocalTracks.first,
              let accompanimentSource = accompanimentTracks.first else {
            throw AudioRecordingError.missingAudioTrack
        }

        let vocalDuration = try await vocalAsset.load(.duration)
        let accompanimentDuration = try await accompanimentAsset.load(.duration)
        guard vocalDuration.isValid, vocalDuration.seconds > 0 else {
            throw AudioRecordingError.invalidDuration
        }

        let composition = AVMutableComposition()
        guard let vocalTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let accompanimentTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioRecordingError.cannotCreateMix
        }

        let vocalTrim = CMTime(
            seconds: min(max(0, vocalAlignmentSeconds), max(0, vocalDuration.seconds - 0.05)),
            preferredTimescale: 48_000
        )
        let vocalDelay = CMTime(
            seconds: max(0, -vocalAlignmentSeconds),
            preferredTimescale: 48_000
        )
        let alignedVocalDuration = CMTimeSubtract(vocalDuration, vocalTrim)
        try vocalTrack.insertTimeRange(
            CMTimeRange(start: vocalTrim, duration: alignedVocalDuration),
            of: vocalSource,
            at: vocalDelay
        )
        let alignedOutputDuration = CMTimeAdd(vocalDelay, alignedVocalDuration)
        let accompanimentInsertDuration = CMTimeCompare(accompanimentDuration, alignedOutputDuration) < 0
            ? accompanimentDuration
            : alignedOutputDuration
        if accompanimentInsertDuration.isValid, accompanimentInsertDuration.seconds > 0 {
            try accompanimentTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: accompanimentInsertDuration),
                of: accompanimentSource,
                at: .zero
            )
        }

        let vocalParameters = AVMutableAudioMixInputParameters(track: vocalTrack)
        vocalParameters.setVolume(Float(vocalVolume), at: .zero)
        let accompanimentParameters = AVMutableAudioMixInputParameters(track: accompanimentTrack)
        accompanimentParameters.setVolume(Float(accompanimentVolume), at: .zero)
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [vocalParameters, accompanimentParameters]

        let output = SharedStorage.audioDirectory
            .appendingPathComponent("Karaoke-\(Self.timestamp())-\(UUID().uuidString).m4a")
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioRecordingError.cannotCreateExporter
        }
        exporter.audioMix = audioMix
        try await exporter.export(to: output, as: .m4a)
        return output
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.state == .recording {
                    let normalized: Float
                    if let recorder = self.recorder {
                        recorder.updateMeters()
                        let decibels = recorder.averagePower(forChannel: 0)
                        normalized = max(0.04, min(1, pow(10, decibels / 36)))
                    } else {
                        normalized = self.engineLevel
                    }
                    self.levels.append(normalized)
                    if self.levels.count > 48 { self.levels.removeFirst(self.levels.count - 48) }
                    if let startedAt = self.startedAt {
                        self.elapsed = self.elapsedBeforePause + max(0, Date().timeIntervalSince(startedAt))
                    }
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func persistLyrics(_ sourceURL: URL?, beside audioURL: URL) {
        guard let sourceURL else { return }
        let fileExtension = LyricDocumentCodec.normalizedFileExtension(for: sourceURL)
        let destination = audioURL.deletingPathExtension().appendingPathExtension(fileExtension)
        try? FileManager.default.removeItem(at: destination)
        if fileExtension != "txt", lyricLines.contains(where: { $0.time != nil }) {
            let text = LyricDocumentCodec.renderLRC(lyricLines, offset: lyricOffset)
            try? text.write(to: destination, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.copyItem(at: sourceURL, to: destination)
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private enum AudioRecordingError: LocalizedError {
    case cannotStart
    case inputUnavailable
    case headphonesUnavailable
    case missingAudioTrack
    case invalidDuration
    case cannotCreateMix
    case cannotCreateExporter
    case invalidLyrics

    var errorDescription: String? {
        switch self {
        case .cannotStart: "无法开始录音"
        case .inputUnavailable: "当前没有可用的麦克风输入"
        case .headphonesUnavailable: "未检测到耳机"
        case .missingAudioTrack: "伴奏文件没有音轨"
        case .invalidDuration: "录音时长无效"
        case .cannotCreateMix: "无法创建混音轨道"
        case .cannotCreateExporter: "无法创建混音导出器"
        case .invalidLyrics: "无法读取歌词文件"
        }
    }
}
