import SwiftUI
import UniformTypeIdentifiers

struct SignalTranscodeView: View {
    @StateObject private var queue = TranscodeQueue()
    @State private var presentsImporter = false
    @State private var importError: String?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: SignalSpace.lg) {
                SignalPageHeader(
                    title: "变成你要的",
                    detail: "一次选好，整队自动完成",
                    action: AnyView(
                        SignalIconButton(symbol: "plus", label: "添加媒体") { presentsImporter = true }
                    )
                )

                if queue.jobs.isEmpty {
                    emptyState
                        .youthStageEntrance()
                } else {
                    queueContent
                        .youthStageEntrance()
                }
            }
            .signalPagePadding()
            .padding(.bottom, 124)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .fileImporter(
            isPresented: $presentsImporter,
            allowedContentTypes: [.movie, .audio, .data],
            allowsMultipleSelection: true
        ) { result in
            Task { await receive(result) }
        }
        .alert("无法添加媒体", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("好", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "请稍后重试")
        }
    }

    private var emptyState: some View {
        VStack(spacing: SignalSpace.lg) {
            HStack(spacing: 0) {
                flowStep("输入", symbol: "tray.and.arrow.down", active: true)
                flowConnector
                flowStep("格式", symbol: "slider.horizontal.3", active: false)
                flowConnector
                flowStep("输出", symbol: "square.and.arrow.up", active: false)
            }

            Button { presentsImporter = true } label: {
                VStack(spacing: SignalSpace.md) {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 58, height: 58)
                        .background(SignalColor.acid)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    VStack(spacing: 6) {
                        Text("添加媒体")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                        Text("支持视频、音频与批量处理")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.52))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 280)
                .background(SignalColor.stage)
                .clipShape(YouthNotchedPanelShape(cornerRadius: 34, notchWidth: 94, notchDepth: 62))
                .overlay(alignment: .topTrailing) {
                    YouthStatusBubble(value: "AUTO", symbol: "bolt.fill")
                        .padding(8)
                }
            }
            .buttonStyle(SignalPressStyle())
        }
    }

    private var queueContent: some View {
        VStack(spacing: SignalSpace.md) {
            statusStrip

            SignalPanel {
                LazyVStack(spacing: 0) {
                    ForEach(Array(queue.jobs.enumerated()), id: \.element.id) { index, job in
                        jobRow(job)
                        if index < queue.jobs.count - 1 { SignalRule().padding(.leading, 60) }
                    }
                }
            }

            Button {
                queue.isRunning ? queue.stop() : queue.start()
            } label: {
                HStack {
                    Image(systemName: queue.isRunning ? "pause.fill" : "play.fill")
                    Text(queue.isRunning ? "完成当前项后停止" : "开始转码")
                    Spacer()
                    Text("\(queue.waitingCount) 待处理")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .opacity(0.72)
                }
                .font(.system(.headline, design: .rounded, weight: .bold))
                .padding(.horizontal, SignalSpace.md)
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(SignalPrimaryButtonStyle())
            .disabled(!queue.isRunning && queue.waitingCount == 0)
            .opacity(!queue.isRunning && queue.waitingCount == 0 ? 0.45 : 1)
        }
    }

    private var statusStrip: some View {
        VStack(spacing: SignalSpace.sm) {
            HStack {
                SignalStatus(
                    text: queue.isRunning ? "正在处理" : queue.completedCount > 0 ? "处理完成" : "等待开始",
                    kind: queue.isRunning ? .live : queue.completedCount > 0 ? .done : .ready
                )
                Spacer()
                Text("\(queue.completedCount) / \(queue.jobs.count)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(SignalColor.secondary(scheme))
            }
            ProgressView(value: queue.overallProgress)
                .tint(queue.isRunning ? SignalColor.acid : SignalColor.success)
        }
        .padding(SignalSpace.md)
        .foregroundStyle(.white)
        .background(SignalColor.stage)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func jobRow(_ job: TranscodeJob) -> some View {
        VStack(spacing: SignalSpace.sm) {
            HStack(spacing: SignalSpace.sm) {
                Image(systemName: job.probe.hasVideo ? "film" : "waveform")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(SignalColor.coral)
                    .frame(width: 36, height: 36)
                    .background(SignalColor.raised(scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title).font(.system(.body, design: .rounded, weight: .bold)).lineLimit(1)
                    Text(job.detail)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(SignalColor.secondary(scheme))
                        .lineLimit(1)
                }
                Spacer(minLength: SignalSpace.xs)
                statusLabel(job)
            }

            HStack(spacing: SignalSpace.sm) {
                Text("输出")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(SignalColor.secondary(scheme))

                Menu {
                    ForEach(queue.availableTargets(for: job.probe)) { target in
                        Button {
                            queue.setTarget(target, for: job.id)
                        } label: {
                            if target == job.target { Label(target.title, systemImage: "checkmark") }
                            else { Text(target.title) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(job.target.title)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(SignalColor.ink(scheme))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 34)
                    .background(SignalColor.raised(scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Spacer()

                if case .failed = job.status {
                    Button("重试") { queue.retry(job.id) }
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(SignalColor.coral)
                }
                Button(role: .destructive) { queue.remove(job.id) } label: {
                    Image(systemName: "trash").frame(width: 36, height: 36)
                }
                .disabled(isRunning(job))
                .opacity(isRunning(job) ? 0.35 : 1)
                .accessibilityLabel("移除 \(job.title)")
            }

            if isRunning(job) {
                ProgressView(value: job.progress).tint(SignalColor.coral)
            }
        }
        .padding(SignalSpace.md)
    }

    @ViewBuilder private func statusLabel(_ job: TranscodeJob) -> some View {
        switch job.status {
        case .waiting:
            SignalStatus(text: "等待", kind: .ready)
        case .running:
            Text("\(Int(job.progress * 100))%")
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundStyle(SignalColor.coral)
        case .completed:
            SignalStatus(text: "完成", kind: .done)
        case .failed:
            SignalStatus(text: "失败", kind: .warning)
        }
    }

    private func isRunning(_ job: TranscodeJob) -> Bool {
        if case .running = job.status { return true }
        return false
    }

    private func flowStep(_ title: String, symbol: String, active: Bool) -> some View {
        VStack(spacing: SignalSpace.xs) {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold))
            Text(title).font(.system(.caption, design: .rounded, weight: .bold))
        }
        .foregroundStyle(active ? SignalColor.ink(scheme) : SignalColor.secondary(scheme))
        .frame(width: 72)
        .frame(minHeight: 70)
    }

    private var flowConnector: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { context in
            GeometryReader { proxy in
                let phase = reduceMotion ? 0.5 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                ZStack(alignment: .leading) {
                    Rectangle().fill(SignalColor.rule(scheme)).frame(height: 1)
                    Rectangle()
                        .fill(SignalColor.coral)
                        .frame(width: 18, height: 3)
                        .offset(x: max(0, (proxy.size.width - 18) * phase))
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }

    @MainActor private func receive(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            for source in urls {
                let access = source.startAccessingSecurityScopedResource()
                defer { if access { source.stopAccessingSecurityScopedResource() } }

                try SharedStorage.prepare()
                let fileExtension = source.pathExtension.isEmpty ? "media" : source.pathExtension
                let target = SharedStorage.transcodeDirectory.appendingPathComponent("Input-\(UUID().uuidString).\(fileExtension)")
                try FileManager.default.copyItem(at: source, to: target)
                let probe = try await MediaProbe.inspect(target)
                try queue.add(files: [(target, probe)])
            }
        } catch {
            importError = error.localizedDescription
        }
    }
}
