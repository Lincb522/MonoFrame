import SwiftUI

enum LegalDocument: String, CaseIterable, Identifiable {
    case ffmpeg
    case userAgreement
    case disclaimer
    case privacyRights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ffmpeg: "FFmpeg 开源许可"
        case .userAgreement: "用户协议"
        case .disclaimer: "免责协议"
        case .privacyRights: "隐私权利"
        }
    }

    var icon: String {
        switch self {
        case .ffmpeg: "chevron.left.forwardslash.chevron.right"
        case .userAgreement: "doc.text"
        case .disclaimer: "exclamationmark.shield"
        case .privacyRights: "hand.raised"
        }
    }

    var sections: [LegalSection] {
        switch self {
        case .ffmpeg: ffmpegSections
        case .userAgreement: userAgreementSections
        case .disclaimer: disclaimerSections
        case .privacyRights: privacySections
        }
    }

    var links: [LegalLink] {
        guard self == .ffmpeg else { return [] }
        return [
            .init(
                title: "FFmpeg 8.0 对应源代码",
                url: "https://ffmpeg.org/releases/ffmpeg-8.0.tar.xz"
            ),
            .init(
                title: "GNU LGPL 2.1 完整文本",
                url: "https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html"
            ),
            .init(
                title: "FFmpegSwiftSDK 源代码与构建脚本",
                url: "https://github.com/Lincb522/FFmpegSwiftSDK"
            ),
            .init(
                title: "LAME 项目与许可",
                url: "https://lame.sourceforge.io/"
            )
        ]
    }

    private var ffmpegSections: [LegalSection] {
        [
            .init(
                title: "第三方软件声明",
                body: "MonoFrame 使用 FFmpeg 项目的库，许可为 GNU Lesser General Public License 2.1 或更高版本。FFmpeg 是 Fabrice Bellard 的商标；MonoFrame 与 FFmpeg 项目不存在隶属或背书关系。"
            ),
            .init(
                title: "当前构建",
                body: "版本：FFmpeg 8.0\n许可：LGPL-2.1-or-later\n链接方式：静态链接\n外部库：LAME 3.100（LGPL）\n构建未启用 --enable-gpl 或 --enable-nonfree。"
            ),
            .init(
                title: "你的开源权利",
                body: "你可以依照适用的 LGPL 获取、复制、修改、重新编译和再分发 FFmpeg 与 LAME。MonoFrame 的用户协议不限制为调试这些 LGPL 组件的修改而依法进行的必要逆向工程。对应源代码、许可文本和构建脚本见下方链接。"
            ),
            .init(
                title: "Swift 封装层",
                body: "FFmpegSwiftSDK 采用 MIT License。Copyright © 2025 Lincb522。该软件按“原样”提供，不附带任何明示或默示保证；在法律允许范围内，作者不对因使用该软件产生的索赔、损害或其他责任负责。"
            )
        ]
    }

    private var userAgreementSections: [LegalSection] {
        [
            .init(
                title: "接受协议",
                body: "下载、安装或使用 MonoFrame 即表示你同意本协议。若不同意，请停止使用并删除 App。"
            ),
            .init(
                title: "使用许可",
                body: "MonoFrame 授予你一项有限、非独占、不可转让的许可，用于个人或合法的商业音视频录制、编辑、转码和导出。"
            ),
            .init(
                title: "你的内容",
                body: "你保留对录音、录像和导入文件的权利。你应确保拥有录制、编辑和发布相关内容所需的授权，并尊重他人的著作权、肖像权、隐私权及其他合法权益。"
            ),
            .init(
                title: "禁止行为",
                body: "不得使用 MonoFrame 侵害他人权益、规避技术保护措施、制作或传播违法内容、攻击或干扰软件安全。开源许可证明确允许的行为不受本条限制。"
            ),
            .init(
                title: "软件与开源组件",
                body: "MonoFrame 的产品界面、品牌和非开源代码受相关法律保护。FFmpeg、LAME 和 Swift 封装层分别适用其开源许可证；本协议不削减这些许可证授予你的权利。"
            ),
            .init(
                title: "更新与停止使用",
                body: "功能可能因系统、设备、编解码器或合规要求调整。你可以随时停止使用并删除 App 及本地文件。法律另有强制规定的，从其规定。"
            )
        ]
    }

    private var disclaimerSections: [LegalSection] {
        [
            .init(
                title: "处理结果",
                body: "不同设备、系统版本、编码格式和源文件状态可能影响录制、预览、转码、逐帧定位或导出结果。重要内容请在导出后检查。"
            ),
            .init(
                title: "文件备份",
                body: "编辑、转码、清理缓存或删除 App 前，请自行保留原始文件和必要备份。设备空间不足、系统中断或文件损坏可能导致任务失败。"
            ),
            .init(
                title: "内容责任",
                body: "你应对录制、导入、编辑、保存和分享的内容及其合法性负责。MonoFrame 不授予任何第三方音乐、影像、商标或人物形象的使用权。"
            ),
            .init(
                title: "责任限制",
                body: "在适用法律允许的最大范围内，MonoFrame 按现状提供，不保证所有格式、设备或场景均可用。任何条款均不排除或限制法律规定不得排除或限制的消费者权利及责任。"
            )
        ]
    }

    private var privacySections: [LegalSection] {
        [
            .init(
                title: "不收集到服务器",
                body: "MonoFrame 不要求账号，不含广告、统计或跨 App 跟踪，也不会把你的录音、录像、导入媒体或使用记录上传到开发者服务器。"
            ),
            .init(
                title: "设备端处理",
                body: "你选择的媒体、麦克风音频、系统录屏样本和编辑参数仅用于在设备上完成录制、预览、剪辑、转码和导出。FFmpeg 与 LAME 同样在设备本地运行，不会自行传输数据。"
            ),
            .init(
                title: "权限",
                body: "麦克风权限用于录音；照片添加权限用于保存视频和 Live Photo；媒体组件包含相机视频输入接口，只有在你主动启用相关功能并允许后才会访问相机；文件选择器仅向 MonoFrame 提供你主动选择的文件。你可以随时在 iOS 设置中撤回权限。"
            ),
            .init(
                title: "保存与删除",
                body: "作品和临时文件保存在 App 沙盒或 App Group 容器中，直至你删除作品、清理转码缓存或卸载 App。通过系统分享或照片导出后的副本由对应 App 或系统管理。"
            ),
            .init(
                title: "你的权利",
                body: "你可以查看、导出或删除本地作品，清理临时文件，撤回系统权限，并通过卸载 App 删除其本地容器。由于 MonoFrame 不建立服务器账户，也不持有服务器端个人资料，因此不存在需要开发者代为删除的云端账户数据。"
            ),
            .init(
                title: "分享与联系",
                body: "只有在你主动使用系统分享、照片保存或文件导出时，内容才会交给你选择的目标。隐私问题可通过 App Store 产品页面中的开发者支持渠道联系。"
            )
        ]
    }
}

