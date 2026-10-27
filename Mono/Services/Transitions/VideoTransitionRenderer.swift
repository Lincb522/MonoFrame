import CoreVideo
import Metal

/// Serial-queue renderer. A selected shader failing is an error, never another effect.
final class VideoTransitionRenderer {
    enum RenderError: LocalizedError {
        case unavailable, shader(String), texture(OSStatus), command(String)
        var errorDescription: String? {
            switch self {
            case .unavailable: "设备的 Metal 转场渲染器初始化失败。"
            case .shader(let name): "转场着色器加载失败：\(name)"
            case .texture(let status): "转场纹理创建失败（\(status)）。"
            case .command(let detail): "转场渲染失败：\(detail)"
            }
        }
    }
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let library: MTLLibrary
    private let cache: CVMetalTextureCache
    private var pipelines: [VideoTransition: MTLRenderPipelineState] = [:]

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { throw RenderError.unavailable }
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        guard status == kCVReturnSuccess, let cache else { throw RenderError.texture(status) }
        self.device = device; self.queue = queue; self.library = library; self.cache = cache
    }

    func render(from: CVPixelBuffer, to: CVPixelBuffer, into output: CVPixelBuffer,
                effect: VideoTransition, progress: Float) throws {
        // All imported kernels have exact source/destination endpoints, even when their
        // interior math has singularities at progress == 0 or 1 (page curls, cube, etc.).
        let endpoint = progress <= 0 || progress >= 1
        let active: VideoTransition = endpoint ? .dissolve : effect
        let pipeline: MTLRenderPipelineState
        if let cached = pipelines[active] { pipeline = cached }
        else {
            guard let vertex = library.makeFunction(name: "monoTransitionVertex"),
                  let fragment = library.makeFunction(name: active.functionName) else {
                throw RenderError.shader(active.functionName)
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex; descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            pipelines[active] = pipeline
        }
        let a = try texture(from), b = try texture(to), target = try texture(output)
        guard let command = queue.makeCommandBuffer() else { throw RenderError.unavailable }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = CVMetalTextureGetTexture(target)
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw RenderError.unavailable }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(CVMetalTextureGetTexture(a), index: 0)
        encoder.setFragmentTexture(CVMetalTextureGetTexture(b), index: 1)
        active.encodeParameters(encoder, ratio: Float(CVPixelBufferGetWidth(output)) / Float(CVPixelBufferGetHeight(output)),
                                progress: min(1, max(0, progress)))
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        command.commit(); command.waitUntilCompleted()
        withExtendedLifetime([a, b, target]) {}
        if command.status != .completed { throw RenderError.command(command.error?.localizedDescription ?? "GPU command did not complete") }
    }

    private func texture(_ buffer: CVPixelBuffer) throws -> CVMetalTexture {
        var texture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &texture)
        guard status == kCVReturnSuccess, let texture else { throw RenderError.texture(status) }
        return texture
    }
}
