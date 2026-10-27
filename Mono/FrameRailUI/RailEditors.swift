import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers

private enum RailVideoTool: String, CaseIterable, Identifiable {
    case cut = "剪切"
    case speed = "变速"
    case look = "画面"
    case sound = "声音"
    case text = "文字"
    case export = "格式"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .cut: "scissors"
        case .speed: "speedometer"
        case .look: "camera.filters"
        case .sound: "speaker.wave.2"
        case .text: "textformat"
        case .export: "doc.text"
        }
    }
}

struct RailVideoEditorView: View {
    let recording: Recording
    @StateObject private var editor: VideoEditor
    @State private var player: AVPlayer
    @State private var activeTool: RailVideoTool = .cut
    @State private var playhead: Double
    @State private var isPlaying = false
    @State private var timeObserver: Any?
    @State private var outputURL: URL?
    @State private var message: String?
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    init(recording: Recording) {
        self.recording = recording
        let model = VideoEditor(sourceURL: recording.url, duration: recording.duration)
        _editor = StateObject(wrappedValue: model)
        _player = State(initialValue: AVPlayer(url: recording.url))
        _playhead = State(initialValue: model.trimStart)
    }

    var body: some View {
        ZStack {
            RailBackground()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    preview
                    timeline
                    toolRail
                    toolPanel
                    exportButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 36)
                .frame(maxWidth: 960)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { if let message { RailToast(message: message) } }
        .task { await editor.loadFFmpegPreview() }
        .onAppear { installObserver() }
        .onDisappear { player.pause(); removeObserver() }
        .onChange(of: editor.selectedClipID) { _, _ in
            player.replaceCurrentItem(with: AVPlayerItem(url: editor.selectedSourceURL))
            playhead = editor.trimStart
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            RailIconButton(symbol: "xmark", title: nil) { dismiss() }
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title).font(.system(.headline, design: .rounded, weight: .bold)).lineLimit(1)
                Text("VIDEO PROJECT · \(editor.clips.count) TRACK\(editor.clips.count == 1 ? "" : "S")")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(RailColor.secondary(scheme))
            }
            Spacer()
            Button { editor.undo() } label: { RailGlyph(systemName: "arrow.uturn.backward").frame(width: 42, height: 42) }
                .disabled(!editor.canUndo)
            Button { editor.redo() } label: { RailGlyph(systemName: "arrow.uturn.forward").frame(width: 42, height: 42) }
                .disabled(!editor.canRedo)
        }
        .foregroundStyle(RailColor.ink(scheme))
    }

    private var preview: some View {
        ZStack(alignment: .bottom) {
            Color.black
            VideoPlayer(player: player)
                .aspectRatio(16 / 9, contentMode: .fit)
            HStack {
                Button { togglePlayback() } label: {
                    RailGlyph(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                }
                Text(editor.timecode(playhead)).font(.caption.monospaced().bold()).foregroundStyle(.white)
                Spacer()
                Text(editor.technicalSummary ?? "\(Int(editor.frameRate.rounded())) FPS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .background(.black.opacity(0.58))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var timeline: some View {
        VStack(spacing: 10) {
            HStack {
                Text("TIMELINE").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(RailColor.secondary(scheme))
                Spacer()
                Text(editor.timecode(editor.projectDuration)).font(.caption.monospaced().bold()).foregroundStyle(RailColor.secondary(scheme))
            }
            RailTimelineTicks(count: 25, tint: RailColor.coral)
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(editor.clips) { clip in
                        Button { editor.selectClip(clip.id); playhead = clip.start } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(clip.id == editor.selectedClipID ? RailColor.blue : RailColor.blue.opacity(0.34))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(clip.name).lineLimit(1)
                                    Text(String(format: "%.1fs", clip.timelineDuration)).font(.caption2.monospaced())
                                }
                                .font(.caption.bold()).foregroundStyle(.white).padding(9).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(width: max(92, min(220, CGFloat(clip.timelineDuration) * 24)), height: 58)
                        }
                        .buttonStyle(RailPressStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)
            Slider(value: $playhead, in: 0...max(editor.duration, 0.1), step: editor.frameDuration)
                .tint(RailColor.coral)
                .onChange(of: playhead) { _, value in seek(value) }
        }
        .padding(14)
        .background(RailColor.surface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var toolRail: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(RailVideoTool.allCases) { tool in
                    Button { withAnimation(.smooth(duration: 0.24)) { activeTool = tool } } label: {
                        RailLabel(tool.rawValue, systemImage: tool.symbol)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(activeTool == tool ? RailColor.onSelection(scheme) : RailColor.secondary(scheme))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 42)
                            .background(activeTool == tool ? RailColor.selection(scheme) : RailColor.surface(scheme))
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(RailPressStyle())
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private var toolPanel: some View {
        RailSurface {
            switch activeTool {
            case .cut: cutPanel
            case .speed: speedPanel
            case .look: lookPanel
            case .sound: soundPanel
            case .text: textPanel
            case .export: exportPanel
            }
        }
    }

    private var cutPanel: some View {
        VStack(spacing: 14) {
            toolHeader("片段剪切", detail: "逐帧微调入点和出点")
            boundary("入点", value: Binding(get: { editor.trimStart }, set: { editor.setTrimStart($0) }))
            boundary("出点", value: Binding(get: { editor.trimEnd }, set: { editor.setTrimEnd($0) }))
            HStack(spacing: 8) {
                toolButton("分割", "scissors") { _ = editor.split(at: playhead) }
                toolButton("复制", "plus.square.on.square") { editor.duplicateSelectedClip() }
                toolButton("删除", "trash") { editor.deleteSelectedClip() }.disabled(!editor.canDeleteClip)
            }
        }
        .padding(15)
    }

    private var speedPanel: some View {
        VStack(spacing: 14) {
            toolHeader("播放速度", detail: String(format: "%.2fx", editor.speed))
            Slider(value: $editor.speed, in: 0.25...4, step: 0.05).tint(RailColor.coral)
            HStack(spacing: 8) {
                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { value in
                    Button("\(value, specifier: "%.1f")x") { editor.speed = value }
                        .font(.caption.bold()).foregroundStyle(editor.speed == value ? .white : RailColor.ink(scheme))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(editor.speed == value ? RailColor.coral : RailColor.raised(scheme)).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(15)
    }

    private var lookPanel: some View {
        VStack(spacing: 14) {
            toolHeader("画面调校", detail: editor.look.rawValue)
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(VideoLook.allCases) { look in
                        Button(look.rawValue) { editor.apply(look) }
                            .font(.caption.bold()).foregroundStyle(editor.look == look ? .white : RailColor.ink(scheme))
                            .padding(.horizontal, 12).frame(minHeight: 38)
                            .background(editor.look == look ? RailColor.blue : RailColor.raised(scheme)).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            adjustment("亮度", value: $editor.brightness, range: -1...1)
            adjustment("对比度", value: $editor.contrast, range: 0.5...1.5)
            adjustment("饱和度", value: $editor.saturation, range: 0...2)
        }
        .padding(15)
    }

    private var soundPanel: some View {
        VStack(spacing: 14) {
            toolHeader("片段声音", detail: editor.isMuted ? "MUTED" : "ACTIVE")
            Toggle("静音", isOn: $editor.isMuted).tint(RailColor.coral)
            adjustment("音量", value: $editor.volume, range: 0...2)
            adjustment("淡入", value: $editor.fadeIn, range: 0...5)
            adjustment("淡出", value: $editor.fadeOut, range: 0...5)
        }
        .padding(15)
    }

    private var textPanel: some View {
        VStack(spacing: 14) {
            toolHeader("画面文字", detail: "OVERLAY")
            TextField("输入叠加文字", text: $editor.overlayText, axis: .vertical)
                .padding(12).background(RailColor.raised(scheme)).clipShape(RoundedRectangle(cornerRadius: 10))
            RailSegmented(values: VideoTextPosition.allCases.map { ($0, $0.rawValue) }, selection: $editor.overlayPosition)
            adjustment("透明度", value: $editor.overlayOpacity, range: 0.2...1)
        }
        .padding(15)
    }

    private var exportPanel: some View {
        VStack(spacing: 14) {
            toolHeader("输出设置", detail: outputURL == nil ? "NOT EXPORTED" : "READY")
            RailSegmented(values: VideoExportSize.allCases.map { ($0, $0.rawValue) }, selection: $editor.exportSize)
            RailSegmented(values: VideoExportCodec.allCases.map { ($0, $0.rawValue) }, selection: $editor.exportCodec)
            if editor.isExporting { ProgressView(value: editor.exportProgress).tint(RailColor.coral) }
            if let outputURL { ShareLink(item: outputURL) { RailLabel("分享文件", systemImage: "arrow.up.right").frame(maxWidth: .infinity, minHeight: 46) }.buttonStyle(RailPrimaryButtonStyle(tint: RailColor.blue)) }
        }
        .padding(15)
    }

    private var exportButton: some View {
        Button { export() } label: {
            HStack {
                if editor.isExporting { ProgressView().tint(.white) }
                else { RailGlyph(systemName: "arrow.up.forward.app.fill") }
                Text(editor.isExporting ? "正在导出 \(Int(editor.exportProgress * 100))%" : "导出视频")
                Spacer()
                Text(editor.timecode(editor.projectDuration)).font(.caption.monospaced().bold()).opacity(0.7)
            }
            .font(.system(.headline, design: .rounded, weight: .bold)).padding(.horizontal, 17).frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(RailPrimaryButtonStyle())
        .disabled(editor.isExporting)
    }

    private func toolHeader(_ title: String, detail: String) -> some View {
        HStack { Text(title).font(.system(.headline, design: .rounded, weight: .bold)); Spacer(); Text(detail).font(.caption.monospaced().bold()).foregroundStyle(RailColor.secondary(scheme)) }
    }

    private func boundary(_ title: String, value: Binding<Double>) -> some View {
        HStack { Text(title).font(.caption.bold()).frame(width: 32); Slider(value: value, in: 0...max(editor.duration, 0.1), step: editor.frameDuration).tint(RailColor.coral); Text(editor.timecode(value.wrappedValue)).font(.caption2.monospaced()).frame(width: 58) }
    }

    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack { Text(title).font(.caption.bold()).frame(width: 48, alignment: .leading); Slider(value: value, in: range).tint(RailColor.coral); Text(String(format: "%.2f", value.wrappedValue)).font(.caption2.monospaced()).frame(width: 40) }
    }

    private func toolButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { RailLabel(title, systemImage: symbol).font(.caption.bold()).foregroundStyle(RailColor.ink(scheme)).frame(maxWidth: .infinity, minHeight: 42).background(RailColor.raised(scheme)).clipShape(RoundedRectangle(cornerRadius: 10)) }
            .buttonStyle(RailPressStyle())
    }

    private func togglePlayback() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    private func seek(_ time: Double) {
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func installObserver() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.10, preferredTimescale: 600), queue: .main) { time in
            Task { @MainActor in if isPlaying { playhead = min(editor.duration, max(0, time.seconds)) } }
        }
    }

    private func removeObserver() {
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
    }

    private func export() {
        Task {
            do {
                let url = try await editor.export()
                outputURL = url
                await library.reload()
                show("视频已导出")
            } catch { show(error.localizedDescription) }
        }
    }

    private func show(_ text: String) {
        message = text
        Task { try? await Task.sleep(for: .seconds(2)); message = nil }
    }
}

private enum RailAudioTool: String, CaseIterable, Identifiable {
    case cut = "剪切"; case tone = "音色"; case smart = "智能"; case lyrics = "歌词"; case export = "格式"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .cut: "scissors"; case .tone: "slider.vertical.3"; case .smart: "wand.and.stars"; case .lyrics: "text.quote"; case .export: "doc.text"
        }
    }
}

struct RailAudioEditorView: View {
    let recording: AudioRecording
    @StateObject private var editor: AudioEditor
    @State private var player: AVPlayer
    @State private var activeTool: RailAudioTool = .cut
    @State private var playhead = 0.0
    @State private var isPlaying = false
    @State private var timeObserver: Any?
    @State private var outputURL: URL?
    @State private var message: String?
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    init(recording: AudioRecording) {
        self.recording = recording
        _editor = StateObject(wrappedValue: AudioEditor(sourceURL: recording.url, duration: recording.duration))
        _player = State(initialValue: AVPlayer(url: recording.url))
    }

    var body: some View {
        ZStack {
            RailBackground()
            ScrollView {
                VStack(spacing: 16) {
                    audioHeader
                    audioStage
                    audioToolRail
                    audioToolPanel
                    audioExportButton
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 36)
                .frame(maxWidth: 900).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { if let message { RailToast(message: message) } }
        .task { await editor.loadWaveform() }
        .onAppear { installAudioObserver() }
        .onDisappear { player.pause(); removeAudioObserver() }
    }

    private var audioHeader: some View {
        HStack(spacing: 10) {
            RailIconButton(symbol: "xmark", title: nil) { dismiss() }
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title).font(.system(.headline, design: .rounded, weight: .bold))
                Text("AUDIO PROJECT · \(recording.formatText)").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(RailColor.secondary(scheme))
            }
            Spacer()
            Button { editor.undo() } label: { RailGlyph(systemName: "arrow.uturn.backward").frame(width: 42, height: 42) }.disabled(!editor.canUndo)
            Button { editor.redo() } label: { RailGlyph(systemName: "arrow.uturn.forward").frame(width: 42, height: 42) }.disabled(!editor.canRedo)
        }
        .foregroundStyle(RailColor.ink(scheme))
    }

    private var audioStage: some View {
        VStack(spacing: 16) {
            HStack {
                RailStatus(text: isPlaying ? "PLAYING" : "PAUSED", tint: isPlaying ? RailColor.coral : RailColor.mint)
                Spacer()
                Text(timecode(playhead)).font(.caption.monospaced().bold()).foregroundStyle(.white.opacity(0.68))
            }
            RailWaveform(samples: editor.waveform, tint: RailColor.coral, playhead: max(0, min(1, playhead / max(editor.duration, 0.1))))
                .frame(height: 124)
            RailTimelineTicks(count: 26, tint: RailColor.coral)
            Slider(value: $playhead, in: 0...max(editor.duration, 0.1), step: 0.01).tint(RailColor.coral)
                .onChange(of: playhead) { _, value in player.seek(to: CMTime(seconds: value, preferredTimescale: 600)) }
            HStack {
                Button { playhead = max(0, playhead - 5) } label: { RailGlyph(systemName: "gobackward.5").frame(width: 44, height: 44) }
                Spacer()
                Button { toggleAudio() } label: {
                    RailGlyph(systemName: isPlaying ? "pause.fill" : "play.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 60, height: 60).background(RailColor.coral).clipShape(Circle())
                }
                .buttonStyle(RailPressStyle())
                Spacer()
                Button { playhead = min(editor.duration, playhead + 5) } label: { RailGlyph(systemName: "goforward.5").frame(width: 44, height: 44) }
            }
            .foregroundStyle(.white)
        }
        .padding(16)
        .background(Color(red: 0.055, green: 0.06, blue: 0.075))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .top) { Rectangle().fill(RailColor.coral).frame(height: 3) }
    }

    private var audioToolRail: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(RailAudioTool.allCases) { tool in
                    Button { activeTool = tool } label: {
                        RailLabel(tool.rawValue, systemImage: tool.symbol).font(.caption.bold())
                            .foregroundStyle(activeTool == tool ? RailColor.onSelection(scheme) : RailColor.secondary(scheme))
                            .padding(.horizontal, 12).frame(minHeight: 42)
                            .background(activeTool == tool ? RailColor.selection(scheme) : RailColor.surface(scheme)).clipShape(RoundedRectangle(cornerRadius: 11))
                    }.buttonStyle(RailPressStyle())
                }
            }
        }.scrollIndicators(.hidden)
    }

    @ViewBuilder private var audioToolPanel: some View {
        RailSurface {
            switch activeTool {
            case .cut: audioCutPanel
            case .tone: audioTonePanel
            case .smart: audioSmartPanel
            case .lyrics: audioLyricsPanel
            case .export: audioExportPanel
            }
        }
    }

    private var audioCutPanel: some View {
        VStack(spacing: 14) {
            panelHeader("片段剪切", "\(editor.clips.count) CLIPS")
            audioBoundary("入点", Binding(get: { editor.trimStart }, set: { editor.setTrimStart($0) }))
            audioBoundary("出点", Binding(get: { editor.trimEnd }, set: { editor.setTrimEnd($0) }))
            HStack(spacing: 8) {
                audioToolButton("分割", "scissors") { _ = editor.split(at: playhead) }
                audioToolButton("复制", "plus.square.on.square") { editor.duplicateSelectedClip() }
                audioToolButton("删除", "trash") { editor.deleteSelectedClip() }.disabled(!editor.canDeleteClip)
            }
            adjustAudio("速度", $editor.speed, 0.25...4)
        }.padding(15)
    }

    private var audioTonePanel: some View {
        VStack(spacing: 14) {
            panelHeader("音色塑形", editor.hasAudioEffects ? "ACTIVE" : "NEUTRAL")
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(AudioEQPreset.allCases) { preset in
                        Button(preset.rawValue) { editor.applyEQPreset(preset) }
                            .font(.caption.bold()).foregroundStyle(RailColor.ink(scheme)).padding(.horizontal, 12).frame(minHeight: 38)
                            .background(RailColor.raised(scheme)).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            adjustAudio("降噪", $editor.noiseReduction, 0...1)
            adjustAudio("低频", $editor.bassGain, -12...12)
            adjustAudio("中频", $editor.midGain, -12...12)
            adjustAudio("高频", $editor.trebleGain, -12...12)
        }.padding(15)
    }

    private var audioSmartPanel: some View {
        VStack(spacing: 12) {
            panelHeader("智能处理", editor.isAnalyzingSilence ? "ANALYZING" : "ON DEVICE")
            Button { Task { await editor.analyzeSilence() } } label: { smartRow("检测静音", "标记可移除的安静片段", "waveform.badge.magnifyingglass") }.buttonStyle(.plain)
            RailHairline()
            Button { _ = editor.applySilenceRemoval() } label: { smartRow("移除静音", "已检测 \(String(format: "%.1f", editor.detectedSilenceDuration)) 秒", "scissors.badge.ellipsis") }.buttonStyle(.plain)
            RailHairline()
            Button { Task { await editor.autoTuneNoiseReduction() } } label: { smartRow("自动降噪", "分析噪声底并匹配强度", "wand.and.stars") }.buttonStyle(.plain)
        }.padding(15)
    }

    private var audioLyricsPanel: some View {
        VStack(spacing: 12) {
            panelHeader("歌词轨", editor.hasLyrics ? "\(editor.lyrics.count) LINES" : "EMPTY")
            if editor.lyrics.isEmpty {
                Text("可在录音时导入歌词，编辑器会自动读取同名歌词文件。")
                    .font(.system(.caption, design: .rounded)).foregroundStyle(RailColor.secondary(scheme)).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(editor.lyrics.prefix(6)) { line in
                    HStack { Text(line.time.map(timecode) ?? "—").font(.caption2.monospaced()).foregroundStyle(RailColor.secondary(scheme)).frame(width: 48); Text(line.text).font(.body).lineLimit(1); Spacer() }
                }
            }
        }.padding(15)
    }

    private var audioExportPanel: some View {
        VStack(spacing: 14) {
            panelHeader("输出设置", outputURL == nil ? "NOT EXPORTED" : "READY")
            RailSegmented(values: editor.availableFormats.map { ($0, $0.rawValue) }, selection: $editor.exportFormat)
            RailSegmented(values: AudioExportBitrate.allCases.map { ($0, $0.title) }, selection: $editor.exportBitrate)
            if editor.isExporting { ProgressView(value: editor.exportProgress).tint(RailColor.coral) }
            if let outputURL { ShareLink(item: outputURL) { RailLabel("分享文件", systemImage: "arrow.up.right").frame(maxWidth: .infinity, minHeight: 46) }.buttonStyle(RailPrimaryButtonStyle(tint: RailColor.blue)) }
        }.padding(15)
    }

    private var audioExportButton: some View {
        Button { exportAudio() } label: {
            HStack {
                if editor.isExporting { ProgressView().tint(.white) } else { RailGlyph(systemName: "waveform.badge.plus") }
                Text(editor.isExporting ? "正在导出 \(Int(editor.exportProgress * 100))%" : "导出音频")
                Spacer(); Text(editor.exportFormat.rawValue).font(.caption.monospaced().bold()).opacity(0.7)
            }
            .font(.system(.headline, design: .rounded, weight: .bold)).padding(.horizontal, 17).frame(maxWidth: .infinity, minHeight: 58)
        }.buttonStyle(RailPrimaryButtonStyle()).disabled(editor.isExporting)
    }

    private func panelHeader(_ title: String, _ detail: String) -> some View {
        HStack { Text(title).font(.system(.headline, design: .rounded, weight: .bold)); Spacer(); Text(detail).font(.caption.monospaced().bold()).foregroundStyle(RailColor.secondary(scheme)) }
    }

    private func audioBoundary(_ title: String, _ value: Binding<Double>) -> some View {
        HStack { Text(title).font(.caption.bold()).frame(width: 32); Slider(value: value, in: 0...max(editor.duration, 0.1)).tint(RailColor.coral); Text(timecode(value.wrappedValue)).font(.caption2.monospaced()).frame(width: 48) }
    }

    private func adjustAudio(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack { Text(title).font(.caption.bold()).frame(width: 40, alignment: .leading); Slider(value: value, in: range).tint(RailColor.coral); Text(String(format: "%.1f", value.wrappedValue)).font(.caption2.monospaced()).frame(width: 38) }
    }

    private func audioToolButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { RailLabel(title, systemImage: symbol).font(.caption.bold()).foregroundStyle(RailColor.ink(scheme)).frame(maxWidth: .infinity, minHeight: 42).background(RailColor.raised(scheme)).clipShape(RoundedRectangle(cornerRadius: 10)) }.buttonStyle(RailPressStyle())
    }

    private func smartRow(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(spacing: 12) { RailGlyph(systemName: symbol).foregroundStyle(RailColor.coral).frame(width: 32); VStack(alignment: .leading, spacing: 3) { Text(title).font(.body.bold()); Text(detail).font(.caption).foregroundStyle(RailColor.secondary(scheme)) }; Spacer(); RailGlyph(systemName: "arrow.right").font(.caption.bold()).foregroundStyle(RailColor.secondary(scheme)) }.foregroundStyle(RailColor.ink(scheme)).frame(minHeight: 52)
    }

    private func toggleAudio() { if isPlaying { player.pause() } else { player.play() }; isPlaying.toggle() }

    private func installAudioObserver() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.08, preferredTimescale: 600), queue: .main) { time in
            Task { @MainActor in if isPlaying { playhead = min(editor.duration, max(0, time.seconds)) } }
        }
    }

    private func removeAudioObserver() { if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil } }

    private func exportAudio() {
        Task {
            do { outputURL = try await editor.export(); await library.reload(); showAudio("音频已导出") }
            catch { showAudio(error.localizedDescription) }
        }
    }

    private func timecode(_ seconds: Double) -> String { let value = max(0, Int(seconds)); return String(format: "%02d:%02d", value / 60, value % 60) }
    private func showAudio(_ text: String) { message = text; Task { try? await Task.sleep(for: .seconds(2)); message = nil } }
}
