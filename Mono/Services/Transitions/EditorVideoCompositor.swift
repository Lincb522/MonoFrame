import AVFoundation
import CoreImage

struct EditorVideoLayer {
    let trackID: CMPersistentTrackID
    let transform: CGAffineTransform
    let start: Double
    let duration: Double
    let motion: ClipMotion?
}

final class EditorVideoInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    var requiredSourceTrackIDs: [NSValue]? { layers.map { NSNumber(value: $0.trackID) } }
    let layers: [EditorVideoLayer]
    let transition: VideoTransition
    init(range: CMTimeRange, layers: [EditorVideoLayer], transition: VideoTransition = .none) {
        self.timeRange = range; self.layers = layers; self.transition = transition
    }
}

final class EditorVideoCompositor: NSObject, AVVideoCompositing {
    var sourcePixelBufferAttributes: [String: Any]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }
    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true,
         kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
    }
    private let queue = DispatchQueue(label: "MonoFrame.video-compositor", qos: .userInitiated)
    private let renderer: Result<VideoTransitionRenderer, Error>
    private let context: CIContext?
    private var pool: CVPixelBufferPool?
    private var poolSize = CGSize.zero
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    override init() {
        let result = Result { try VideoTransitionRenderer() }
        renderer = result
        switch result {
        case .success(let engine): context = CIContext(mtlDevice: engine.device, options: [.cacheIntermediates: false])
        case .failure: context = nil
        }
        super.init()
    }
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        queue.async { self.pool = nil; self.poolSize = .zero }
    }
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async {
            do {
                let engine = try self.renderer.get()
                guard let context = self.context else { throw VideoTransitionRenderer.RenderError.unavailable }
                guard let instruction = request.videoCompositionInstruction as? EditorVideoInstruction,
                      let first = instruction.layers.first,
                      let output = request.renderContext.newPixelBuffer() else { throw VideoTransitionRenderer.RenderError.command("Missing composition instruction or output buffer") }
                let size = request.renderContext.size
                let a = try self.normalized(first, request: request, size: size)
                if instruction.layers.count == 2 {
                    let b = try self.normalized(instruction.layers[1], request: request, size: size)
                    let progress = Float((request.compositionTime - instruction.timeRange.start).seconds / instruction.timeRange.duration.seconds)
                    try engine.render(from: a, to: b, into: output, effect: instruction.transition, progress: progress)
                } else {
                    context.render(CIImage(cvPixelBuffer: a), to: output, bounds: CGRect(origin: .zero, size: size), colorSpace: self.colorSpace)
                }
                request.finish(withComposedVideoFrame: output)
            } catch { request.finish(with: error) }
        }
    }
    func cancelAllPendingVideoCompositionRequests() {
        // Drain the serial queue: every enqueued request is completed exactly once.
        queue.sync {}
    }
    private func normalized(_ layer: EditorVideoLayer, request: AVAsynchronousVideoCompositionRequest, size: CGSize) throws -> CVPixelBuffer {
        guard let source = request.sourceFrame(byTrackID: layer.trackID) else {
            throw VideoTransitionRenderer.RenderError.command("Missing source frame for track \(layer.trackID)")
        }
        if pool == nil || poolSize != size {
            let status = CVPixelBufferPoolCreate(nil, nil, [
                kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ] as CFDictionary, &pool)
            guard status == kCVReturnSuccess else { throw VideoTransitionRenderer.RenderError.texture(status) }
            poolSize = size
        }
        var buffer: CVPixelBuffer?
        guard let pool else { throw VideoTransitionRenderer.RenderError.unavailable }
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw VideoTransitionRenderer.RenderError.texture(status) }
        let bounds = CGRect(origin: .zero, size: size)
        var frame = CIImage(cvPixelBuffer: source).transformed(by: layer.transform)
        if let motion = layer.motion {
            let pose = motion.pose(at: (request.compositionTime.seconds - layer.start) / max(layer.duration, 0.001))
            let zoom = max(1, pose.zoom)
            // Normalized pan is bounded by the scaled image's overflow, never exposing an empty edge.
            let dx = -size.width * (zoom - 1) * (0.5 + min(1, max(-1, pose.x)) * 0.5)
            let dy = -size.height * (zoom - 1) * (0.5 - min(1, max(-1, pose.y)) * 0.5)
            frame = frame.transformed(by: CGAffineTransform(a: zoom, b: 0, c: 0, d: zoom, tx: dx, ty: dy))
        }
        frame = frame.composited(over: CIImage(color: .black).cropped(to: bounds)).cropped(to: bounds)
        guard let context else { throw VideoTransitionRenderer.RenderError.unavailable }
        context.render(frame, to: buffer, bounds: bounds, colorSpace: colorSpace)
        return buffer
    }
}
