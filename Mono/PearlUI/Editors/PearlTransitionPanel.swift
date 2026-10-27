import AVFoundation
import CoreImage
import SwiftUI

struct PearlTransitionPanel: View {
    @ObservedObject var editor: VideoEditor
    var previewReady: Bool
    var preview: () -> Void
    @State private var category = "全部"
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var thumbnails: [VideoTransition: UIImage] = [:]
    @State private var thumbnailError: String?
    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 8)]
    private var visible: [VideoTransition] {
        VideoTransition.effects.filter {
            (category == "全部" || $0.category == category) &&
            (query.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(query) || $0.functionName.localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("转场库").font(.headline)
                    Text("50 款新增 · 51 款效果").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: preview) { Label("预览", systemImage: "play.fill").font(.caption.weight(.semibold)).frame(minHeight: 44) }
                    .disabled(!editor.hasNextClip || !previewReady)
                    .accessibilityIdentifier("pearl.transition.preview")
            }
            if !editor.hasNextClip {
                Label("请选择前一个片段，或添加下一段视频。", systemImage: "rectangle.on.rectangle")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
            } else {
                DisclosureGroup {
                HStack(spacing: 8) {
                    Text("\((editor.selectedClipIndex ?? 0) + 1)").font(.caption.monospacedDigit().bold())
                        .frame(width: 28, height: 28).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    Text("\((editor.selectedClipIndex ?? 0) + 2)").font(.caption.monospacedDigit().bold())
                        .frame(width: 28, height: 28).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    Spacer()
                    Text(editor.transition.rawValue).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    Button("移除") { editor.setTransition(.none) }.font(.caption).frame(minHeight: 44)
                        .disabled(editor.transition == .none)
                }
                Slider(value: Binding(get: { editor.transitionDuration }, set: { editor.setTransition(editor.transition, duration: $0) }),
                       in: 0.1...2, step: 0.05, onEditingChanged: { $0 ? editor.beginContinuousEdit() : editor.endContinuousEdit() })
                HStack {
                    Text("实际时长 \(String(format: "%.2f", editor.effectiveTransitionDuration(after: editor.selectedClipIndex ?? 0)))s")
                    Spacer()
                    Button("应用到全部") { editor.setTransition(editor.transition, duration: editor.transitionDuration, all: true) }
                        .accessibilityIdentifier("pearl.transition.applyAll")
                }.font(.caption2)
                Text("短片段自动限制重叠长度，避免相邻转场冲突。").font(.caption2).foregroundStyle(.secondary)
                } label: {
                    Text("\(editor.transition.rawValue) · \(String(format: "%.2f", editor.effectiveTransitionDuration(after: editor.selectedClipIndex ?? 0)))s")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text("时长 / 批量").font(.caption2).foregroundStyle(.secondary)
                }.tint(.orange)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索转场", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                    .accessibilityIdentifier("pearl.transition.search")
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除转场搜索") }
            }.font(.subheadline).padding(11).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(["全部"] + VideoTransition.categories, id: \.self) { name in
                        Button { category = name } label: {
                            Text(name).font(.caption.weight(.medium)).padding(.horizontal, 12).frame(height: 36)
                                .foregroundStyle(category == name ? .black : .white.opacity(0.7))
                                .background(category == name ? Color.orange : Color.white.opacity(0.055), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }.scrollIndicators(.hidden)
            if let thumbnailError { Text(thumbnailError).font(.caption2).foregroundStyle(.orange) }
            if visible.isEmpty { Text("没有匹配的转场").font(.caption).foregroundStyle(.secondary).padding(.vertical, 20) }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(visible) { effect in
                    Button { editor.setTransition(effect) } label: {
                        VStack(spacing: 7) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.055))
                                if let image = thumbnails[effect] {
                                    Image(uiImage: image).resizable().scaledToFill().frame(height: 54).clipped()
                                } else { Image(systemName: effect.symbol).font(.title3).foregroundStyle(.secondary) }
                                if editor.transition == effect {
                                    VStack { HStack { Spacer(); Image(systemName: "checkmark.circle.fill").foregroundStyle(.black, .orange).padding(4) }; Spacer() }
                                }
                            }.frame(height: 54).clipShape(RoundedRectangle(cornerRadius: 7))
                                .overlay { RoundedRectangle(cornerRadius: 7).stroke(editor.transition == effect ? Color.orange : .white.opacity(0.08), lineWidth: editor.transition == effect ? 2 : 1) }
                            Text(effect.rawValue).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                .foregroundStyle(editor.transition == effect ? .orange : .white.opacity(0.8))
                        }
                    }.buttonStyle(.plain).disabled(!editor.hasNextClip)
                        .accessibilityIdentifier("pearl.transition.\(effect.functionName)")
                        .accessibilityLabel(effect.rawValue + (editor.transition == effect ? "，已选中" : ""))
                        .accessibilityValue(thumbnails[effect] == nil ? "正在生成缩略图" : "画面缩略图已加载")
                }
            }
        }
        .task(id: editor.selectedClipID) { await loadThumbnails() }
    }

    private func loadThumbnails() async {
        guard let index = editor.selectedClipIndex, editor.hasNextClip else { return }
        let from = editor.clips[index], to = editor.clips[index + 1]
        do {
            let images = try await Task.detached(priority: .utility) {
                let renderer = try VideoTransitionRenderer()
                let context = CIContext(mtlDevice: renderer.device)
                func frame(_ clip: VideoClip, seconds: Double) async throws -> CVPixelBuffer {
                    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip.sourceURL))
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: 256, height: 256)
                    let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
                    let buffer = try TransitionThumbnailBuffers.make()
                    var input = CIImage(cgImage: image)
                    let scale = max(128 / input.extent.width, 80 / input.extent.height)
                    input = input.transformed(by: .init(scaleX: scale, y: scale))
                    input = input.transformed(by: .init(translationX: (128 - input.extent.width) / 2, y: (80 - input.extent.height) / 2))
                    context.render(input, to: buffer)
                    return buffer
                }
                let a = try await frame(from, seconds: max(from.start, from.end - 0.1))
                let b = try await frame(to, seconds: to.start)
                let out = try TransitionThumbnailBuffers.make()
                var results: [VideoTransition: UIImage] = [:]
                for effect in VideoTransition.effects {
                    try Task.checkCancellation()
                    try renderer.render(from: a, to: b, into: out, effect: effect, progress: 0.48)
                    guard let cg = context.createCGImage(CIImage(cvPixelBuffer: out), from: CGRect(x: 0, y: 0, width: 128, height: 80)) else {
                        throw VideoTransitionRenderer.RenderError.command("Thumbnail image conversion failed")
                    }
                    results[effect] = UIImage(cgImage: cg)
                }
                return results
            }.value
            try Task.checkCancellation()
            thumbnails = images; thumbnailError = nil
        } catch is CancellationError {} catch { thumbnailError = "缩略图生成失败：\(error.localizedDescription)" }
    }
}
private enum TransitionThumbnailBuffers {
    static func make() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, 128, 80, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferMetalCompatibilityKey as String: true, kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw VideoTransitionRenderer.RenderError.texture(status) }
        return buffer
    }
}
