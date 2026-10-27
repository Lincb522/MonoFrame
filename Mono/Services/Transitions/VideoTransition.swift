import Foundation
import Metal

// Effect kernels: alexiscn/MTTransitions (MIT). See Resources/ThirdParty.
enum VideoTransition: String, CaseIterable, Identifiable, Codable {
    case none = "无"
    case dissolve = "叠化"
    case fadeColor = "黑场淡入"
    case fadegrayscale = "灰阶溶解"
    case multiplyBlend = "正片叠底"
    case linearBlur = "柔焦"
    case angular = "扇形展开"
    case radial = "径向擦除"
    case circleOpen = "圆形展开"
    case directional = "向上推移"
    case directionalEasing = "缓动推移"
    case directionalWarp = "斜向扭曲"
    case directionalWipe = "斜向擦除"
    case wipeLeft = "向左擦除"
    case wipeRight = "向右擦除"
    case wipeUp = "向上擦除"
    case wipeDown = "向下擦除"
    case fadeInWipeLeft = "向左渐入"
    case fadeInWipeUp = "向上渐入"
    case crossZoom = "交叉变焦"
    case crossWarp = "交叉拉伸"
    case dreamyZoom = "梦幻变焦"
    case rotateScaleFade = "旋转缩放"
    case simpleZoom = "快速推进"
    case zoomInCircles = "同心圆变焦"
    case squeeze = "挤压"
    case swirl = "旋涡"
    case bowTieHorizontal = "横向蝴蝶"
    case bowTieVertical = "纵向蝴蝶"
    case heart = "心形"
    case hexagonalize = "蜂巢"
    case gridFlip = "网格翻转"
    case mosaic = "马赛克"
    case randomSquares = "随机方块"
    case squaresWire = "方格线框"
    case windowBlinds = "百叶窗"
    case windowSlice = "窗格切片"
    case cube = "立方体"
    case doorway = "开门"
    case swap = "立体交换"
    case bounce = "弹跳"
    case bookFlip = "翻书"
    case invertedPageCurl = "卷页"
    case burn = "燃烧"
    case colorPhase = "色彩相位"
    case dreamy = "梦幻波动"
    case glitchDisplace = "故障位移"
    case glitchMemories = "故障闪回"
    case perlin = "噪声溶解"
    case ripple = "波纹"
    case waterDrop = "水滴"
    case wind = "风蚀"
    var id: String { rawValue }
    static var effects: [Self] { allCases.filter { $0 != .none } }
    static let categories = ["基础", "推拉", "缩放", "几何", "立体", "特效"]
    var category: String {
        switch self {
        case .none: "基础"
        case .dissolve, .fadeColor, .fadegrayscale, .multiplyBlend, .linearBlur, .angular, .radial, .circleOpen: "基础"
        case .directional, .directionalEasing, .directionalWarp, .directionalWipe, .wipeLeft, .wipeRight, .wipeUp, .wipeDown, .fadeInWipeLeft, .fadeInWipeUp: "推拉"
        case .crossZoom, .crossWarp, .dreamyZoom, .rotateScaleFade, .simpleZoom, .zoomInCircles, .squeeze, .swirl: "缩放"
        case .bowTieHorizontal, .bowTieVertical, .heart, .hexagonalize, .gridFlip, .mosaic, .randomSquares, .squaresWire, .windowBlinds, .windowSlice: "几何"
        case .cube, .doorway, .swap, .bounce, .bookFlip, .invertedPageCurl: "立体"
        case .burn, .colorPhase, .dreamy, .glitchDisplace, .glitchMemories, .perlin, .ripple, .waterDrop, .wind: "特效"
        }
    }
    var symbol: String {
        switch category {
        case "基础": "circle.lefthalf.filled"
        case "推拉": "arrow.left.arrow.right"
        case "缩放": "arrow.up.left.and.arrow.down.right"
        case "几何": "square.grid.2x2"
        case "立体": "cube"
        case "特效": "sparkles"
        default: "circle.slash"
        }
    }
    var functionName: String {
        switch self {
        case .none: "FadeFragment"
        case .dissolve: "FadeFragment"
        case .fadeColor: "FadeColorFragment"
        case .fadegrayscale: "FadegrayscaleFragment"
        case .multiplyBlend: "MultiplyBlendFragment"
        case .linearBlur: "LinearBlurFragment"
        case .angular: "AngularFragment"
        case .radial: "RadialFragment"
        case .circleOpen: "CircleOpenFragment"
        case .directional: "DirectionalFragment"
        case .directionalEasing: "DirectionalEasingFragment"
        case .directionalWarp: "DirectionalWarpFragment"
        case .directionalWipe: "DirectionalWipeFragment"
        case .wipeLeft: "WipeLeftFragment"
        case .wipeRight: "WipeRightFragment"
        case .wipeUp: "WipeUpFragment"
        case .wipeDown: "WipeDownFragment"
        case .fadeInWipeLeft: "FadeInWipeLeftFragment"
        case .fadeInWipeUp: "FadeInWipeUpFragment"
        case .crossZoom: "CrossZoomFragment"
        case .crossWarp: "CrossWarpFragment"
        case .dreamyZoom: "DreamyZoomFragment"
        case .rotateScaleFade: "RotateScaleFadeFragment"
        case .simpleZoom: "SimpleZoomFragment"
        case .zoomInCircles: "ZoomInCirclesFragment"
        case .squeeze: "SqueezeFragment"
        case .swirl: "SwirlFragment"
        case .bowTieHorizontal: "BowTieHorizontalFragment"
        case .bowTieVertical: "BowTieVerticalFragment"
        case .heart: "HeartFragment"
        case .hexagonalize: "HexagonalizeFragment"
        case .gridFlip: "GridFlipFragment"
        case .mosaic: "MosaicFragment"
        case .randomSquares: "RandomSquaresFragment"
        case .squaresWire: "SquaresWireFragment"
        case .windowBlinds: "WindowBlindsFragment"
        case .windowSlice: "WindowSliceFragment"
        case .cube: "CubeFragment"
        case .doorway: "DoorwayFragment"
        case .swap: "SwapFragment"
        case .bounce: "BounceFragment"
        case .bookFlip: "BookFlipFragment"
        case .invertedPageCurl: "InvertedPageCurlFragment"
        case .burn: "BurnFragment"
        case .colorPhase: "ColorPhaseFragment"
        case .dreamy: "DreamyFragment"
        case .glitchDisplace: "GlitchDisplaceFragment"
        case .glitchMemories: "GlitchMemoriesFragment"
        case .perlin: "PerlinFragment"
        case .ripple: "RippleFragment"
        case .waterDrop: "WaterDropFragment"
        case .wind: "WindFragment"
        }
    }
    func encodeParameters(_ encoder: MTLRenderCommandEncoder, ratio: Float, progress: Float) {
        func bind<T>(_ input: T, at index: Int) {
            var value = input
            withUnsafeBytes(of: &value) { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: index) }
        }
        switch self {
        case .none: bind(ratio, at: 0); bind(progress, at: 1)
        case .dissolve:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .fadeColor:
            bind(SIMD3<Float>(0.0, 0.0, 0.0), at: 0)
            bind(Float(0.4), at: 1)
            bind(ratio, at: 2)
            bind(progress, at: 3)
        case .fadegrayscale:
            bind(Float(0.3), at: 0)
            bind(ratio, at: 1)
            bind(progress, at: 2)
        case .multiplyBlend:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .linearBlur:
            bind(Float(0.1), at: 0)
            bind(ratio, at: 1)
            bind(progress, at: 2)
        case .angular:
            bind(Float(90), at: 0)
            bind(ratio, at: 1)
            bind(progress, at: 2)
        case .radial:
            bind(Float(1), at: 0)
            bind(ratio, at: 1)
            bind(progress, at: 2)
        case .circleOpen:
            bind(Float(0.3), at: 0)
            bind(UInt8(1), at: 1)
            bind(ratio, at: 2)
            bind(progress, at: 3)
        case .directional:
            bind(SIMD2<Float>(0, 1.0), at: 0)
            bind(ratio, at: 1)
            bind(progress, at: 2)
        case .directionalEasing:
            bind(SIMD2<Float>(0.0, 1.0), at: 0)
            bind(ratio, at: 1)
            bind(progress, at: 2)
        case .directionalWarp:
            bind(SIMD2<Float>(-1.0, 1.0), at: 0)
            bind(ratio, at: 1)
            bind(progress, at: 2)
        case .directionalWipe:
            bind(SIMD2<Float>(1.0, -1.0), at: 0)
            bind(Float(0.5), at: 1)
            bind(ratio, at: 2)
            bind(progress, at: 3)
        case .wipeLeft:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .wipeRight:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .wipeUp:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .wipeDown:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .fadeInWipeLeft:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .fadeInWipeUp:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .crossZoom:
            bind(Float(0.4), at: 0)
            bind(ratio, at: 1)
            bind(progress, at: 2)
        case .crossWarp:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .dreamyZoom:
            bind(Float(6), at: 0)
            bind(Float(1.2), at: 1)
            bind(ratio, at: 2)
            bind(progress, at: 3)
        case .rotateScaleFade:
            bind(Float(8), at: 0)
            bind(Float(1), at: 1)
            bind(SIMD2<Float>(0.5, 0.5), at: 2)
            bind(SIMD4<Float>(0.15, 0.15, 0.15, 1.0), at: 3)
            bind(ratio, at: 4)
            bind(progress, at: 5)
        case .simpleZoom:
            bind(Float(0.8), at: 0)
            bind(ratio, at: 1)
            bind(progress, at: 2)
        case .zoomInCircles:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .squeeze:
            bind(Float(0.04), at: 0)
            bind(ratio, at: 1)
            bind(progress, at: 2)
        case .swirl:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .bowTieHorizontal:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .bowTieVertical:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .heart:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .hexagonalize:
            bind(Int32(50), at: 0)
            bind(Float(20), at: 1)
            bind(ratio, at: 2)
            bind(progress, at: 3)
        case .gridFlip:
            bind(SIMD4<Float>(0.0, 0.0, 0.0, 1.0), at: 0)
            bind(Float(0.1), at: 1)
            bind(Float(0.1), at: 2)
            bind(Float(0.05), at: 3)
            bind(SIMD2<Int32>(4, 4), at: 4)
            bind(ratio, at: 5)
            bind(progress, at: 6)
        case .mosaic:
            bind(Int32(-1), at: 0)
            bind(Int32(2), at: 1)
            bind(ratio, at: 2)
            bind(progress, at: 3)
        case .randomSquares:
            bind(Float(0.5), at: 0)
            bind(SIMD2<Float>(10, 10), at: 1)
            bind(ratio, at: 2)
            bind(progress, at: 3)
        case .squaresWire:
            bind(SIMD2<Float>(1.0, -0.5), at: 0)
            bind(SIMD2<Int32>(10, 10), at: 1)
            bind(Float(1.6), at: 2)
            bind(ratio, at: 3)
            bind(progress, at: 4)
        case .windowBlinds:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .windowSlice:
            bind(Float(10), at: 0)
            bind(Float(0.5), at: 1)
            bind(ratio, at: 2)
            bind(progress, at: 3)
        case .cube:
            bind(Float(0.7), at: 0)
            bind(Float(0.3), at: 1)
            bind(Float(0.4), at: 2)
            bind(Float(3), at: 3)
            bind(ratio, at: 4)
            bind(progress, at: 5)
        case .doorway:
            bind(Float(3), at: 0)
            bind(Float(0.4), at: 1)
            bind(Float(0.4), at: 2)
            bind(ratio, at: 3)
            bind(progress, at: 4)
        case .swap:
            bind(Float(3), at: 0)
            bind(Float(0.4), at: 1)
            bind(Float(0.2), at: 2)
            bind(ratio, at: 3)
            bind(progress, at: 4)
        case .bounce:
            bind(Float(3), at: 0)
            bind(SIMD4<Float>(0.0, 0.0, 0.0, 0.6), at: 1)
            bind(Float(0.075), at: 2)
            bind(ratio, at: 3)
            bind(progress, at: 4)
        case .bookFlip:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .invertedPageCurl:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .burn:
            bind(SIMD3<Float>(0.9, 0.4, 0.2), at: 0)
            bind(ratio, at: 1)
            bind(progress, at: 2)
        case .colorPhase:
            bind(SIMD4<Float>(0.0, 0.2, 0.4, 0.0), at: 0)
            bind(SIMD4<Float>(0.6, 0.8, 1.0, 1.0), at: 1)
            bind(ratio, at: 2)
            bind(progress, at: 3)
        case .dreamy:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .glitchDisplace:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .glitchMemories:
            bind(ratio, at: 0)
            bind(progress, at: 1)
        case .perlin:
            bind(Float(4), at: 0)
            bind(Float(12.9898), at: 1)
            bind(Float(0.01), at: 2)
            bind(ratio, at: 3)
            bind(progress, at: 4)
        case .ripple:
            bind(Float(50), at: 0)
            bind(Float(100), at: 1)
            bind(ratio, at: 2)
            bind(progress, at: 3)
        case .waterDrop:
            bind(Float(30), at: 0)
            bind(Float(30), at: 1)
            bind(ratio, at: 2)
            bind(progress, at: 3)
        case .wind:
            bind(Float(0.2), at: 0)
            bind(ratio, at: 1)
            bind(progress, at: 2)
        }
    }
}
