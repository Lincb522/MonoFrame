import SwiftUI
import UIKit

struct SignalLibraryView: View {
    enum MediaFilter: String, CaseIterable { case video = "视频"; case audio = "音频" }

    @State private var filter: MediaFilter = .video
    @State private var query = ""
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: SignalSpace.md) {
                SignalPageHeader(
                    title: "你的片场",
                    detail: "所有录屏与声音，都在这里",
                    action: AnyView(
                        SignalIconButton(symbol: "arrow.clockwise", label: "刷新") {
                            Task { await library.reload() }
                        }
                    )
                )

                libraryOverview
                    .youthStageEntrance()
                searchField
                    .youthDelayedReveal(delay: 0.38)
                SignalSegmentedControl(
                    values: MediaFilter.allCases.map { ($0, $0.rawValue) },
                    selection: $filter
                )
                .youthDelayedReveal(delay: 0.44)

                if filter == .video { videoContent } else { audioContent }
            }
            .signalPagePadding()
            .padding(.bottom, 124)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .refreshable { await library.reload() }
    }

    private var searchField: some View {
        HStack(spacing: SignalSpace.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(SignalColor.secondary(scheme))
            TextField("搜索文件", text: $query)
                .font(.system(.body, design: .rounded))
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(SignalColor.secondary(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, SignalSpace.md)
        .frame(minHeight: 48)
        .background(SignalColor.surface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var libraryOverview: some View {
        let total = library.recordings.count + library.audioRecordings.count
        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本机创作")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                    YouthCountingText(value: Double(total))
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(SignalColor.acid)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<8, id: \.self) { index in
                        let source = index.isMultiple(of: 2) ? library.recordings.count : library.audioRecordings.count
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(index == 5 ? SignalColor.acid : Color.white.opacity(index < 4 ? 0.9 : 0.22))
                            .frame(maxWidth: .infinity)
                            .frame(height: CGFloat(22 + ((source + index * 13) % 5) * 12))
                    }
                }
                .frame(height: 76)

                HStack(spacing: 16) {
                    Label("\(library.recordings.count) 视频", systemImage: "play.rectangle.fill")
                    Label("\(library.audioRecordings.count) 音频", systemImage: "waveform")
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 230, alignment: .leading)
            .background(SignalColor.stage)
            .clipShape(YouthNotchedPanelShape(cornerRadius: 34, notchWidth: 94, notchDepth: 62))

            YouthStatusBubble(value: "\(total)", symbol: "sparkles")
                .padding(8)

            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 5)
                YouthRingSegment(
                    from: 0.06,
                    to: 0.92,
                    animationProgress: total == 0 ? 0.24 : 0.92,
                    tint: SignalColor.acid,
                    lineWidth: 5
                )
                .rotationEffect(.degrees(-90))
            }
            .frame(width: 48, height: 48)
            .padding(.trailing, 18)
            .padding(.top, 104)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var videoContent: some View {
        let items = filteredVideos
        if library.isLoading && library.recordings.isEmpty {
            loadingRows
        } else if items.isEmpty {
            emptyState(
                title: query.isEmpty ? "还没有录屏" : "没有匹配的录屏",
                detail: query.isEmpty ? "完成一次屏幕录制后，文件会自动出现在这里" : "尝试缩短关键词",
                symbol: "rectangle.dashed"
            )
        } else {
            SignalPanel {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: item) {
                            SignalVideoRow(recording: item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("删除", systemImage: "trash", role: .destructive) { library.delete(item) }
                        }
                        if index < items.count - 1 { SignalRule().padding(.leading, 116) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var audioContent: some View {
        let items = filteredAudio
        if library.isLoading && library.audioRecordings.isEmpty {
            loadingRows
        } else if items.isEmpty {
            emptyState(
                title: query.isEmpty ? "还没有录音" : "没有匹配的录音",
                detail: query.isEmpty ? "从录屏页进入录音机即可开始" : "尝试缩短关键词",
                symbol: "waveform"
            )
        } else {
            SignalPanel {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: item) {
                            HStack(spacing: SignalSpace.sm) {
                                SignalAudioGlyph(seed: item.id.hashValue)
                                    .frame(width: 84, height: 42)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.system(.body, design: .rounded, weight: .bold)).lineLimit(1)
                                    Text("\(item.durationText) · \(item.formatText) · \(item.sizeText)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(SignalColor.secondary(scheme))
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(SignalColor.secondary(scheme))
                            }
                            .foregroundStyle(SignalColor.ink(scheme))
                            .padding(.horizontal, SignalSpace.md)
                            .frame(minHeight: 72)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("删除", systemImage: "trash", role: .destructive) { library.delete(item) }
                        }
                        if index < items.count - 1 { SignalRule().padding(.leading, 116) }
                    }
                }
            }
        }
    }

    private var loadingRows: some View {
        VStack(spacing: 1) {
            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: SignalSpace.sm) {
                    RoundedRectangle(cornerRadius: 8).fill(SignalColor.raised(scheme)).frame(width: 88, height: 58)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(SignalColor.raised(scheme)).frame(width: 120, height: 12)
                        RoundedRectangle(cornerRadius: 3).fill(SignalColor.raised(scheme)).frame(width: 180, height: 9)
                    }
                    Spacer()
                }
                .padding(.horizontal, SignalSpace.md)
                .frame(height: 82)
                .opacity(1 - Double(index) * 0.14)
            }
        }
        .background(SignalColor.surface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("正在载入作品")
    }

    private func emptyState(title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: SignalSpace.md) {
            TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { context in
                SignalEmptyReel(
                    symbol: symbol,
                    phase: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                )
            }
            VStack(spacing: SignalSpace.xs) {
                Text(title).font(.system(.title3, design: .rounded, weight: .bold))
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(SignalColor.secondary(scheme))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .accessibilityElement(children: .combine)
    }

    private var filteredVideos: [Recording] {
        guard !query.isEmpty else { return library.recordings }
        return library.recordings.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) }
    }

    private var filteredAudio: [AudioRecording] {
        guard !query.isEmpty else { return library.audioRecordings }
        return library.audioRecordings.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) }
    }
}

