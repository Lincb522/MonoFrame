import SwiftUI
import UniformTypeIdentifiers

struct RailAudioRecorderView: View {
    enum Mode: String, CaseIterable { case voice = "纯人声"; case session = "混音录制" }

    @StateObject private var recorder = AudioRecordingService()
    @State private var mode: Mode = .voice
    @State private var message: String?
    @State private var importingAudio = false
    @State private var importingLyrics = false
    @State private var showingLyrics = false
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RailBackground()
            ScrollView {
                VStack(spacing: 22) {
                    RailPageHeader(title: "声音采集") {
                        RailIconButton(symbol: "xmark", title: nil) { close() }
                    }
                    RailSegmented(values: Mode.allCases.map { ($0, $0.rawValue) }, selection: $mode)
                        .disabled(recorder.isBusy)
                    recorderStage
                        .railEntrance(delay: 0.04)
                    if !recorder.isActive {
                        inputControls
                            .railEntrance(delay: 0.08)
                        if mode == .session {
                            sessionControls
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                }
                .railPagePadding()
                .padding(.bottom, 32)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $importingAudio, allowedContentTypes: [.audio], allowsMultipleSelection: false) { importAudio($0) }
        .fileImporter(isPresented: $importingLyrics, allowedContentTypes: lyricTypes, allowsMultipleSelection: false) { importLyrics($0) }
        .sheet(isPresented: $showingLyrics) { RailLyricsReader(lines: recorder.lyricLines, currentIndex: recorder.currentLyricIndex) }
        .overlay(alignment: .top) { if let message { RailToast(message: message) } }
        .sensoryFeedback(.impact(weight: .medium), trigger: recorder.isActive)
    }

    private var recorderStage: some View {
        VStack(spacing: 0) {
            HStack {
                RailStatus(text: recorder.isActive ? "RECORDING" : "READY", tint: recorder.isActive ? RailColor.coral : RailColor.mint)
                Spacer()
                Text("48 KHZ / \(recorder.captureMode.rawValue)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.60))
            }
            .padding(.horizontal, 17)
            .frame(height: 58)

            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)

            VStack(spacing: 20) {
                RailWaveform(samples: recorder.levels, tint: RailColor.coral)
                    .frame(height: mode == .voice ? 132 : 92)

                Text(timeText)
                    .font(.system(size: 48, weight: .medium, design: .monospaced))
                    .tracking(-2)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                if mode == .session, recorder.hasLyrics {
                    Button { showingLyrics = true } label: {
                        VStack(spacing: 5) {
                            Text(recorder.currentLyric?.text ?? "准备")
                                .font(.system(.headline, design: .rounded, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Text(recorder.nextLyric?.text ?? "轻触查看全部歌词")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(stateText)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.white.opacity(0.48))
                }

                HStack(spacing: 28) {
                    Button { recorder.togglePause() } label: {
                        RailGlyph(systemName: recorder.state == .paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(.white.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .disabled(!recorder.isActive)

                    Button {
                        if recorder.isActive { finish() }
                        else { Task { await recorder.start(includeSessionMedia: mode == .session) } }
                    } label: {
                        ZStack {
                            Circle().stroke(.white.opacity(0.22), lineWidth: 9).frame(width: 94, height: 94)
                            Circle().stroke(.white.opacity(0.72), lineWidth: 2).frame(width: 78, height: 78)
                            if recorder.isBusy && !recorder.isActive {
                                ProgressView().tint(.white)
                            } else {
                                RoundedRectangle(cornerRadius: recorder.isActive ? 10 : 32, style: .continuous)
                                    .fill(RailColor.coral)
                                    .frame(width: recorder.isActive ? 42 : 64, height: recorder.isActive ? 42 : 64)
                            }
                        }
                    }
                    .buttonStyle(RailPressStyle())
                    .disabled(recorder.isBusy && !recorder.isActive)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.30), value: recorder.isActive)
                    .accessibilityLabel(recorder.isActive ? "停止录音" : "开始录音")

                    Color.clear.frame(width: 50, height: 50)
                }
            }
            .padding(20)
        }
        .background(Color(red: 0.055, green: 0.06, blue: 0.075))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .top) { Rectangle().fill(RailColor.coral).frame(height: 3) }
    }

    private var inputControls: some View {
        VStack(spacing: 11) {
            RailSectionTitle(title: "输入路由")
            RailSurface {
                VStack(spacing: 15) {
                    RailSegmented(values: AudioCaptureMode.allCases.map { ($0, $0.rawValue) }, selection: $recorder.captureMode)
                    if recorder.captureMode != .headphones {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("扬声器处理").font(.caption.bold()).foregroundStyle(RailColor.secondary(scheme))
                            RailSegmented(values: SpeakerProcessingStrength.allCases.map { ($0, $0.rawValue) }, selection: $recorder.speakerProcessingStrength)
                        }
                    }
                }
                .padding(15)
            }
        }
    }

    private var sessionControls: some View {
        VStack(spacing: 11) {
            RailSectionTitle(title: "素材", detail: recorder.hasAccompaniment ? "SYNCED" : "EMPTY")
            RailSurface {
                VStack(spacing: 0) {
                    mediaRow(
                        title: "伴奏文件",
                        detail: recorder.accompanimentName ?? "选择音频文件",
                        symbol: "music.note",
                        active: recorder.hasAccompaniment,
                        action: { importingAudio = true },
                        clear: recorder.clearAccompaniment
                    )
                    RailHairline().padding(.leading, 62)
                    mediaRow(
                        title: "歌词",
                        detail: recorder.lyricsName ?? "LRC / QLRC / TXT",
                        symbol: "text.quote",
                        active: recorder.hasLyrics,
                        action: { importingLyrics = true },
                        clear: recorder.clearLyrics
                    )
                    if recorder.hasAccompaniment {
                        RailHairline()
                        VStack(spacing: 12) {
                            volume("伴奏音量", value: $recorder.accompanimentVolume)
                            volume("人声音量", value: $recorder.vocalVolume)
                            HStack {
                                Text("人声同步").font(.caption.bold())
                                Slider(value: $recorder.vocalSyncAdjustmentMilliseconds, in: -500...500, step: 10).tint(RailColor.coral)
                                Text(String(format: "%+.0f ms", recorder.vocalSyncAdjustmentMilliseconds))
                                    .font(.caption2.monospaced().bold()).foregroundStyle(RailColor.coral).frame(width: 62)
                            }
                        }
                        .padding(15)
                    }
                }
            }
        }
    }

    private func mediaRow(
        title: String,
        detail: String,
        symbol: String,
        active: Bool,
        action: @escaping () -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 13) {
            Button(action: action) {
                HStack(spacing: 13) {
                    RailGlyph(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(active ? .white : RailColor.coral)
                        .frame(width: 38, height: 38).background(active ? RailColor.coral : RailColor.coral.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(.body, design: .rounded, weight: .bold))
                        Text(detail).font(.caption).foregroundStyle(RailColor.secondary(scheme)).lineLimit(1)
                    }
                    Spacer()
                }
                .foregroundStyle(RailColor.ink(scheme))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if active {
                Button(action: clear) { RailGlyph(systemName: "xmark.circle.fill").foregroundStyle(RailColor.secondary(scheme)).frame(width: 44, height: 44) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 66)
    }

    private func volume(_ title: String, value: Binding<Double>) -> some View {
        HStack { Text(title).font(.caption.bold()).frame(width: 62, alignment: .leading); Slider(value: value, in: 0...1).tint(RailColor.coral) }
    }

    private var stateText: String {
        switch recorder.state {
        case .idle: "轻触开始录音"
        case .recording: "录制中"
        case .paused: "已暂停"
        case .processing: "优化人声中"
        case .mixing: "正在混音"
        case .failed(let error): error
        }
    }

    private var timeText: String {
        let seconds = max(0, Int(recorder.elapsed))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var lyricTypes: [UTType] {
        var result: [UTType] = [.plainText, .utf8PlainText]
        for ext in LyricDocumentCodec.supportedFileExtensions where ext != "txt" {
            if let type = UTType(filenameExtension: ext), !result.contains(type) { result.append(type) }
        }
        return result
    }

    private func finish() {
        Task {
            guard await recorder.stop() != nil else { return }
            await library.reload()
            show("录音已保存")
        }
    }

    private func close() {
        Task {
            if recorder.isActive { _ = await recorder.stop(); await library.reload() }
            dismiss()
        }
    }

    private func importAudio(_ result: Result<[URL], Error>) {
        do { if let url = try result.get().first { try recorder.importAccompaniment(from: url) } }
        catch { show(error.localizedDescription) }
    }

    private func importLyrics(_ result: Result<[URL], Error>) {
        do { if let url = try result.get().first { try recorder.importLyrics(from: url); show("歌词已导入") } }
        catch { show(error.localizedDescription) }
    }

    private func show(_ text: String) {
        withAnimation(.easeOut(duration: 0.16)) { message = text }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.16)) { message = nil }
        }
    }
}

private struct RailLyricsReader: View {
    let lines: [LyricLine]
    let currentIndex: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                Text(time(line.time)).font(.caption2.monospaced().bold()).foregroundStyle(RailColor.secondary(scheme)).frame(width: 42, alignment: .trailing)
                                Text(line.text)
                                    .font(.system(index == currentIndex ? .title3 : .body, design: .rounded, weight: index == currentIndex ? .bold : .medium))
                                    .foregroundStyle(index == currentIndex ? RailColor.coral : RailColor.ink(scheme))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id(index)
                        }
                    }
                    .padding(20)
                }
                .onChange(of: currentIndex) { _, index in if let index { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(index, anchor: .center) } } }
            }
            .background(RailBackground())
            .navigationTitle("歌词轨")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() }.foregroundStyle(RailColor.coral) } }
        }
        .presentationDetents([.medium, .large])
    }

    private func time(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "" }
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
