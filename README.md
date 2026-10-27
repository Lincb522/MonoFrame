# MonoFrame

iOS 26 SwiftUI 录屏、录音、编辑、转码与 Live Photo 工具。

## 运行

1. 打开 `Mono.xcodeproj`。
2. 连接 iPhone 后直接运行 `Mono` Scheme。
3. 使用真机测试全屏广播录制、麦克风和照片导出。

## 功能

- iOS Control Widget 控制中心录屏入口
- Broadcast Upload Extension 全屏录制，不包含 App 内录屏
- 原始屏幕尺寸、HEVC、18 Mbps、最高 60 fps
- 独立录音界面，AAC 48 kHz，128/256 Kbps 可选
- 视频编辑：裁剪、0.5–2× 变速、静音、实时画面预设、亮度、对比度、饱和度
- 音频编辑：FFmpeg 波形、裁剪、音量、淡入、淡出、分享导出
- H.264、HEVC、M4A、WAV 音视频转码
- 视频/音频双作品库
- FFmpeg 媒体探测与时间轴缩略图
- FFmpeg 无重编码快速导出、静音与兼容片段拼接
- 高清视频导出
- 带配对元数据的 Live Photo 导出
- 录屏编码、码率、录音质量、外观与缓存设置
- 深浅色、VoiceOver、降低动态效果

工程由 `project.yml` 管理；修改配置后运行 `xcodegen generate`。

## FFmpeg

工程使用本地 Swift Package：`Packages/FFmpegSwiftSDK`。MonoFrame 新增的 `VideoProcessor` 提供视频信息读取、FFmpeg 解码缩略图、MP4/MOV 无损快速裁尾与静音、兼容编码片段拼接，并输出处理进度。

`FFmpegLibs.xcframework` 已从官方 FFmpeg 8.0 源码重新全量编译，包含 517 个解码器、185 个编码器、356 个 demuxer、182 个 muxer、441 个滤镜、37 个协议、48 个 bitstream filter 和 AVFoundation 输入设备。启用 VideoToolbox、AudioToolbox、Metal、CoreImage、SecureTransport、网络、ARM SIMD、`libmp3lame`、`libavdevice`、`libswscale` 与完整公共头。

`CodecCapabilities.runtimeCatalog()` 可枚举二进制实际注册的全部组件。构建保持 LGPL，MP3 编码由 LGPL 的 libmp3lame 提供，不包含 GPL/非自由第三方库；iOS SDK 未公开 LZMA 开发头，因此只关闭 LZMA。快速导出直接复制 H.264/HEVC 压缩数据；需要非关键帧精确起点或变速时，编辑器自动使用 AVFoundation 重编码。