private struct SignalVideoRow: View {
    let recording: Recording
    @State private var thumbnail: UIImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: SignalSpace.sm) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    ZStack {
                        SignalColor.stageRaised
                        Image(systemName: "film").foregroundStyle(Color.white.opacity(0.54))
                    }
                }
            }
            .frame(width: 88, height: 58)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Text(recording.durationText)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                    .background(Color.black.opacity(0.70))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title).font(.system(.body, design: .rounded, weight: .bold)).lineLimit(1)
                Text("\(recording.url.pathExtension.uppercased()) · \(recording.sizeText)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(SignalColor.secondary(scheme))
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(SignalColor.secondary(scheme))
        }
        .foregroundStyle(SignalColor.ink(scheme))
        .padding(.horizontal, SignalSpace.md)
        .frame(minHeight: 82)
        .contentShape(Rectangle())
        .task { thumbnail = await ThumbnailLoader.image(for: recording.url) }
    }
}

private struct SignalEmptyReel: View {
    let symbol: String
    let phase: TimeInterval

    var body: some View {
        let shift = CGFloat(sin(phase * 1.45)) * 3
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
                .frame(width: 112, height: 72)
                .rotationEffect(.degrees(-6 + Double(shift)))
                .offset(x: -8, y: 5)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 112, height: 72)
                .rotationEffect(.degrees(5 - Double(shift)))
                .offset(x: 8, y: -4)
            Circle()
                .fill(SignalColor.coral.opacity(0.12))
                .frame(width: 54, height: 54)
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(SignalColor.coral)
        }
        .frame(width: 140, height: 94)
        .accessibilityHidden(true)
    }
}

private struct SignalAudioGlyph: View {
    let seed: Int

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<18, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 5) ? SignalColor.coral : Color.secondary.opacity(0.34))
                    .frame(maxWidth: .infinity)
                    .frame(height: CGFloat(6 + abs((seed &+ index * 13) % 28)))
            }
        }
        .accessibilityHidden(true)
    }
}
