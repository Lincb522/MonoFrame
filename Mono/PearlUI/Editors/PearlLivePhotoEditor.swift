import AVFoundation
import SwiftUI

struct PearlLivePhotoEditor: View {
    let url: URL
    @StateObject private var playback: PearlPlaybackController
    @State private var sourceDuration = 0.1
    @State private var start = 0.0
    @State private var length = 3.0
    @State private var keyTime = 1.5
    @State private var muted = false
    @State private var ready = false
    @State private var saving = false
    @State private var message: String?
    @State private var saved = false
    @Environment(\.dismiss) private var dismiss

    init(url: URL) {
        self.url = url
        _playback = StateObject(wrappedValue: PearlPlaybackController(url: url))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ZStack(alignment: .bottom) {
                        PearlPlayerSurface(player: playback.player).allowsHitTesting(false)
                        Label("按住预览 · 松开回到封面", systemImage: "livephoto")
                            .font(.caption.weight(.semibold)).foregroundStyle(.white).padding(10)
                            .background(.black.opacity(0.7), in: Capsule()).padding(12)
                    }
                    .frame(height: 300).background(.black).clipShape(RoundedRectangle(cornerRadius: 12))
                    .onLongPressGesture(minimumDuration: 0.15, perform: {}, onPressingChanged: { pressed in
                        guard ready, !saving else { return }
                        if pressed { playback.seek(to: start); playback.play(range: start...(start + length)) }
                        else { playback.pause(); playback.seek(to: start + keyTime) }
                    })
                    .accessibilityLabel("Live Photo 预览").accessibilityAddTraits(.isButton)
                    .accessibilityAction { playback.toggle(range: start...(start + length)) }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("留住这一瞬").font(.title2.bold())
                        Text("选择最多 3 秒动态，再指定相册中显示的关键照片。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Group {
                        LabeledContent("片段起点", value: String(format: "%.2f 秒", start))
                        Slider(value: $start, in: 0...max(0.001, sourceDuration - length))
                            .accessibilityIdentifier("pearl.livePhoto.start")
                            .disabled(sourceDuration <= length)
                        LabeledContent("动态时长", value: String(format: "%.2f 秒", length))
                        Slider(value: $length, in: min(0.1, sourceDuration)...max(0.101, min(3, sourceDuration)))
                            .accessibilityIdentifier("pearl.livePhoto.length")
                        LabeledContent("关键照片", value: String(format: "%.2f 秒", start + keyTime))
                        Slider(value: $keyTime, in: 0...max(0.001, length - 1 / 30))
                            .accessibilityIdentifier("pearl.livePhoto.keyTime")
                        Toggle("保留动态声音", isOn: Binding(get: { !muted }, set: { muted = !$0 }))
                            .accessibilityIdentifier("pearl.livePhoto.sound")
                    }.disabled(!ready || saving)
                    if let message {
                        Label(message, systemImage: saved ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(saved ? .green : .orange)
                            .accessibilityIdentifier("pearl.livePhoto.notice")
                    }
                    Button(action: save) {
                        HStack { if saving { ProgressView() }; Text(saving ? "正在写入相册" : "保存 Live Photo").bold() }
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent).tint(.orange)
                    .disabled(!ready || saving)
                    .accessibilityIdentifier("pearl.livePhoto.save")
                }.padding(20)
            }
            .background(Color(white: 0.055))
            .toolbarBackground(Color(white: 0.055), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationTitle("Live Photo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() }.disabled(saving) } }
            .interactiveDismissDisabled(saving)
            .task {
                do {
                    let seconds = try await AVURLAsset(url: url).load(.duration).seconds
                    guard seconds.isFinite, seconds > 0 else { throw EditingDeskError.invalidRange }
                    sourceDuration = seconds; length = min(3, seconds)
                    start = max(0, (seconds - length) / 2); keyTime = length / 2
                    playback.seek(to: start + keyTime); ready = true
                } catch { message = error.localizedDescription }
            }
            .onChange(of: start) { _, _ in constrainAndSeek() }
            .onChange(of: length) { _, _ in constrainAndSeek() }
            .onChange(of: keyTime) { _, _ in playback.seek(to: start + keyTime) }
            .onChange(of: muted) { _, value in playback.player.isMuted = value }
            .onDisappear { playback.pause() }
        }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .tint(.orange)
    }

    private func constrainAndSeek() {
        start = min(start, max(0, sourceDuration - length))
        keyTime = min(keyTime, max(0, length - 1 / 30))
        playback.pause(); playback.seek(to: start + keyTime)
        saved = false
    }

    private func save() {
        guard ready, !saving else { return }
        saving = true; saved = false; message = nil; playback.pause()
        Task {
            defer { saving = false }
            do {
                try await LivePhotoMaker.save(videoURL: url, selection: .init(
                    start: start, duration: length, keyTime: keyTime, muted: muted))
                saved = true; message = "Live Photo 已保存到相册。"
            } catch { message = "保存失败：\(error.localizedDescription)" }
        }
    }
}
