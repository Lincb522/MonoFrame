import SwiftUI
import UIKit

// MARK: - Onboarding

struct CanvasOnboardingFlow: View {
    private enum Stage {
        case welcome
        case permissions
    }

    private let needsWelcome: Bool
    private let needsPermissions: Bool
    private let welcomeCompleted: () -> Void
    private let completion: () -> Void

    @State private var stage: Stage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        needsWelcome: Bool,
        needsPermissions: Bool,
        welcomeCompleted: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        self.needsWelcome = needsWelcome
        self.needsPermissions = needsPermissions
        self.welcomeCompleted = welcomeCompleted
        self.completion = completion
        _stage = State(initialValue: needsWelcome ? .welcome : .permissions)
    }

    var body: some View {
        ZStack {
            CanvasBackdrop()
            switch stage {
            case .welcome:
                CanvasWelcomeView(completion: finishWelcome)
                    .transition(.opacity)
            case .permissions:
                CanvasPermissionView(completion: completion)
                    .transition(.opacity)
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            if !needsWelcome, !needsPermissions {
                completion()
            }
        }
        .accessibilityIdentifier("canvas.onboarding.flow")
    }

    private func finishWelcome() {
        welcomeCompleted()
        guard needsPermissions else {
            completion()
            return
        }

        if reduceMotion {
            stage = .permissions
        } else {
            withAnimation(.easeOut(duration: 0.22)) {
                stage = .permissions
            }
        }
    }
}

struct CanvasWelcomeView: View {
    let completion: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                brandHeader
                    .padding(.bottom, 34)

                VStack(alignment: .leading, spacing: 12) {
                    Text("一张画布，\n从录制延伸到成片。")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(CanvasColor.ink(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text("录屏、收音、编辑与格式转换都在设备上连续完成，不要求账号。")
                        .font(.body)
                        .foregroundStyle(CanvasColor.secondary(scheme))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                CanvasWelcomeMotionTrack()
                    .padding(.vertical, 34)

                capabilityList
                    .padding(.bottom, 30)

                CanvasInlineNotice(
                    message: "媒体默认留在本机。只有当你主动保存、导出或分享时，内容才会交给所选的系统目标。",
                    tone: .info
                )
                .padding(.bottom, 22)

                CanvasPrimaryGlassAction(
                    title: "进入连续画布",
                    glyph: .record,
                    action: completion
                )
                .accessibilityIdentifier("canvas.onboarding.continue")
            }
            .frame(maxWidth: 660, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(CanvasBackdrop())
        .accessibilityIdentifier("canvas.onboarding.welcome")
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            CanvasGlyph(.record, size: 23, weight: 1.85)
                .foregroundStyle(CanvasColor.accent(scheme))
                .frame(width: 44, height: 44)
                .overlay {
                    Circle().stroke(CanvasColor.hairline(scheme), lineWidth: 0.8)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("MonoFrame")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(CanvasColor.ink(scheme))
                Text("CANVAS / LOCAL")
                    .font(.caption2.monospaced().weight(.medium))
                    .foregroundStyle(CanvasColor.tertiary(scheme))
            }

            Spacer(minLength: 12)

            Text("本地优先")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CanvasColor.accent(scheme))
                .padding(.horizontal, 11)
                .frame(minHeight: 34)
                .background(
                    CanvasColor.accent(scheme).opacity(scheme == .dark ? 0.13 : 0.075),
                    in: Capsule()
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("MonoFrame，本地优先")
    }

    private var capabilityList: some View {
        VStack(spacing: 0) {
            capabilityRow(
                glyph: .record,
                title: "录制",
                detail: "系统画面与麦克风输入各自清晰可控"
            )
            CanvasHairline().padding(.leading, 58)
            capabilityRow(
                glyph: .edit,
                title: "编辑",
                detail: "视频、音频、字幕在同一条工作流里继续"
            )
            CanvasHairline().padding(.leading, 58)
            capabilityRow(
                glyph: .export,
                title: "交付",
                detail: "转码、保存与分享由你最后确认"
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CanvasColor.hairline(scheme), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
    }

    private func capabilityRow(
        glyph: CanvasGlyphName,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            CanvasGlyph(glyph, size: 20)
                .foregroundStyle(CanvasColor.accent(scheme))
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(CanvasColor.ink(scheme))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(CanvasColor.secondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct CanvasWelcomeMotionTrack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                CanvasWelcomeTrack(progress: 0.62)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 24)) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 5.6) / 5.6
                    CanvasWelcomeTrack(progress: phase)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("录制、编辑、作品、转码和导出的连续流程")
    }
}

private struct CanvasWelcomeTrack: View {
    private let stages: [(String, CanvasGlyphName)] = [
        ("录制", .record),
        ("编辑", .edit),
        ("作品", .library),
        ("转码", .transcode),
        ("导出", .export)
    ]

    let progress: Double

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                SwiftUI.Canvas { context, size in
                    let inset: CGFloat = 23
                    let y = size.height / 2

                    var baseline = Path()
                    baseline.move(to: CGPoint(x: inset, y: y))
                    baseline.addLine(to: CGPoint(x: max(inset, size.width - inset), y: y))
                    context.stroke(
                        baseline,
                        with: .color(CanvasColor.hairline(scheme)),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 4])
                    )

                    var completed = Path()
                    completed.move(to: CGPoint(x: inset, y: y))
                    completed.addLine(
                        to: CGPoint(
                            x: inset + max(0, size.width - inset * 2) * CGFloat(progress),
                            y: y
                        )
                    )
                    context.stroke(
                        completed,
                        with: .color(CanvasColor.accent(scheme)),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                    )
                }

