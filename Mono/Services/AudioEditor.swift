import AVFoundation
import FFmpegSwiftSDK
import Foundation

private enum AudioNoiseAnalysisError: LocalizedError {
    case insufficientSamples
    var errorDescription: String? { "音频太短，无法建立噪声指纹" }
}

enum AudioExportFormat: String, CaseIterable, Identifiable {
    case m4a = "M4A"
    case mp3 = "MP3"
    case flac = "FLAC"
    case wav = "WAV"

    var id: String { rawValue }

    var pathExtension: String { rawValue.lowercased() }

    var muxer: String {
        switch self {
        case .m4a: "ipod"
        case .mp3: "mp3"
        case .flac: "flac"
        case .wav: "wav"
        }
    }

    var encoders: [String] {
        switch self {
        case .m4a: ["aac"]
        case .mp3: ["libmp3lame", "mp3"]
        case .flac: ["flac"]
        case .wav: ["pcm_s24le", "pcm_s16le"]
        }
    }
}

enum AudioExportBitrate: Int, CaseIterable, Identifiable {
    case kbps128 = 128_000
    case kbps192 = 192_000
    case kbps256 = 256_000
    case kbps320 = 320_000

    var id: Int { rawValue }
    var title: String { "\(rawValue / 1_000)K" }
}

struct AudioClip: Identifiable, Equatable {
    let id: UUID
    var start: Double
    var end: Double

    init(id: UUID = UUID(), start: Double, end: Double) {
        self.id = id
        self.start = start
        self.end = end
    }

    var duration: Double { max(0, end - start) }
}

struct AudioSilenceRegion: Identifiable, Equatable, Sendable {
    let id: UUID
    let start: Double
    let end: Double
    let averageLevel: Float

    init(id: UUID = UUID(), start: Double, end: Double, averageLevel: Float) {
        self.id = id
        self.start = start
        self.end = end
        self.averageLevel = averageLevel
    }

    var duration: Double { max(0, end - start) }
}

enum AudioEQPreset: String, CaseIterable, Identifiable {
    case flat = "原声"
    case vocal = "人声"
    case warm = "温暖"
    case bright = "明亮"

    var id: String { rawValue }
}

@MainActor
final class AudioEditor: ObservableObject {
    @Published private(set) var clips: [AudioClip]
    @Published private(set) var selectedClipID: UUID
    @Published var trimStart: Double
    @Published var trimEnd: Double
    @Published var speed: Double = 1
    @Published var volume: Double = 1
    @Published var fadeIn: Double = 0
    @Published var fadeOut: Double = 0
    @Published var noiseReduction: Double = 0
    @Published var bassGain: Double = 0
    @Published var midGain: Double = 0
    @Published var trebleGain: Double = 0
    @Published var pitchSemitones: Double = 0
    @Published var exportFormat: AudioExportFormat = .m4a
    @Published var exportBitrate: AudioExportBitrate = .kbps256
    @Published var exportSampleRate = 48_000
    @Published var exportChannelCount = 2
    @Published private(set) var waveform: [Float] = []
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var lyricFileName: String?
    @Published private(set) var isExporting = false
    @Published private(set) var isRenderingPreview = false
    @Published private(set) var exportProgress: Double = 0
    @Published private(set) var silenceRegions: [AudioSilenceRegion] = []
    @Published private(set) var isAnalyzingSilence = false
    @Published private(set) var silenceAnalysisError: String?
    @Published private(set) var isAnalyzingNoise = false
    @Published private(set) var detectedNoiseFloor: Float?
    @Published private(set) var noiseAnalysisError: String?

    let sourceURL: URL
    let duration: Double
    private let ffmpeg = AudioProcessor()
    private let transcoder = FFmpegAudioTranscoder()
    private let codecCatalog = CodecCapabilities.runtimeCatalog()
    private var undoStack: [[AudioClip]] = []
    private var redoStack: [[AudioClip]] = []
    private var previewFiles: [URL] = []