struct LegalSection {
    let title: String
    let body: String
}

struct LegalLink: Identifiable {
    let title: String
    let url: String

    var id: String { url }
}

struct LegalDocumentView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                Text("生效日期 2026.07.19")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(MonoTheme.muted(scheme))
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                    legalSection(section)
                }

                if !document.links.isEmpty {
                    links
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .background { SignalPageBackground() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 22) {
                Button { dismiss() } label: {
                    MonoIcon("arrow.left", size: 18, weight: 2.2)
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.12))
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 17))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")

                Text(document.title)
                    .font(.system(size: 29, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(.trailing, 64)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 172, alignment: .leading)
            .background(SignalColor.stage)
            .clipShape(YouthNotchedPanelShape(cornerRadius: 34, notchWidth: 94, notchDepth: 62))

            YouthStatusBubble(value: "DOC", symbol: document.icon)
                .padding(8)
        }
        .padding(.top, 8)
    }

    private func legalSection(_ section: LegalSection) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(section.title)
                .font(.system(.headline, design: .rounded, weight: .black))
            Text(section.body)
                .font(.system(.subheadline, design: .rounded, weight: .regular))
                .foregroundStyle(MonoTheme.muted(scheme))
                .lineSpacing(4)
                .textSelection(.enabled)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(MonoTheme.muted(scheme).opacity(0.2))
        }
    }

    private var links: some View {
        VStack(spacing: 0) {
            ForEach(Array(document.links.enumerated()), id: \.element.id) { index, item in
                if let url = URL(string: item.url) {
                    Link(destination: url) {
                        HStack(spacing: 12) {
                            Text(item.title)
                                .font(.system(.subheadline, design: .rounded, weight: .black))
                                .multilineTextAlignment(.leading)
                            Spacer()
                            MonoIcon("arrow.up.right", size: 17, weight: 2.1)
                                .font(.system(size: 12, weight: .black))
                        }
                        .foregroundStyle(MonoTheme.ink(scheme))
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }

                    if index < document.links.count - 1 {
                        Divider()
                            .overlay(MonoTheme.muted(scheme).opacity(0.2))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .monoPanel()
    }
}
