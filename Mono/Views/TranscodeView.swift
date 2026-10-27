import SwiftUI
import UniformTypeIdentifiers

struct TranscodeView: View {
    @StateObject private var queue = TranscodeQueue()
    @State private var isImporting = false
    @State private var selectedJobID: UUID?
    @State private var message: String?
    @Namespace private var jobExpansionNamespace
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                importPanel

                if queue.jobs.isEmpty {
                    emptyPanel
                } else {
                    if !completedURLs.isEmpty {
                        exportPanel
                    }
                    queueToolbar
                    jobList
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .background(Color.clear)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.movie, .audio, .data],
            allowsMultipleSelection: true
        ) { result in
            Task { await receive(result) }
        }
        .overlay(alignment: .top) {
            if let message { toast(message) }
        }
        .sensoryFeedback(.success, trigger: queue.completedCount)
    }

    private var header: some View {
        MonoPageHeader("转码")
    }

    private var importPanel: some View {
        Button { isImporting = true } label: {
            ZStack {
                LinearGradient(
                    colors: [MonoTheme.primary.opacity(0.18), MonoTheme.lavender.opacity(0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(MonoTheme.mint.opacity(0.22))
                    .frame(width: 210, height: 210)
                    .blur(radius: 52)
                    .offset(x: 150, y: -90)

                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("新建转码")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .tracking(-0.8)
                        Text("放入视频或音频")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(MonoTheme.muted(scheme))
                        HStack(spacing: 6) {
                            formatBadge("VIDEO")
                            formatBadge("AUDIO")
                            formatBadge("BATCH")
                        }
                    }
                    Spacer(minLength: 12)
                    ZStack {
                        Circle().fill(Color.white.opacity(0.72))
                        Circle().stroke(MonoTheme.primary.opacity(0.18), lineWidth: 1).padding(8)
                        Circle().fill(MonoTheme.primary).frame(width: 48, height: 48)
                        MonoIcon("plus", size: 19, weight: 2.3).foregroundStyle(.white)
                    }
                    .frame(width: 92, height: 92)
                }
                .padding(24)
            }
            .foregroundStyle(MonoTheme.ink(scheme))
            .frame(maxWidth: .infinity, minHeight: 190)
            .glassEffect(.regular.tint(MonoTheme.primary.opacity(0.08)).interactive(), in: .rect(cornerRadius: 34))
            .shadow(color: MonoTheme.primary.opacity(0.08), radius: 20, y: 10)
        }
        .buttonStyle(.plain)
    }

    private func formatBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .padding(.horizontal, 11)
            .frame(minHeight: 26)
            .glassEffect(.regular, in: .capsule)
    }

    private var emptyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoSectionHeader(title: "输出格式", detail: "本地处理")
            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    formatFamily("视频", detail: "MP4  MOV  MKV  WEBM", icon: "film", tint: MonoTheme.primary, width: 190)
                    formatFamily("音频", detail: "FLAC  WAV  MP3  OPUS", icon: "waveform", tint: MonoTheme.mint, width: 184)
                    formatFamily("编码", detail: "HEVC  H.264  AV1", icon: "bolt", tint: MonoTheme.coral, width: 164)
                    formatFamily("批量", detail: "MULTI  BACKGROUND", icon: "list.bullet.rectangle", tint: MonoTheme.cyan, width: 176)
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(16)
        .foregroundStyle(MonoTheme.ink(scheme))
        .monoPanel()
    }

    private func formatFamily(_ title: String, detail: String, icon: String, tint: Color, width: CGFloat) -> some View {
        HStack(spacing: 10) {
            MonoIcon(icon, size: 16, weight: 2)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Text(detail)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(MonoTheme.muted(scheme))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 13)
        .frame(width: width, alignment: .leading)
        .frame(minHeight: 64)
        .glassEffect(.regular.tint(tint.opacity(0.08)), in: .capsule)
    }

    private var queueToolbar: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(queue.isRunning ? "队列运行中" : "任务队列")
                        .font(.system(.headline, design: .rounded, weight: .black))
                    Text(queueSummary)
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(MonoTheme.muted(scheme))
                }
                Spacer(minLength: 8)
                if queue.failedCount > 0 || queue.completedCount > 0 {
                    Button { queue.clearFinished() } label: {
                        MonoIcon("xmark", size: 14, weight: 2.2)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MonoTheme.muted(scheme))
                    .accessibilityLabel("清除已结束任务")
                }
            }

            ProgressView(value: queue.overallProgress)
                .tint(MonoTheme.coral)

            Button {
                queue.isRunning ? queue.stop() : queue.start()
            } label: {
                MonoPrimaryButtonLabel(
                    title: queue.isRunning ? "完成当前项后停止" : "开始队列",
                    detail: queue.isRunning
                        ? "\(Int(queue.overallProgress * 100))%"
                        : "\(queue.waitingCount) WAITING",
                    symbol: queue.isRunning ? "pause.fill" : "play.fill",
                    isLoading: queue.isRunning
                )
            }
            .buttonStyle(.plain)
            .disabled(!queue.isRunning && queue.waitingCount == 0)
            .opacity(!queue.isRunning && queue.waitingCount == 0 ? 0.55 : 1)
        }
        .padding(16)
        .monoPanel()
    }

    private var exportPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                MonoIcon("square.and.arrow.up", size: 21, weight: 2.2)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.76))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("转码完成")
                        .font(.system(.headline, design: .rounded, weight: .black))
                    Text("\(completedURLs.count) 个文件可以导出")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(MonoTheme.muted(scheme))
                }
            }

            ShareLink(items: completedURLs) {
                HStack(spacing: 9) {
                    MonoIcon("square.and.arrow.up", size: 16, weight: 2.2)
                    Text(completedURLs.count == 1 ? "导出文件" : "导出全部")
                        .font(.system(.body, design: .rounded, weight: .black))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(MonoTheme.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(completedURLs.count == 1 ? "导出转码文件" : "导出全部转码文件")
        }
        .foregroundStyle(MonoTheme.ink(scheme))
        .padding(16)
        .background(MonoTheme.primary.opacity(0.12))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MonoTheme.primary.opacity(0.16), lineWidth: 1) }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var jobList: some View {
        LazyVStack(spacing: 12) {
            ForEach(queue.jobs) { job in
                jobRow(job)
            }
        }
    }

    private func jobRow(_ job: TranscodeJob) -> some View {
        let expanded = selectedJobID == job.id
        return VStack(spacing: 12) {
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.36, dampingFraction: 0.88)) {
                    selectedJobID = expanded ? nil : job.id
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(job.probe.hasVideo ? MonoTheme.stage : MonoTheme.ink(scheme))
                        MonoIcon(job.probe.hasVideo ? "film" : "waveform", size: 19, weight: 2.1)
                            .foregroundStyle(job.probe.hasVideo ? .white : MonoTheme.background(scheme))
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.title)
                            .font(.system(.subheadline, design: .rounded, weight: .black))
                            .lineLimit(1)
                        Text(job.detail)
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .foregroundStyle(MonoTheme.muted(scheme))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 5) {
                        statusBadge(job)
                        Text(job.target.pathExtension.uppercased())
                            .font(.system(.caption2, design: .monospaced, weight: .black))
                            .foregroundStyle(MonoTheme.muted(scheme))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MonoSpringPressStyle())

            if case .running = job.status {
                ProgressView(value: job.progress)
                    .tint(MonoTheme.coral)
            }

            if !expanded, case .completed(let url) = job.status {
                ShareLink(item: url) {
                    HStack(spacing: 8) {
                        MonoIcon("square.and.arrow.up", size: 15, weight: 2.2)
                        Text("导出此文件")
                            .font(.system(.subheadline, design: .rounded, weight: .black))
                        Spacer()
                        Text(job.target.pathExtension.uppercased())
                            .font(.system(.caption2, design: .monospaced, weight: .black))
                    }
                    .foregroundStyle(MonoTheme.stage)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 44)
                    .background(MonoTheme.stage.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("导出 \(job.title)")
            }

            if expanded {
                MonoHairline()
                    .matchedGeometryEffect(id: "job-divider-\(job.id)", in: jobExpansionNamespace)

                if case .failed(let reason) = job.status {
                    HStack(alignment: .top, spacing: 9) {
                        MonoIcon("exclamationmark.triangle", size: 14, weight: 2.1)
                            .padding(.top, 2)
                        Text(reason)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                MonoSelectionField(
                    title: "输出格式",
                    symbol: sectionIcon(job.target.section),
                    selection: targetBinding(for: job.id),
                    options: queue.availableTargets(for: job.probe).map { item in
                        MonoSelectionOption(
                            value: item,
                            title: item.title,
                            detail: item.detail,
                            symbol: sectionIcon(item.section)
                        )
                    },
                    layout: .detailed,
                    maxVisibleOptions: 6
                )

                rowActions(job)
            }
        }
        .foregroundStyle(MonoTheme.ink(scheme))
        .padding(12)
        .monoPanel()
        .animation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.38, dampingFraction: 0.9), value: expanded)
    }

    @ViewBuilder
    private func rowActions(_ job: TranscodeJob) -> some View {
        HStack(spacing: 10) {
            switch job.status {
            case .completed(let url):
                ShareLink(item: url) {
                    actionLabel("导出", symbol: "square.and.arrow.up")
                }
                .accessibilityLabel("共享转码文件")
            case .failed:
                Button { queue.retry(job.id) } label: {
                    actionLabel("重试", symbol: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            default:
                EmptyView()
            }

            Spacer(minLength: 8)

            if !queue.isRunning || queue.activeJobID != job.id {
                Button { queue.remove(job.id) } label: {
                    actionLabel("移除", symbol: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(MonoTheme.muted(scheme))
            }
        }
    }

    private func actionLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            MonoIcon(symbol, size: 14, weight: 2.1)
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .black))
        }
        .frame(minHeight: 38)
    }

    private func statusBadge(_ job: TranscodeJob) -> some View {
        let state = status(job)
        return HStack(spacing: 5) {
            MonoIcon(state.symbol, size: 12, weight: 2.1)
            Text(state.title)
        }
        .font(.system(.caption2, design: .rounded, weight: .black))
        .foregroundStyle(state.color)
        .padding(.horizontal, 9)
        .frame(minHeight: 26)
        .background(state.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func status(_ job: TranscodeJob) -> (title: String, symbol: String, color: Color) {
        switch job.status {
        case .waiting:
            return ("等待", "clock", MonoTheme.muted(scheme))
        case .running:
            return ("\(Int(job.progress * 100))%", "bolt.fill", MonoTheme.coral)
        case .completed:
            return ("完成", "checkmark", .green)
        case .failed:
            return ("失败", "exclamationmark.triangle", .orange)
        }
    }

    private var queueSummary: String {
        "\(queue.waitingCount) WAITING  ·  \(queue.failedCount) FAILED"
    }

    private var completedURLs: [URL] {
        queue.jobs.compactMap { job in
            guard case .completed(let url) = job.status else { return nil }
            return url
        }
    }

    private func sectionIcon(_ section: String) -> String {
        switch section {
        case "视频": "film"
        case "封装": "shippingbox"
        default: "waveform"
        }
    }

    private func targetBinding(for id: UUID) -> Binding<MediaTranscodeTarget> {
        Binding {
            queue.jobs.first(where: { $0.id == id })?.target ?? .hevcMP4
        } set: { newValue in
            queue.setTarget(newValue, for: id)
        }
    }

    @MainActor
    private func receive(_ result: Result<[URL], Error>) async {
        do {
            let selectedFiles = try result.get()
            guard !selectedFiles.isEmpty else { return }

            var importedCount = 0
            var failedCount = 0

            for selected in selectedFiles {
                do {
                    let local = try copyIntoWorkspace(selected)
                    let probe = try await MediaProbe.inspect(local)
                    do {
                        try queue.add(files: [(local, probe)])
                    } catch {
                        try? FileManager.default.removeItem(at: local)
                        throw error
                    }
                    selectedJobID = queue.jobs.last?.id
                    importedCount += 1
                } catch {
                    failedCount += 1
                }
            }

            if importedCount > 0 {
                show(failedCount > 0 ? "已导入 \(importedCount) 个，\(failedCount) 个失败" : "已导入 \(importedCount) 个")
            } else if failedCount > 0 {
                show("导入失败")
            }
        } catch {
            show(error.localizedDescription)
        }
    }

    private func copyIntoWorkspace(_ selected: URL) throws -> URL {
        let accessing = selected.startAccessingSecurityScopedResource()
        defer { if accessing { selected.stopAccessingSecurityScopedResource() } }

        try SharedStorage.prepare()
        let fileExtension = selected.pathExtension.isEmpty ? "media" : selected.pathExtension
        let local = SharedStorage.transcodeDirectory
            .appendingPathComponent("Input-\(UUID().uuidString).\(fileExtension)")
        try FileManager.default.copyItem(at: selected, to: local)
        return local
    }

    private func toast(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .rounded, weight: .bold))
            .foregroundStyle(MonoTheme.background(scheme))
            .padding(.horizontal, 16)
            .frame(minHeight: 42)
            .background(MonoTheme.ink(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func show(_ text: String) {
        withAnimation(.easeOut(duration: 0.18)) { message = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.18)) { message = nil }
        }
    }
}
