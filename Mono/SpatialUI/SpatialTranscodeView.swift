import SwiftUI
import UniformTypeIdentifiers

struct SpatialTranscodeView: View {
    @StateObject private var queue = TranscodeQueue()
    @State private var importing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SpatialHeading(title: "转码", detail: "从输入到输出，一条路径")
                if queue.jobs.isEmpty { emptyFlow } else { activeFlow }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie, .audio, .data], allowsMultipleSelection: true) { result in
            Task { await receive(result) }
        }
    }

    private var emptyFlow: some View {
        VStack(spacing: 18) {
            Button { importing = true } label: {
                ZStack {
                    Circle().stroke(SpatialColor.ice.opacity(0.32), lineWidth: 1).frame(width: 240, height: 240)
                    Circle().stroke(SpatialColor.sea.opacity(0.22), lineWidth: 1).frame(width: 178, height: 178)
                    VStack(spacing: 11) {
                        Image(systemName: "plus").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 66, height: 66).spatialGlass(Circle(), tint: SpatialColor.seaDeep, interactive: true)
                        Text("放入媒体").font(.system(.headline, design: .rounded, weight: .bold))
                        Text("视频或音频").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 330)
            }.buttonStyle(SpatialGlassButtonStyle()).foregroundStyle(.primary)

            flowLine
            HStack(spacing: 10) {
                format("视频", "MP4 · MOV · MKV", "film")
                format("音频", "FLAC · WAV · MP3", "waveform")
            }
        }
    }

    private var flowLine: some View {
        HStack(spacing: 0) {
            flowStep("输入", active: true)
            connector
            flowStep("参数", active: false)
            connector
            flowStep("输出", active: false)
        }
    }

    private var activeFlow: some View {
        VStack(spacing: 18) {
            HStack {
                Text("\(queue.jobs.count) 个文件").font(.title2.bold())
                Spacer()
                Button { importing = true } label: { Image(systemName: "plus").frame(width: 44, height: 44).spatialGlass(Circle(), interactive: true) }.buttonStyle(SpatialGlassButtonStyle())
            }
            ForEach(queue.jobs) { job in jobFlow(job) }
            Button { queue.isRunning ? queue.stop() : queue.start() } label: {
                Label(queue.isRunning ? "完成当前项后停止" : "开始转码", systemImage: queue.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .spatialGlass(Capsule(), tint: SpatialColor.seaDeep, interactive: true)
            }.buttonStyle(SpatialGlassButtonStyle())
        }
    }

    private func jobFlow(_ job: TranscodeJob) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: job.probe.hasVideo ? "film" : "waveform").foregroundStyle(SpatialColor.seaDeep)
                VStack(alignment: .leading, spacing: 3) { Text(job.title).font(.subheadline.bold()).lineLimit(1); Text(job.detail).font(.caption2.monospaced()).foregroundStyle(.secondary) }
                Spacer(); Text(job.target.pathExtension.uppercased()).font(.caption.bold())
            }
            ProgressView(value: progress(job)).tint(SpatialColor.sea)
            HStack { Text("输入"); Spacer(); Image(systemName: "arrow.right"); Spacer(); Text(job.target.pathExtension.uppercased()) }
                .font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 17)
        .overlay(alignment: .bottom) { Divider().opacity(0.18) }
    }

    private func progress(_ job: TranscodeJob) -> Double {
        switch job.status { case .completed: 1; case .running: job.progress; default: 0 }
    }

    private func flowStep(_ title: String, active: Bool) -> some View {
        Text(title).font(.caption.bold()).foregroundStyle(active ? SpatialColor.seaDeep : .secondary)
            .frame(width: 72, height: 40).spatialGlass(Capsule(), tint: active ? SpatialColor.sea.opacity(0.10) : nil)
    }
    private var connector: some View { Rectangle().fill(SpatialColor.ice.opacity(0.34)).frame(maxWidth: .infinity).frame(height: 1) }
    private func format(_ title: String, _ detail: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) { Image(systemName: symbol).foregroundStyle(SpatialColor.seaDeep); Text(title).font(.subheadline.bold()); Text(detail).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1) }
            .padding(16).frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
    }

    @MainActor private func receive(_ result: Result<[URL], Error>) async {
        guard let urls = try? result.get() else { return }
        for source in urls {
            let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
            do {
                try SharedStorage.prepare(); let ext = source.pathExtension.isEmpty ? "media" : source.pathExtension
                let target = SharedStorage.transcodeDirectory.appendingPathComponent("Input-\(UUID().uuidString).\(ext)")
                try FileManager.default.copyItem(at: source, to: target)
                let probe = try await MediaProbe.inspect(target); try queue.add(files: [(target, probe)])
            } catch { }
        }
    }
}