                HStack(spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                        let isReached = Double(index) / Double(stages.count - 1) <= progress
                        CanvasGlyph(stage.1, size: 18, weight: 1.7)
                            .foregroundStyle(
                                isReached
                                    ? CanvasColor.accent(scheme)
                                    : CanvasColor.secondary(scheme)
                            )
                            .frame(width: 44, height: 44)
                            .background(CanvasColor.background(scheme), in: Circle())
                            .overlay {
                                Circle().stroke(
                                    isReached
                                        ? CanvasColor.accent(scheme).opacity(0.45)
                                        : CanvasColor.hairline(scheme),
                                    lineWidth: 0.9
                                )
                            }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 58)

            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { _, stage in
                        Text(stage.0)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(CanvasColor.tertiary(scheme))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - Permissions

struct CanvasPermissionView: View {
    let completion: () -> Void

    @StateObject private var permissions = PermissionCenter()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("只在需要时访问")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(CanvasColor.ink(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text("照片权限用于保存作品；麦克风权限用于录制声音。你可以稍后在系统设置中更改。")
                        .font(.body)
                        .foregroundStyle(CanvasColor.secondary(scheme))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 30)

                permissionList
                    .padding(.bottom, 22)

                HStack(alignment: .top, spacing: 14) {
                    CanvasGlyph(.folder, size: 20)
                        .foregroundStyle(CanvasColor.accent(scheme))
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("设备端处理")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(CanvasColor.ink(scheme))
                        Text("文件选择器只会向 MonoFrame 提供你主动选择的内容。")
                            .font(.subheadline)
                            .foregroundStyle(CanvasColor.secondary(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .padding(.bottom, 22)

                if permissions.hasDeniedAccess {
                    CanvasInlineNotice(
                        message: "有权限已关闭或为有限访问。前往系统设置即可重新选择。",
                        tone: .warning
                    )
                    .padding(.bottom, 18)
                }

                CanvasPrimaryGlassAction(
                    title: permissions.isRequesting ? "正在请求权限" : primaryTitle,
                    glyph: primaryGlyph,
                    isEnabled: !permissions.isRequesting,
                    action: primaryAction
                )
                .accessibilityIdentifier("canvas.permissions.primary")

                if permissions.hasDeniedAccess || permissions.hasUndeterminedAccess {
                    Button("稍后设置", action: completion)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CanvasColor.secondary(scheme))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                        .buttonStyle(CanvasPressStyle())
                        .accessibilityHint("现在进入 MonoFrame，之后仍可在系统设置中授权")
                        .accessibilityIdentifier("canvas.permissions.skip")
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: 660, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(CanvasBackdrop())
        .onAppear(perform: permissions.refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                permissions.refresh()
            }
        }
        .accessibilityIdentifier("canvas.onboarding.permissions")
    }

    private var permissionList: some View {
        VStack(spacing: 0) {
            permissionRow(
                title: "照片",
                detail: "保存视频与 Live Photo",
                glyph: .image,
                state: permissions.photo
            )
            CanvasHairline().padding(.leading, 68)
            permissionRow(
                title: "麦克风",
                detail: "录音与录屏时采集你的声音",
                glyph: .microphone,
                state: permissions.microphone
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CanvasColor.hairline(scheme), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        detail: String,
        glyph: CanvasGlyphName,
        state: PermissionCenter.AccessState
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    permissionIdentity(title: title, detail: detail, glyph: glyph)
                    permissionStatus(state, title: title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 54)
                }
            } else {
                HStack(spacing: 14) {
                    permissionIdentity(title: title, detail: detail, glyph: glyph)
                    Spacer(minLength: 12)
                    permissionStatus(state, title: title)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(state.title)
    }

    private func permissionIdentity(
        title: String,
        detail: String,
        glyph: CanvasGlyphName
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CanvasGlyph(glyph, size: 20)
                .foregroundStyle(CanvasColor.accent(scheme))
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(CanvasColor.ink(scheme))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(CanvasColor.secondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func permissionStatus(
        _ state: PermissionCenter.AccessState,
        title: String
    ) -> some View {
        HStack(spacing: 7) {
            CanvasGlyph(statusGlyph(state), size: 15, weight: 1.9)
                .accessibilityHidden(true)
            Text(state.title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(permissionColor(state))
        .frame(minHeight: 44)
        .accessibilityLabel("\(title)：\(state.title)")
    }

    private func statusGlyph(_ state: PermissionCenter.AccessState) -> CanvasGlyphName {
        switch state {
        case .allowed: .check
        case .limited: .more
        case .denied: .close
        case .notDetermined: .more
        }
    }

    private func permissionColor(_ state: PermissionCenter.AccessState) -> Color {
        switch state {
        case .allowed:
            CanvasColor.accent(scheme)
        case .limited:
            scheme == .dark
                ? Color(red: 0.96, green: 0.73, blue: 0.35)
                : Color(red: 0.50, green: 0.29, blue: 0.02)
        case .denied:
            CanvasColor.danger(scheme)
        case .notDetermined:
            CanvasColor.secondary(scheme)
        }
    }

    private var primaryTitle: String {
        if permissions.hasDeniedAccess { return "打开系统设置" }
        if permissions.hasUndeterminedAccess { return "允许所需权限" }
        return "进入 MonoFrame"
    }

    private var primaryGlyph: CanvasGlyphName {
        if permissions.hasDeniedAccess { return .settings }
        if permissions.hasUndeterminedAccess { return .check }
        return .chevronRight
    }

    private func primaryAction() {
        if permissions.hasDeniedAccess {
            guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(settingsURL)
        } else if permissions.hasUndeterminedAccess {
            Task {
                await permissions.requestAccess()
            }
        } else {
            completion()
        }
    }
}

// MARK: - Legal documents

struct CanvasLegalDocumentView: View {
    let document: LegalDocument

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                documentHeader
                    .padding(.bottom, 8)

                ForEach(Array(document.sections.enumerated()), id: \.offset) { index, section in
                    legalSection(section, index: index)
                    if index < document.sections.count - 1 {
                        CanvasHairline()
                    }
                }

                if !document.links.isEmpty {
                    externalLinks
                        .padding(.top, 34)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 54)
        }
        .scrollIndicators(.hidden)
        .background(CanvasBackdrop())
        .canvasNavigationTitle(document.title)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: dismiss.callAsFunction) {
                    CanvasGlyph(.back, size: 20)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(CanvasPressStyle())
                .accessibilityLabel("返回")
                .accessibilityIdentifier("canvas.legal.back")
            }
        }
        .accessibilityIdentifier("canvas.legal.\(document.rawValue)")
    }

    private var documentHeader: some View {
        HStack(alignment: .center, spacing: 15) {
            CanvasGlyph(documentGlyph, size: 24, weight: 1.85)
                .foregroundStyle(CanvasColor.accent(scheme))
                .frame(width: 50, height: 50)
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(CanvasColor.hairline(scheme), lineWidth: 0.8)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(document.sections.count) 个章节")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CanvasColor.ink(scheme))
                Text("在本机阅读，可选择文字")
                    .font(.caption)
                    .foregroundStyle(CanvasColor.tertiary(scheme))
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func legalSection(_ section: LegalSection, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(String(format: "%02d", index + 1))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(CanvasColor.accent(scheme))
                .accessibilityHidden(true)

            Text(section.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(CanvasColor.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(section.body)
                .font(.body)
                .foregroundStyle(CanvasColor.secondary(scheme))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 22)
        .accessibilityIdentifier("canvas.legal.\(document.rawValue).section.\(index)")
    }

    private var externalLinks: some View {
        VStack(alignment: .leading, spacing: 10) {
            CanvasSectionLabel("外部资源")

            VStack(spacing: 0) {
                ForEach(Array(document.links.enumerated()), id: \.element.id) { index, link in
                    externalLink(link)
                    if index < document.links.count - 1 {
                        CanvasHairline()
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CanvasColor.hairline(scheme), lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func externalLink(_ link: LegalLink) -> some View {
        if let destination = URL(string: link.url) {
            Link(destination: destination) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(link.title)
                        .font(.body)
                        .foregroundStyle(CanvasColor.ink(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 10)
                    CanvasGlyph(.export, size: 17)
                        .foregroundStyle(CanvasColor.accent(scheme))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(CanvasPressStyle())
            .accessibilityLabel("打开外部资源：\(link.title)")
            .accessibilityHint("将在浏览器中打开")
        }
    }

    private var documentGlyph: CanvasGlyphName {
        switch document {
        case .ffmpeg: .format
        case .userAgreement: .document
        case .disclaimer: .more
        case .privacyRights: .settings
        }
    }
}

// MARK: - Reusable lyric reader

/// A transport-neutral line model for lyric readers outside the recorder's
/// private sheet. Keeping it independent avoids coupling utility UI to a
/// particular recording service lifecycle.
struct CanvasLyricReadingLine: Identifiable, Equatable, Sendable {
    let id: Int
    let time: TimeInterval?
    let text: String

    init(id: Int, time: TimeInterval? = nil, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }
}

struct CanvasLyricReadingView: View {
    let title: String
    let lines: [CanvasLyricReadingLine]
    let currentIndex: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String = "歌词",
        lines: [CanvasLyricReadingLine],
        currentIndex: Int? = nil
    ) {
        self.title = title
        self.lines = lines
        self.currentIndex = currentIndex
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackdrop()

                if lines.isEmpty {
                    CanvasTertiaryEmptyState(
                        glyph: .captions,
                        title: "没有可读歌词",
                        message: "导入 LRC 或纯文本歌词后会显示在这里。"
                    )
                    .padding(24)
                } else {
                    lyricList
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("\(lines.count) 行")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CanvasColor.tertiary(scheme))
                        .accessibilityLabel("共 \(lines.count) 行歌词")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: dismiss.callAsFunction) {
                        CanvasGlyph(.close, size: 18)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(CanvasPressStyle())
                    .accessibilityLabel("关闭歌词")
                    .accessibilityIdentifier("canvas.lyrics.close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(CanvasColor.background(scheme))
        .accessibilityIdentifier("canvas.lyrics.reader")
    }

    private var lyricList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        lyricRow(line, index: index)
                            .id(index)
                        if index < lines.count - 1 {
                            CanvasHairline().padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 68)
                        }
                    }
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                scrollToCurrent(using: proxy)
            }
            .onChange(of: currentIndex) { _, _ in
                scrollToCurrent(using: proxy)
            }
        }
    }

    @ViewBuilder
    private func lyricRow(_ line: CanvasLyricReadingLine, index: Int) -> some View {
        let selected = index == currentIndex

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(timestamp(line.time))
                        .font(.caption.monospacedDigit().weight(selected ? .semibold : .regular))
                        .foregroundStyle(
                            selected
                                ? CanvasColor.accent(scheme)
                                : CanvasColor.tertiary(scheme)
                        )
                    Text(line.text)
                        .font(selected ? .body.weight(.semibold) : .body)
                        .foregroundStyle(CanvasColor.ink(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(timestamp(line.time))
                        .font(.caption.monospacedDigit().weight(selected ? .semibold : .regular))
                        .foregroundStyle(
                            selected
                                ? CanvasColor.accent(scheme)
                                : CanvasColor.tertiary(scheme)
                        )
                        .frame(width: 52, alignment: .trailing)
                    Text(line.text)
                        .font(selected ? .body.weight(.semibold) : .body)
                        .foregroundStyle(CanvasColor.ink(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, selected ? 12 : 0)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(
            selected
                ? CanvasColor.accent(scheme).opacity(scheme == .dark ? 0.13 : 0.07)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .textSelection(.enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(timestamp(line.time))，\(line.text)")
        .accessibilityValue(selected ? "当前歌词" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("canvas.lyrics.line.\(line.id)")
    }

    private func scrollToCurrent(using proxy: ScrollViewProxy) {
        guard let currentIndex, lines.indices.contains(currentIndex) else { return }
        if reduceMotion {
            proxy.scrollTo(currentIndex, anchor: .center)
        } else {
            withAnimation(.easeOut(duration: 0.20)) {
                proxy.scrollTo(currentIndex, anchor: .center)
            }
        }
    }

    private func timestamp(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "—" }
        let wholeSeconds = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }
}

// MARK: - Empty states

struct CanvasSecondaryEmptyState: View {
    let glyph: CanvasGlyphName
    let title: String
    let message: String
    let actionTitle: String?
    let actionGlyph: CanvasGlyphName
    let action: (() -> Void)?

    init(
        glyph: CanvasGlyphName,
        title: String,
        message: String,
        actionTitle: String? = nil,
        actionGlyph: CanvasGlyphName = .plus,
        action: (() -> Void)? = nil
    ) {
        self.glyph = glyph
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.actionGlyph = actionGlyph
        self.action = action
    }

    var body: some View {
        CanvasEmptyStateBody(
            level: .secondary,
            glyph: glyph,
            title: title,
            message: message,
            actionTitle: actionTitle,
            actionGlyph: actionGlyph,
            action: action
        )
    }
}

struct CanvasTertiaryEmptyState: View {
    let glyph: CanvasGlyphName
    let title: String
    let message: String
    let actionTitle: String?
    let actionGlyph: CanvasGlyphName
    let action: (() -> Void)?

    init(
        glyph: CanvasGlyphName,
        title: String,
        message: String,
        actionTitle: String? = nil,
        actionGlyph: CanvasGlyphName = .refresh,
        action: (() -> Void)? = nil
    ) {
        self.glyph = glyph
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.actionGlyph = actionGlyph
        self.action = action
    }

    var body: some View {
        CanvasEmptyStateBody(
            level: .tertiary,
            glyph: glyph,
            title: title,
            message: message,
            actionTitle: actionTitle,
            actionGlyph: actionGlyph,
            action: action
        )
    }
}

private struct CanvasEmptyStateBody: View {
    enum Level {
        case secondary
        case tertiary
    }

    let level: Level
    let glyph: CanvasGlyphName
    let title: String
    let message: String
    let actionTitle: String?
    let actionGlyph: CanvasGlyphName
    let action: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: level == .secondary ? 16 : 12) {
            CanvasGlyph(
                glyph,
                size: level == .secondary ? 28 : 22,
                weight: 1.8
            )
            .foregroundStyle(CanvasColor.accent(scheme))
            .frame(
                width: level == .secondary ? 52 : 44,
                height: level == .secondary ? 52 : 44
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: level == .secondary ? 16 : 13,
                    style: .continuous
                )
                .stroke(CanvasColor.hairline(scheme), lineWidth: 0.8)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(level == .secondary ? .title3.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(CanvasColor.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(level == .secondary ? .body : .subheadline)
                    .foregroundStyle(CanvasColor.secondary(scheme))
                    .lineSpacing(level == .secondary ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 9) {
                        CanvasGlyph(actionGlyph, size: 17)
                            .accessibilityHidden(true)
                        Text(actionTitle)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(CanvasColor.accent(scheme))
                    .padding(.horizontal, 15)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .overlay {
                        Capsule().stroke(CanvasColor.hairline(scheme), lineWidth: 0.8)
                    }
                }
                .buttonStyle(CanvasPressStyle())
                .accessibilityLabel(actionTitle)
            }
        }
        .frame(maxWidth: level == .secondary ? 480 : 380, alignment: .leading)
        .padding(level == .secondary ? 26 : 18)
        .background {
            if level == .secondary {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(CanvasColor.surface(scheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(CanvasColor.hairline(scheme), lineWidth: 0.8)
                    }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Primary glass action

private struct CanvasPrimaryGlassAction: View {
    let title: String
    let glyph: CanvasGlyphName
    var isEnabled = true
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                CanvasGlyph(glyph, size: 19, weight: 1.9)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                CanvasGlyph(.chevronRight, size: 15, weight: 1.8)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(CanvasColor.background(scheme))
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
            .background {
                let shape = RoundedRectangle(cornerRadius: 19, style: .continuous)
                if reduceTransparency {
                    shape.fill(CanvasColor.accent(scheme))
                } else {
                    shape
                        .fill(.thinMaterial)
                        .overlay {
                            shape.fill(
                                CanvasColor.accent(scheme)
                                    .opacity(scheme == .dark ? 0.82 : 0.94)
                            )
                        }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(CanvasColor.glassEdge(scheme), lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(CanvasPressStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.58)
        .accessibilityLabel(title)
        .accessibilityValue(isEnabled ? "" : "正在处理")
    }
}