    init(sourceURL: URL, duration: Double) {
        self.sourceURL = sourceURL
        self.duration = max(duration, 0.1)
        let clip = AudioClip(start: 0, end: max(duration, 0.1))
        self.clips = [clip]
        self.selectedClipID = clip.id
        self.trimStart = clip.start
        self.trimEnd = clip.end
        loadLyricsFromSidecar()
    }

    var selectedClipIndex: Int? { clips.firstIndex { $0.id == selectedClipID } }
    var selectedClip: AudioClip? { selectedClipIndex.map { clips[$0] } }
    var selectedDuration: Double { max(0.1, clips.reduce(0) { $0 + $1.duration } / speed) }
    var canDeleteClip: Bool { clips.count > 1 }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasLyrics: Bool { !lyrics.isEmpty }
    var hasAudioEffects: Bool {
        noiseReduction > 0.01 || abs(bassGain) > 0.01 || abs(midGain) > 0.01
            || abs(trebleGain) > 0.01 || abs(pitchSemitones) > 0.01
    }
    var detectedSilenceDuration: Double { silenceRegions.reduce(0) { $0 + $1.duration } }

    var availableFormats: [AudioExportFormat] {
        AudioExportFormat.allCases.filter { format in
            format.encoders.contains(where: codecCatalog.encoders.contains)
                && codecCatalog.muxers.contains(format.muxer)
        }
    }

    func selectClip(_ id: UUID) {
        guard let clip = clips.first(where: { $0.id == id }) else { return }
        selectedClipID = id
        trimStart = clip.start
        trimEnd = clip.end
    }

    func setTrimStart(_ value: Double) {
        guard let index = selectedClipIndex else { return }
        trimStart = max(0, min(trimEnd - 0.01, value))
        clips[index].start = trimStart
    }

    func setTrimEnd(_ value: Double) {
        guard let index = selectedClipIndex else { return }
        trimEnd = min(duration, max(trimStart + 0.01, value))
        clips[index].end = trimEnd
    }

    @discardableResult
    func split(at time: Double) -> Bool {
        guard let index = selectedClipIndex else { return false }
        let clip = clips[index]
        let value = min(duration, max(0, time))
        guard value > clip.start + 0.02, value < clip.end - 0.02 else { return false }
        registerChange()
        let left = AudioClip(start: clip.start, end: value)
        let right = AudioClip(start: value, end: clip.end)
        clips.replaceSubrange(index...index, with: [left, right])
        selectClip(right.id)
        return true
    }

    func deleteSelectedClip() {
        guard clips.count > 1, let index = selectedClipIndex else { return }
        registerChange()
        clips.remove(at: index)
        selectClip(clips[min(index, clips.count - 1)].id)
    }

    func duplicateSelectedClip() {
        guard let index = selectedClipIndex else { return }
        registerChange()
        let source = clips[index]
        let copy = AudioClip(start: source.start, end: source.end)
        clips.insert(copy, at: index + 1)
        selectClip(copy.id)
    }

    func moveSelected(by offset: Int) {
        guard let index = selectedClipIndex else { return }
        let destination = index + offset
        guard clips.indices.contains(destination) else { return }
        registerChange()
        clips.swapAt(index, destination)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(clips)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(clips)
        restore(next)
    }

    @Published private(set) var waveformError: String?

    func loadWaveform() async {
        guard waveform.isEmpty else { return }
        waveformError = nil
        do {
            let samples = try await WaveformGenerator().generate(
                url: sourceURL.path,
                samplesCount: 160,
                maxDuration: 0
            )
            waveform = samples.map { max(abs($0.positive), abs($0.negative)) }
        } catch {
            waveformError = "无法读取音频波形：\(error.localizedDescription)。可重试加载或重新导入音频。"
        }
    }

