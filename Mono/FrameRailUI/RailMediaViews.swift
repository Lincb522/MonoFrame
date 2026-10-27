import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct RailStudioView: View {
    enum Kind: String, CaseIterable { case video = "视频"; case audio = "音频" }

    @State private var kind: Kind = .video
    @State private var importing = false
    @State private var importedVideo: Recording?
    @State private var importedAudio: AudioRecording?
    @State private var errorMessage: String?
    @EnvironmentObject private var library: RecordingLibrary

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                RailPageHeader(title: "创作工作台")
                    .railEntrance()
                RailSegmented(values: Kind.allCases.map { ($0, $0.rawValue) }, selection: $kind)
                    .railEntrance(delay: 0.04)
                importWorkspace
                    .railEntrance(delay: 0.08)
            }
            .railPagePadding()
            .padding(.bottom, 116)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: kind == .video ? [.movie] : [.audio],
            allowsMultipleSelection: false
        ) { result in Task { await importMedia(result) } }
        .navigationDestination(isPresented: Binding(
            get: { importedVideo != nil },
            set: { if !$0 { importedVideo = nil } }
        )) {
            if let importedVideo { RailVideoEditorView(recording: importedVideo) }
        }
        .navigationDestination(isPresented: Binding(
            get: { importedAudio != nil },
            set: { if !$0 { importedAudio = nil } }
        )) {
            if let importedAudio { RailAudioEditorView(recording: importedAudio) }
        }
        .alert("无法导入素材", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "请稍后重试") }
    }

    private var importWorkspace: some View {
        Button { importing = true } label: {
            VStack(spacing: 0) {
                VStack(spacing: 18) {
                    ZStack {
                        ForEach(0..<3, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(index == 1 ? RailColor.blue.opacity(0.72) : index == 2 ? RailColor.coral : Color.white.opacity(0.14))
                                .frame(height: index == 1 ? 48 : 34)
                                .padding(.horizontal, CGFloat(index) * 18)
                                .offset(y: CGFloat(index - 1) * 28)
                        }
                        Rectangle().fill(.white).frame(width: 2, height: 126)
                            .overlay(alignment: .top) { Circle().fill(RailColor.coral).frame(width: 10, height: 10) }
                    }
                    .frame(height: 138)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("选择文件")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                            Text(kind == .video ? "MOV / MP4  ·  保留原件" : "M4A / WAV / FLAC  ·  保留原件")
                                .font(.system(.caption, design: .monospaced, weight: .medium))
                                .foregroundStyle(.white.opacity(0.58))
                        }
                        Spacer()
                        RailGlyph(systemName: "plus")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(RailColor.coral)
                            .clipShape(Circle())
                    }
                }
                .padding(18)
            }
            .foregroundStyle(.white)
            .background(Color(red: 0.055, green: 0.06, blue: 0.075))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .top) { Rectangle().fill(kind == .video ? RailColor.blue : RailColor.coral).frame(height: 3) }
        }
        .buttonStyle(RailPressStyle())
        .accessibilityHint("打开文件选择器")
    }

    @MainActor private func importMedia(_ result: Result<[URL], Error>) async {
        do {
            guard let source = try result.get().first else { return }
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            try SharedStorage.prepare()
            let directory = kind == .video ? SharedStorage.localDirectory : SharedStorage.audioDirectory
            let fallback = kind == .video ? "mp4" : "m4a"
            let ext = source.pathExtension.isEmpty ? fallback : source.pathExtension
            let target = directory.appendingPathComponent("Import-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: source, to: target)
            let duration = (try? await AVURLAsset(url: target).load(.duration).seconds) ?? 0
            let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
            let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            if kind == .video {
                importedVideo = Recording(id: UUID(), url: target, createdAt: .now, duration: duration, byteCount: bytes)
            } else {
                importedAudio = AudioRecording(id: UUID(), url: target, createdAt: .now, duration: duration, byteCount: bytes)
            }
            await library.reload()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct RailLibraryView: View {
    enum Filter: String, CaseIterable { case video = "视频"; case audio = "音频" }

    @State private var filter: Filter = .video
    @State private var query = ""
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                RailPageHeader(title: "素材库") {
                    RailIconButton(symbol: "arrow.clockwise", title: nil) { Task { await library.reload() } }
                }
                .railEntrance()
                search
                    .railEntrance(delay: 0.04)
                RailSegmented(
                    values: [
                        (Filter.video, "视频 \(library.recordings.count)"),
                        (Filter.audio, "音频 \(library.audioRecordings.count)")
                    ],
                    selection: $filter
                )
                    .railEntrance(delay: 0.08)
                content
                    .railEntrance(delay: 0.12)
            }
            .railPagePadding()
            .padding(.bottom, 116)
            .frame(maxWidth: 840)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var search: some View {
        HStack(spacing: 10) {
            RailGlyph(systemName: "magnifyingglass").foregroundStyle(RailColor.secondary(scheme))
            TextField("搜索素材", text: $query).font(.system(.body, design: .rounded))
            if !query.isEmpty {
                Button { query = "" } label: { RailGlyph(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(RailColor.secondary(scheme))
            }
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 48)
        .background(RailColor.surface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        let videos = filteredVideos
        let audio = filteredAudio
        if library.isLoading && library.recordings.isEmpty && library.audioRecordings.isEmpty {
            ProgressView("正在建立素材索引").frame(maxWidth: .infinity, minHeight: 180)
        } else if filter == .video, videos.isEmpty {
            RailSurface { RailEmptyState(title: query.isEmpty ? "还没有录屏" : "没有匹配结果", detail: "完成录制后会自动出现在这里", symbol: "rectangle.dashed") }
        } else if filter == .audio, audio.isEmpty {
            RailSurface { RailEmptyState(title: query.isEmpty ? "还没有录音" : "没有匹配结果", detail: "从录制页进入录音机开始创作", symbol: "waveform") }
        } else if filter == .video {
            LazyVStack(spacing: 10) {
                ForEach(videos) { item in
                    NavigationLink(value: item) { RailVideoLibraryRow(recording: item) }
                        .buttonStyle(RailPressStyle())
                        .contextMenu {
                            Button(role: .destructive) { library.delete(item) } label: {
                                RailLabel("删除", systemImage: "trash")
                            }
                        }
                }
            }
        } else {
            LazyVStack(spacing: 10) {
                ForEach(audio) { item in
                    NavigationLink(value: item) {
                        HStack(spacing: 14) {
                            RailMiniTrack(seed: item.id.hashValue, tint: RailColor.coral).frame(width: 82, height: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.system(.body, design: .rounded, weight: .bold)).lineLimit(1)
                                Text("\(item.durationText) · \(item.formatText) · \(item.sizeText)")
                                    .font(.system(.caption, design: .monospaced)).foregroundStyle(RailColor.secondary(scheme)).lineLimit(1)
                            }
                            Spacer()
                            RailGlyph(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(RailColor.coral)
                        }
                        .foregroundStyle(RailColor.ink(scheme))
                        .padding(14)
                        .background(RailColor.surface(scheme))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(RailPressStyle())
                    .contextMenu {
                        Button(role: .destructive) { library.delete(item) } label: {
                            RailLabel("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
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

private struct RailVideoLibraryRow: View {
    let recording: Recording
    @State private var thumbnail: UIImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill() }
                else { ZStack { Color.black; RailGlyph(systemName: "film").foregroundStyle(.white.opacity(0.55)) } }
            }
            .frame(width: 104, height: 68)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Text(recording.durationText)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                    .background(.black.opacity(0.72))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(recording.title).font(.system(.body, design: .rounded, weight: .bold)).lineLimit(1)
                Text("\(recording.url.pathExtension.uppercased()) · \(recording.sizeText)")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(RailColor.secondary(scheme)).lineLimit(1)
            }
            Spacer()
            RailGlyph(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(RailColor.coral)
        }
        .foregroundStyle(RailColor.ink(scheme))
        .padding(12)
        .background(RailColor.surface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task { thumbnail = await ThumbnailLoader.image(for: recording.url) }
    }
}

struct RailMiniTrack: View {
    let seed: Int
    var tint = RailColor.coral

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<16, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 6) ? tint : tint.opacity(0.34))
                    .frame(maxWidth: .infinity)
                    .frame(height: CGFloat(5 + abs((seed &+ index * 17) % 30)))
            }
        }
        .accessibilityHidden(true)
    }
}
