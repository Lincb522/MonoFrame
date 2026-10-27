import Foundation

struct TranscodeJob: Identifiable {
    enum Status {
        case waiting
        case running
        case completed(URL)
        case failed(String)
    }

    let id: UUID
    let inputURL: URL
    let probe: MediaProbe
    var target: MediaTranscodeTarget
    var status: Status
    var progress: Double

    var title: String { inputURL.lastPathComponent }

    var detail: String {
        let kind = probe.hasVideo ? "VIDEO" : "AUDIO"
        let codec = probe.videoCodec ?? probe.audioCodec ?? "UNKNOWN"
        let seconds = max(0, Int(probe.duration.rounded()))
        return "\(kind)  ·  \(codec.uppercased())  ·  \(String(format: "%02d:%02d", seconds / 60, seconds % 60))"
    }
}

@MainActor
final class TranscodeQueue: ObservableObject {
    @Published private(set) var jobs: [TranscodeJob] = []
    @Published private(set) var isRunning = false
    @Published private(set) var activeJobID: UUID?

    private let transcoder = MediaTranscoder()
    private var worker: Task<Void, Never>?
    private var stopAfterCurrent = false

    var completedCount: Int {
        jobs.filter {
            if case .completed = $0.status { return true }
            return false
        }.count
    }

    var failedCount: Int {
        jobs.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
    }

    var waitingCount: Int {
        jobs.filter {
            if case .waiting = $0.status { return true }
            return false
        }.count
    }

    var overallProgress: Double {
        guard !jobs.isEmpty else { return 0 }
        let total = jobs.reduce(0) { partial, job in
            switch job.status {
            case .completed:
                return partial + 1
            case .running:
                return partial + job.progress
            default:
                return partial
            }
        }
        return min(1, max(0, total / Double(jobs.count)))
    }

    func availableTargets(for probe: MediaProbe) -> [MediaTranscodeTarget] {
        transcoder.availableTargets(for: probe)
    }

    func add(files: [(URL, MediaProbe)]) throws {
        var newJobs: [TranscodeJob] = []
        for file in files {
            let choices = transcoder.availableTargets(for: file.1)
            guard let target = defaultTarget(for: file.1, choices: choices) else {
                throw TranscodeQueueError.noOutputFormat
            }
            newJobs.append(
                TranscodeJob(
                    id: UUID(),
                    inputURL: file.0,
                    probe: file.1,
                    target: target,
                    status: .waiting,
                    progress: 0
                )
            )
        }
        jobs.append(contentsOf: newJobs)
    }

    func setTarget(_ target: MediaTranscodeTarget, for id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        guard canEdit(jobs[index]) else { return }
        jobs[index].target = target
    }

    func remove(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        guard canEdit(jobs[index]) else { return }
        let url = jobs[index].inputURL
        jobs.remove(at: index)
        try? FileManager.default.removeItem(at: url)
    }

    func retry(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        guard case .failed = jobs[index].status else { return }
        jobs[index].status = .waiting
        jobs[index].progress = 0
    }

    func clearFinished() {
        jobs.removeAll { job in
            switch job.status {
            case .completed, .failed:
                try? FileManager.default.removeItem(at: job.inputURL)
                return true
            default:
                return false
            }
        }
    }

    func start() {
        guard !isRunning else { return }
        stopAfterCurrent = false
        worker = Task { await processQueue() }
    }

    func stop() {
        stopAfterCurrent = true
    }

    private func processQueue() async {
        isRunning = true
        defer {
            isRunning = false
            activeJobID = nil
            worker = nil
        }

        while !stopAfterCurrent, var job = nextWaitingJob() {
            guard let target = supportedTarget(for: job) else {
                update(job.id) {
                    $0.status = .failed(TranscodeQueueError.noOutputFormat.localizedDescription)
                    $0.progress = 0
                }
                continue
            }
            job.target = target
            activeJobID = job.id
            update(job.id) {
                $0.target = target
                $0.status = .running
                $0.progress = 0
            }

            let monitor = Task { @MainActor in
                while !Task.isCancelled {
                    update(job.id) { $0.progress = transcoder.progress }
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }

            do {
                let output = try await transcoder.transcode(inputURL: job.inputURL, target: job.target)
                monitor.cancel()
                update(job.id) {
                    $0.status = .completed(output)
                    $0.progress = 1
                }
            } catch {
                monitor.cancel()
                update(job.id) {
                    $0.status = .failed(error.localizedDescription)
                    $0.progress = 0
                }
            }
        }
    }

    private func nextWaitingJob() -> TranscodeJob? {
        jobs.first {
            if case .waiting = $0.status { return true }
            return false
        }
    }

    private func update(_ id: UUID, mutate: (inout TranscodeJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[index])
    }

    private func canEdit(_ job: TranscodeJob) -> Bool {
        if case .running = job.status { return false }
        return true
    }

    private func supportedTarget(for job: TranscodeJob) -> MediaTranscodeTarget? {
        let choices = transcoder.availableTargets(for: job.probe)
        if choices.contains(job.target) { return job.target }
        return defaultTarget(for: job.probe, choices: choices)
    }

    private func defaultTarget(
        for probe: MediaProbe,
        choices: [MediaTranscodeTarget]
    ) -> MediaTranscodeTarget? {
        if probe.hasVideo {
            return choices.first(where: { $0 == .hevcMP4 })
                ?? choices.first(where: { $0 == .h264MP4 })
                ?? choices.first
        }
        return choices.first(where: { $0 == .m4a })
            ?? choices.first(where: { $0 == .mp3 })
            ?? choices.first
    }
}

private enum TranscodeQueueError: LocalizedError {
    case noOutputFormat

    var errorDescription: String? { "当前文件没有可用输出格式" }
}