    func analyzeSilence(threshold: Float = -45, minimumDuration: Double = 0.45) async {
        guard !isAnalyzingSilence else { return }
        isAnalyzingSilence = true
        silenceAnalysisError = nil
        defer { isAnalyzingSilence = false }

        do {
            let path = sourceURL.path
            let regions = try await Task.detached(priority: .userInitiated) {
                let decoded = try AudioAnalyzer.decodeAudioFile(
                    url: path,
                    maxDuration: 0,
                    outputChannelCount: 1
                )
                return AudioAnalyzer.detectSilence(
                    samples: decoded.samples,
                    sampleRate: decoded.sampleRate,
                    threshold: threshold,
                    minDuration: minimumDuration
                ).map {
                    AudioSilenceRegion(start: $0.startTime, end: $0.endTime, averageLevel: $0.averageLevel)
                }
            }.value
            silenceRegions = regions
        } catch {
            silenceRegions = []
            silenceAnalysisError = error.localizedDescription
        }
    }

    func autoTuneNoiseReduction() async {
        guard !isAnalyzingNoise else { return }
        isAnalyzingNoise = true
        noiseAnalysisError = nil
        defer { isAnalyzingNoise = false }

        do {
            let path = sourceURL.path
            let profile = try await Task.detached(priority: .userInitiated) {
                let decoded = try AudioAnalyzer.decodeAudioFile(
                    url: path,
                    maxDuration: 90,
                    outputChannelCount: 1
                )
                let samples = decoded.samples
                guard samples.count >= 1_024 else { throw AudioNoiseAnalysisError.insufficientSamples }
                var levels: [Float] = []
                levels.reserveCapacity(samples.count / 1_024)
                var index = 0
                while index + 1_024 <= samples.count {
                    let window = samples[index..<(index + 1_024)]
                    let meanSquare = window.reduce(Float.zero) { $0 + $1 * $1 } / Float(window.count)
                    let rms = sqrt(max(meanSquare, 0.000_000_000_1))
                    levels.append(20 * log10(rms))
                    index += 1_024
                }
                levels.sort()
                let percentileIndex = min(levels.count - 1, max(0, Int(Double(levels.count) * 0.2)))
                let floor = levels[percentileIndex]
                let reduction = min(28, max(4, (Double(-floor) - 24) * 0.72))
                return (floor, reduction)
            }.value
            detectedNoiseFloor = profile.0
            noiseReduction = profile.1
        } catch {
            noiseAnalysisError = error.localizedDescription
        }
    }

    @discardableResult
    func applySilenceRemoval(padding: Double = 0.08) -> Bool {
        guard !silenceRegions.isEmpty else { return false }
        var rebuilt: [AudioClip] = []

        for clip in clips {
            var cursor = clip.start
            for silence in silenceRegions where silence.end > clip.start && silence.start < clip.end {
                let removalStart = min(clip.end, max(cursor, silence.start + padding))
                let removalEnd = min(clip.end, max(removalStart, silence.end - padding))
                if removalStart - cursor >= 0.03 {
                    rebuilt.append(AudioClip(start: cursor, end: removalStart))
                }
                cursor = max(cursor, removalEnd)
            }
            if clip.end - cursor >= 0.03 {
                rebuilt.append(AudioClip(start: cursor, end: clip.end))
            }
        }

        guard !rebuilt.isEmpty, rebuilt != clips else { return false }
        registerChange()
        clips = rebuilt
        selectClip(rebuilt[0].id)
        return true
    }

    func applyEQPreset(_ preset: AudioEQPreset) {
        switch preset {
        case .flat:
            bassGain = 0
            midGain = 0
            trebleGain = 0
        case .vocal:
            bassGain = -1.5
            midGain = 3.5
            trebleGain = 1.5
        case .warm:
            bassGain = 3
            midGain = 1
            trebleGain = -1
        case .bright:
            bassGain = -1
            midGain = 1.5
            trebleGain = 4
        }
    }

