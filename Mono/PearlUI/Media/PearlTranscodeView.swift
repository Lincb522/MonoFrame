import SwiftUI
import UniformTypeIdentifiers

struct PearlTranscodeView: View {
    @StateObject private var model = PearlTranscodeModel()
    @State private var selectingFormat: TranscodeJob?
    @State private var stopRequested = false
    @Environment(\.colorScheme) private var scheme
    private var pending: [TranscodeJob] { model.queue.jobs.filter { if case .completed = $0.status { return false }; return true } }
    private var completed: [TranscodeJob] { model.queue.jobs.filter { if case .completed = $0.status { return true }; return false } }
    var body: some View {
        PearlPage {
            VStack(alignment: .leading, spacing: 20) {
                PearlRootHeader(title: "转码") {
                    PearlIconButton(title: "添加转码文件", glyph: .plus, filled: true) { model.isImporting = true }
                        .accessibilityIdentifier("pearl.transcode.add")
                }
                PearlCountHeading(count: model.queue.jobs.count, label: "个转码任务")
                PearlHairline()
                if model.queue.jobs.isEmpty {
                    PearlEmptyState(glyph: .transcode, title: "选择文件，转换格式", message: "视频与音频可以一起加入队列。")
                    Button { model.isImporting = true } label: { PearlPrimaryLabel(title: "添加文件", glyph: .plus) }
                        .buttonStyle(PearlPressStyle())
                }
                if !pending.isEmpty {
                    sectionTitle("待处理", pending.count)
                    LazyVStack(spacing: 14) { ForEach(pending) { row($0) } }
                }
                if !completed.isEmpty {
                    sectionTitle("已完成", completed.count)
                    LazyVStack(spacing: 14) { ForEach(completed) { row($0) } }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.queue.isRunning || model.queue.waitingCount > 0 {
                Button {
                    if model.queue.isRunning { stopRequested = true; model.queue.stop() }
                    else { model.queue.start() }
                } label: {
                    PearlPrimaryLabel(title: model.queue.isRunning ? (stopRequested ? "当前文件完成后停止" : "处理完当前文件后停止") : "开始转码 · \(model.queue.waitingCount) 个文件", glyph: model.queue.isRunning ? .stop : .play)
                }.buttonStyle(PearlPressStyle()).disabled(stopRequested)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .accessibilityIdentifier("pearl.transcode.start")
            }
        }
        .fileImporter(isPresented: $model.isImporting, allowedContentTypes: [.movie, .audio, .data], allowsMultipleSelection: true) { result in
            Task { await model.receive(result) }
        }
        .sheet(item: $selectingFormat) { job in
            PearlFormatPicker(job: job, targets: model.queue.availableTargets(for: job.probe)) { target in
                model.queue.setTarget(target, for: job.id)
            }
        }
        .alert("无法加入任务", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "请重新选择文件。") }
        .onChange(of: model.queue.isRunning) { _, running in if !running { stopRequested = false } }
        .task {
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if env["MONO_UI_TEST"] == "1", let name = env["MONO_TEST_TRANSCODE_FILE"], model.queue.jobs.isEmpty {
                await model.receive(.success([SharedStorage.audioDirectory.appendingPathComponent(name)]))
            }
            #endif
        }

    }
    private func sectionTitle(_ title: String, _ count: Int) -> some View {
        HStack(spacing: 8) { Text(title).font(.headline); Text("\(count)").font(.subheadline).foregroundStyle(PearlColor.secondary(scheme)) }
    }
    private func row(_ job: TranscodeJob) -> some View {
        PearlTranscodeJobView(job: job, selectFormat: { selectingFormat = job }, retry: { model.queue.retry(job.id) }, remove: { model.queue.remove(job.id) })
    }
}

private struct PearlTranscodeJobView: View {
    let job: TranscodeJob
    let selectFormat: () -> Void
    let retry: () -> Void
    let remove: () -> Void
    @State private var export: PearlExportItem?
    @Environment(\.colorScheme) private var scheme
    private var running: Bool { if case .running = job.status { return true }; return false }
    private var output: URL? { if case .completed(let url) = job.status { return url }; return nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 13) {
                PearlThumbnail(url: output ?? job.inputURL, isVideo: job.probe.hasVideo).frame(width: 66, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 6) {
                    Text((output ?? job.inputURL).lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(job.inputURL.pathExtension.uppercased() + " · " + durationText).font(.caption).foregroundStyle(PearlColor.secondary(scheme))
                }.frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button("移除任务", role: .destructive, action: remove).disabled(running)
                } label: { PearlGlyph(.more, size: 18).frame(width: 44, height: 44) }
                    .accessibilityLabel("任务操作")
            }
            if let output {
                HStack(spacing: 7) { PearlGlyph(.check, size: 17); Text("转码完成").font(.caption.weight(.medium)) }
                    .foregroundStyle(PearlColor.accent(scheme)).accessibilityIdentifier("pearl.transcode.completed")
                HStack(spacing: 10) {
                    Button { export = PearlExportItem(url: output) } label: { PearlPrimaryLabel(title: "导出文件", glyph: .export) }
                        .buttonStyle(PearlPressStyle()).accessibilityIdentifier("pearl.transcode.export")
                    ShareLink(item: output) {
                        Label { Text("分享") } icon: { PearlGlyph(.share, size: 18) }
                            .font(.subheadline.weight(.medium)).frame(minWidth: 90, minHeight: 54)
                            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(PearlColor.hairline(scheme), lineWidth: 1) }
                    }.buttonStyle(PearlPressStyle())
                }
            } else {
                Button(action: selectFormat) {
                    HStack(spacing: 10) {
                        Text("输出格式").foregroundStyle(PearlColor.secondary(scheme))
                        Spacer(minLength: 8)
                        Text(job.target.title).multilineTextAlignment(.trailing)
                        PearlGlyph(.chevronRight, size: 12).rotationEffect(.degrees(90))
                    }.font(.caption).padding(12).frame(minHeight: 48)
                        .background(PearlColor.elevated(scheme).opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(PearlPressStyle()).disabled(running).accessibilityLabel("输出格式，\(job.target.pathExtension)，\(job.target.title)")
                    .accessibilityIdentifier("pearl.transcode.format")
            }
            if running {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(job.progress * 100))%").font(.system(size: 48, weight: .bold)).monospacedDigit()
                        .foregroundStyle(PearlColor.display(scheme))
                    Text("正在转码").font(.subheadline)
                }
                PearlDotMatrix(progress: job.progress, columns: 20, rows: 2, active: true).frame(height: 36)
                ProgressView(value: job.progress).tint(PearlColor.accent(scheme)).accessibilityLabel("转码进度")
            }
            if case .failed(let message) = job.status {
                PearlInlineNotice(message: message, tone: .error)
                Button("重试", action: retry).frame(minHeight: 44)
            }
        }
        .foregroundStyle(PearlColor.ink(scheme)).padding(14)
        .background(PearlColor.surface(scheme), in: RoundedRectangle(cornerRadius: 12))
        .sheet(item: $export) { PearlFileExporter(url: $0.url) }
    }
    private var durationText: String { let s = max(0, Int(job.probe.duration)); return String(format: "%02d:%02d", s / 60, s % 60) }
}

private struct PearlFormatPicker: View {
    let job: TranscodeJob
    let targets: [MediaTranscodeTarget]
    let select: (MediaTranscodeTarget) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        PearlSecondaryLayout(title: "输出格式") {
            PearlPage {
                VStack(spacing: 14) {
                    TextField("搜索格式或编码", text: $query).textFieldStyle(.roundedBorder).frame(minHeight: 44)
                    ForEach(targets.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.pathExtension.localizedCaseInsensitiveContains(query) }) { target in
                        Button { select(target); dismiss() } label: {
                            HStack {
                                PearlGlyph(.format, size: 24).frame(width: 36)
                                VStack(alignment: .leading, spacing: 3) { Text(target.title); Text(target.detail).font(.caption).foregroundStyle(PearlColor.secondary(scheme)) }
                                Spacer()
                                if target == job.target { PearlGlyph(.check, size: 20) }
                            }.frame(minHeight: 58).foregroundStyle(PearlColor.ink(scheme))
                        }.buttonStyle(PearlPressStyle()).accessibilityAddTraits(target == job.target ? .isSelected : [])
                        PearlHairline()
                    }
                }
            }
        }.presentationDragIndicator(.visible)
    }
}