    func renderEffectPreview() async throws -> URL {
        guard !isRenderingPreview else { throw AudioEffectError.previewInProgress }
        isRenderingPreview = true
        defer { isRenderingPreview = false }
        try SharedStorage.prepare()

        let raw = SharedStorage.exportDirectory
            .appendingPathComponent("Preview-Raw-\(UUID().uuidString).m4a")
        let output = SharedStorage.exportDirectory
            .appendingPathComponent("Preview-FX-\(UUID().uuidString).m4a")
        try await renderTimeline(to: raw)
        guard hasAudioEffects else {
            previewFiles.append(raw)
            removeOldPreviews(keeping: raw)
            return raw
        }
        _ = try await transcoder.transcode(
            inputURL: raw,
            outputURL: output,
            muxerName: "ipod",
            encoderName: "aac",
            bitRate: 256_000,
            filterDescription: audioFilterDescription
        )
        try? FileManager.default.removeItem(at: raw)
        previewFiles.append(output)
        removeOldPreviews(keeping: output)
        return output
    }

    func importLyrics(from sourceURL: URL) throws {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: sourceURL)
        guard let text = LyricDocumentCodec.decode(data) else { throw LyricEditingError.cannotRead }
        let parsed = LyricDocumentCodec.parse(text)
        guard !parsed.isEmpty else { throw LyricEditingError.cannotRead }
        lyrics = parsed
        lyricFileName = sourceURL.lastPathComponent
    }

    func updateLyric(_ id: Int, text: String? = nil, time: Double? = nil) {
        guard let index = lyrics.firstIndex(where: { $0.id == id }) else { return }
        let old = lyrics[index]
        lyrics[index] = LyricLine(
            id: old.id,
            time: time.map { min(duration, max(0, $0)) } ?? old.time,
            text: text ?? old.text
        )
    }

    func setLyricTime(_ id: Int, to time: Double) {
        updateLyric(id, time: time)
    }

    func shiftLyrics(by offset: Double) {
        lyrics = lyrics.map {
            LyricLine(id: $0.id, time: $0.time.map { min(duration, max(0, $0 + offset)) }, text: $0.text)
        }
    }

    func addLyric(at time: Double) -> Int {
        let id = (lyrics.map(\.id).max() ?? -1) + 1
        lyrics.append(LyricLine(id: id, time: min(duration, max(0, time)), text: "新歌词"))
        lyrics.sort { ($0.time ?? .greatestFiniteMagnitude) < ($1.time ?? .greatestFiniteMagnitude) }
        return id
    }

    func deleteLyric(_ id: Int) {
        lyrics.removeAll { $0.id == id }
    }

    @discardableResult
    func saveLyrics() throws -> URL {
        guard !lyrics.isEmpty else { throw LyricEditingError.empty }
        let output = sourceURL.deletingPathExtension().appendingPathExtension("lrc")
        try writeLyrics(lyrics, to: output)
        lyricFileName = output.lastPathComponent
        return output
    }

    func export() async throws -> URL {
        isExporting = true
        exportProgress = 0.04
        defer {
            isExporting = false
            exportProgress = 0
        }
        try SharedStorage.prepare()

        let finalURL = SharedStorage.audioDirectory
            .appendingPathComponent("Edit-\(UUID().uuidString).\(exportFormat.pathExtension)")
        let requiresTranscode = exportFormat != .m4a || hasAudioEffects
        let intermediate = !requiresTranscode
            ? finalURL
            : SharedStorage.exportDirectory.appendingPathComponent("Audio-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: finalURL)
        try? FileManager.default.removeItem(at: intermediate)
        defer {
            if intermediate != finalURL { try? FileManager.default.removeItem(at: intermediate) }
        }

        try await renderTimeline(to: intermediate)
        exportProgress = requiresTranscode ? 0.64 : 1
        guard requiresTranscode else {
            try persistExportLyrics(beside: finalURL)
            return finalURL
        }

        guard let encoder = exportFormat.encoders.first(where: codecCatalog.encoders.contains) else {
            throw MediaConversionError.transcodeFailed("当前 FFmpeg 静态库不支持 \(exportFormat.rawValue) 编码")
        }
        let bitRate = [.flac, .wav].contains(exportFormat) ? 0 : exportBitrate.rawValue
        _ = try await transcoder.transcode(
            inputURL: intermediate,
            outputURL: finalURL,
            muxerName: exportFormat.muxer,
            encoderName: encoder,
            bitRate: bitRate,
            sampleRate: exportSampleRate,
            channelCount: exportChannelCount,
            filterDescription: hasAudioEffects ? audioFilterDescription : nil
        ) { [weak self] value in
            Task { @MainActor [weak self] in
                self?.exportProgress = 0.64 + value * 0.36
            }
        }
        exportProgress = 1
        try persistExportLyrics(beside: finalURL)
        return finalURL
    }

    private var audioFilterDescription: String? {
        var filters: [String] = []
        if noiseReduction > 0.01 {
            filters.append(String(format: "afftdn=nr=%.1f:nf=-25:tn=1", noiseReduction))
        }
        if abs(bassGain) > 0.01 {
            filters.append(String(format: "bass=g=%.1f:f=110:w=0.6", bassGain))
        }
        if abs(midGain) > 0.01 {
            filters.append(String(format: "equalizer=f=1200:t=q:w=1:g=%.1f", midGain))
        }
        if abs(trebleGain) > 0.01 {
            filters.append(String(format: "treble=g=%.1f:f=6500:w=0.6", trebleGain))
        }
        if abs(pitchSemitones) > 0.01 {
            let ratio = pow(2, pitchSemitones / 12)
            let sampleRate = max(8_000, sourceSampleRate)
            filters.append(String(
                format: "asetrate=%.0f,aresample=%d,atempo=%.6f",
                Double(sampleRate) * ratio,
                sampleRate,
                1 / ratio
            ))
        }
        return filters.isEmpty ? nil : filters.joined(separator: ",")
    }

    private var sourceSampleRate: Int {
        guard let file = try? AVAudioFile(forReading: sourceURL) else { return 48_000 }
        return Int(file.processingFormat.sampleRate.rounded())
    }

    private func removeOldPreviews(keeping current: URL) {
        for url in previewFiles where url != current {
            try? FileManager.default.removeItem(at: url)
        }
        previewFiles = [current]
    }

    private func loadLyricsFromSidecar() {
        for fileExtension in LyricDocumentCodec.supportedFileExtensions {
            let candidate = sourceURL.deletingPathExtension().appendingPathExtension(fileExtension)
            guard FileManager.default.fileExists(atPath: candidate.path),
                  let data = try? Data(contentsOf: candidate),
                  let text = LyricDocumentCodec.decode(data) else { continue }
            let parsed = LyricDocumentCodec.parse(text)
            guard !parsed.isEmpty else { continue }
            lyrics = parsed
            lyricFileName = candidate.lastPathComponent
            return
        }
    }

    private func persistExportLyrics(beside outputURL: URL) throws {
        guard !lyrics.isEmpty else { return }
        let destination = outputURL.deletingPathExtension().appendingPathExtension("lrc")
        if lyrics.allSatisfy({ $0.time == nil }) {
            try writeLyrics(lyrics, to: destination)
            return
        }
        var cursor = 0.0
        var transformed: [LyricLine] = []
        var nextID = 0
        for clip in clips {
            let matching = lyrics.filter { line in
                guard let time = line.time else { return false }
                return time >= clip.start && time < clip.end
            }
            for line in matching {
                let outputTime = cursor + ((line.time ?? clip.start) - clip.start) / speed
                transformed.append(LyricLine(id: nextID, time: outputTime, text: line.text))
                nextID += 1
            }
            cursor += clip.duration / speed
        }
        guard !transformed.isEmpty else { return }
        try writeLyrics(transformed, to: destination)
    }

    private func writeLyrics(_ lines: [LyricLine], to output: URL) throws {
        let sorted = lines.sorted { ($0.time ?? .greatestFiniteMagnitude) < ($1.time ?? .greatestFiniteMagnitude) }
        let document = LyricDocumentCodec.renderLRC(sorted)
        do {
            try document.write(to: output, atomically: true, encoding: .utf8)
        } catch {
            throw LyricEditingError.cannotWrite
        }
    }

    private func renderTimeline(to output: URL) async throws {
        if let only = clips.first,
           clips.count == 1,
           abs(speed - 1) < 0.001,
           abs(volume - 1) < 0.001,
           fadeIn == 0,
           fadeOut == 0 {
            do {
                _ = try await trimWithFFmpeg(output: output, clip: only)
                exportProgress = 0.6
                return
            } catch {
                try? FileManager.default.removeItem(at: output)
            }
        }

        let asset = AVURLAsset(url: sourceURL)
        let composition = AVMutableComposition()
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first,
              let track = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else { throw ExportError.missingAudio }

        var cursor = CMTime.zero
        for clip in clips where clip.duration > 0.01 {
            let range = CMTimeRange(
                start: CMTime(seconds: clip.start, preferredTimescale: 60_000),
                duration: CMTime(seconds: clip.duration, preferredTimescale: 60_000)
            )
            try track.insertTimeRange(range, of: sourceTrack, at: cursor)
            let targetDuration = CMTimeMultiplyByFloat64(range.duration, multiplier: 1 / speed)
            if abs(speed - 1) > 0.001 {
                composition.scaleTimeRange(
                    CMTimeRange(start: cursor, duration: range.duration),
                    toDuration: targetDuration
                )
            }
            cursor = cursor + targetDuration
        }
        guard cursor.seconds > 0 else { throw ExportError.exportFailed }

        let parameters = AVMutableAudioMixInputParameters(track: track)
        let targetVolume = Float(volume)
        parameters.setVolume(targetVolume, at: .zero)
        let total = cursor.seconds
        if fadeIn > 0 {
            parameters.setVolumeRamp(
                fromStartVolume: 0,
                toEndVolume: targetVolume,
                timeRange: CMTimeRange(
                    start: .zero,
                    duration: CMTime(seconds: min(fadeIn, total / 2), preferredTimescale: 600)
                )
            )
        }
        if fadeOut > 0 {
            let fade = CMTime(seconds: min(fadeOut, total / 2), preferredTimescale: 600)
            parameters.setVolumeRamp(
                fromStartVolume: targetVolume,
                toEndVolume: 0,
                timeRange: CMTimeRange(start: cursor - fade, duration: fade)
            )
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else { throw ExportError.exportFailed }
        exporter.audioMix = mix
        exportProgress = 0.32
        try await exporter.export(to: output, as: .m4a)
        exportProgress = 0.6
    }

    private func trimWithFFmpeg(output: URL, clip: AudioClip) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            ffmpeg.trim(
                inputURL: sourceURL,
                outputURL: output,
                config: .init(startTime: clip.start, endTime: clip.end),
                progress: { [weak self] progress in
                    Task { @MainActor [weak self] in self?.exportProgress = Double(progress) * 0.6 }
                }
            ) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func registerChange() {
        undoStack.append(clips)
        if undoStack.count > 30 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func restore(_ snapshot: [AudioClip]) {
        clips = snapshot
        if !clips.contains(where: { $0.id == selectedClipID }), let first = clips.first {
            selectedClipID = first.id
        }
        selectClip(selectedClipID)
    }
}

private enum LyricEditingError: LocalizedError {
    case cannotRead
    case cannotWrite
    case empty

    var errorDescription: String? {
        switch self {
        case .cannotRead: "无法读取歌词文件"
        case .cannotWrite: "无法保存歌词文件"
        case .empty: "还没有歌词"
        }
    }
}

private enum AudioEffectError: LocalizedError {
    case previewInProgress

    var errorDescription: String? { "正在生成试听" }
}
