import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct WildStudioView: View {
    enum Kind: String, CaseIterable { case video = "视频"; case audio = "音频" }
    @State private var kind: Kind = .video
    @State private var importing = false
    @State private var importedVideo: Recording?
    @State private var importedAudio: AudioRecording?
    @State private var errorMessage: String?
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                WildHeader("混剪实验室", kicker: "REMIX 02").wildEntrance()
                HStack(spacing: 12) {
                    WildSegmented(values: Kind.allCases.map { ($0, $0.rawValue) }, selection: $kind)
                    WildStamp(
                        text: kind == .video ? "FRAME" : "WAVE",
                        tint: kind == .video ? WildColor.blue : WildColor.orange,
                        foreground: kind == .video ? WildColor.onBlue : WildColor.onOrange
                    )
                }.wildEntrance(0.04)
                importStage.wildEntrance(0.08)
                if !library.recordings.isEmpty || !library.audioRecordings.isEmpty { sourceHint.wildEntrance(0.12) }
            }.wildPage().padding(.bottom, 120).frame(maxWidth: 820).frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden)
        .fileImporter(isPresented: $importing, allowedContentTypes: kind == .video ? [.movie] : [.audio], allowsMultipleSelection: false) { result in Task { await importMedia(result) } }
        .navigationDestination(isPresented: Binding(get: { importedVideo != nil }, set: { if !$0 { importedVideo = nil } })) { if let importedVideo { WildVideoEditorView(recording: importedVideo) } }
        .navigationDestination(isPresented: Binding(get: { importedAudio != nil }, set: { if !$0 { importedAudio = nil } })) { if let importedAudio { WildAudioEditorView(recording: importedAudio) } }
        .alert("无法导入素材", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("好", role: .cancel) { errorMessage = nil } } message: { Text(errorMessage ?? "请稍后重试") }
    }

    private var importStage: some View {
        Button { importing = true } label: {
            ZStack(alignment: .bottomLeading) {
                WildColor.stage(scheme)
                ForEach(0..<4, id: \.self) { i in
                    WildPanelShape(cut: 8).fill(i.isMultiple(of: 2) ? WildColor.blue.opacity(0.78) : WildColor.orange.opacity(0.76))
                        .frame(width: 175 + CGFloat(i) * 22, height: 34)
                        .rotationEffect(.degrees(Double(i - 2) * 3.4))
                        .offset(x: 92 + CGFloat(i) * 6, y: -88 + CGFloat(i) * 31)
                }
                Rectangle().fill(WildColor.stageInk(scheme)).frame(width: 3, height: 190).offset(x: 204, y: -46)
                VStack(alignment: .leading, spacing: 13) {
                    WildStamp(text: "DROP / PICK", tint: WildColor.acid)
                    Text(kind == .video ? "把画面扔进来" : "把声音扔进来")
                        .font(.system(size: 28, weight: .black, design: .rounded)).tracking(-0.8).foregroundStyle(WildColor.stageInk(scheme))
                    HStack {
                        Text(kind == .video ? "MOV · MP4" : "M4A · WAV · FLAC")
                            .font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(WildColor.stageSecondary(scheme))
                        Spacer()
                        RailGlyph(systemName: "plus").font(.system(size: 21, weight: .black)).foregroundStyle(WildColor.onAcid)
                            .frame(width: 52, height: 52).background(WildColor.acid).clipShape(WildTicketShape())
                    }
                }.padding(18)
            }.frame(minHeight: 330).clipShape(WildPanelShape(cut: 24)).shadow(color: WildColor.blue.opacity(0.18), radius: 12, x: 8, y: 10)
        }.buttonStyle(WildPressStyle()).accessibilityHint("打开文件选择器")
    }

    private var sourceHint: some View {
        WildSurface(tint: WildColor.violet) {
            HStack(spacing: 13) {
                RailGlyph(systemName: "rectangle.stack").font(.system(size: 18, weight: .black)).foregroundStyle(WildColor.onViolet)
                    .frame(width: 42, height: 42).background(WildColor.violet).clipShape(WildTicketShape())
                VStack(alignment: .leading, spacing: 2) {
                    Text("片库素材可直接开剪").font(.system(.subheadline, design: .rounded, weight: .black))
                    Text("视频 \(library.recordings.count) · 音频 \(library.audioRecordings.count)").font(.caption.monospaced()).foregroundStyle(WildColor.secondary(scheme))
                }
                Spacer(); RailGlyph(systemName: "arrow.right").foregroundStyle(WildColor.violet)
            }.foregroundStyle(WildColor.ink(scheme)).padding(14)
        }
    }

    @MainActor private func importMedia(_ result: Result<[URL], Error>) async {
        do {
            guard let source = try result.get().first else { return }
            let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
            try SharedStorage.prepare()
            let directory = kind == .video ? SharedStorage.localDirectory : SharedStorage.audioDirectory
            let fallback = kind == .video ? "mp4" : "m4a"; let ext = source.pathExtension.isEmpty ? fallback : source.pathExtension
            let target = directory.appendingPathComponent("Import-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: source, to: target)
            let duration = (try? await AVURLAsset(url: target).load(.duration).seconds) ?? 0
            let attributes = try FileManager.default.attributesOfItem(atPath: target.path); let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            if kind == .video { importedVideo = Recording(id: UUID(), url: target, createdAt: .now, duration: duration, byteCount: bytes) }
            else { importedAudio = AudioRecording(id: UUID(), url: target, createdAt: .now, duration: duration, byteCount: bytes) }
            await library.reload()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct WildLibraryView: View {
    enum Filter: String, CaseIterable { case video = "视频"; case audio = "音频" }
    @State private var filter: Filter = .video
    @State private var query = ""
    @EnvironmentObject private var library: RecordingLibrary
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                WildHeader("片库", kicker: "ARCHIVE 03") { WildIconButton(symbol: "arrow.clockwise", tint: WildColor.violet, foreground: WildColor.onViolet) { Task { await library.reload() } } }.wildEntrance()
                search.wildEntrance(0.04)
                WildSegmented(values: [(Filter.video,"视频 \(library.recordings.count)"),(Filter.audio,"音频 \(library.audioRecordings.count)")], selection: $filter).wildEntrance(0.08)
                content.wildEntrance(0.12)
            }.wildPage().padding(.bottom, 120).frame(maxWidth: 840).frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden)
    }

    private var search: some View {
        HStack(spacing: 10) {
            RailGlyph(systemName: "magnifyingglass").foregroundStyle(WildColor.violet)
            TextField("搜文件名", text: $query).font(.system(.body, design: .rounded, weight: .bold))
            if !query.isEmpty { Button { query = "" } label: { RailGlyph(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(WildColor.secondary(scheme)) }
        }.padding(.horizontal, 15).frame(minHeight: 50).background(WildColor.paper(scheme)).clipShape(WildPanelShape(cut: 10))
            .overlay { WildPanelShape(cut: 10).stroke(WildColor.rule(scheme), lineWidth: 1) }
    }

    @ViewBuilder private var content: some View {
        let videos = filteredVideos; let audio = filteredAudio
        if library.isLoading && library.recordings.isEmpty && library.audioRecordings.isEmpty { ProgressView("正在建立索引").frame(maxWidth: .infinity, minHeight: 180) }
        else if filter == .video, videos.isEmpty { WildSurface { WildEmptyState(title: query.isEmpty ? "没有录屏" : "没有命中", detail: "完成录制后自动归档", symbol: "rectangle.dashed") } }
        else if filter == .audio, audio.isEmpty { WildSurface { WildEmptyState(title: query.isEmpty ? "没有录音" : "没有命中", detail: "从开拍页进入录音机", symbol: "waveform") } }
        else if filter == .video {
            LazyVStack(spacing: 12) {
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: item) { WildVideoRow(recording: item, index: index) }.buttonStyle(WildPressStyle())
                        .contextMenu { Button(role: .destructive) { library.delete(item) } label: { RailLabel("删除", systemImage: "trash") } }
                }
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(Array(audio.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: item) {
                        HStack(spacing: 13) {
                            Text(String(format: "%02d", index + 1)).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(WildColor.onAcid)
                                .frame(width: 30, height: 44).background(WildColor.acid).clipShape(WildTicketShape())
                            WildMiniTrack(seed: item.id.hashValue).frame(width: 74, height: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.system(.body, design: .rounded, weight: .black)).lineLimit(1)
                                Text("\(item.durationText) · \(item.formatText) · \(item.sizeText)").font(.system(.caption2, design: .monospaced)).foregroundStyle(WildColor.secondary(scheme)).lineLimit(1)
                            }
                            Spacer(); RailGlyph(systemName: "arrow.up.right").foregroundStyle(WildColor.orange)
                        }.foregroundStyle(WildColor.ink(scheme)).padding(13).background(WildColor.paper(scheme)).clipShape(WildPanelShape())
                    }.buttonStyle(WildPressStyle()).contextMenu { Button(role: .destructive) { library.delete(item) } label: { RailLabel("删除", systemImage: "trash") } }
                }
            }
        }
    }

    private var filteredVideos: [Recording] { query.isEmpty ? library.recordings : library.recordings.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) } }
    private var filteredAudio: [AudioRecording] { query.isEmpty ? library.audioRecordings : library.audioRecordings.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) } }
}

private struct WildVideoRow: View {
    let recording: Recording
    let index: Int
    @State private var thumbnail: UIImage?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 13) {
            ZStack(alignment: .topLeading) {
                Group { if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill() } else { Color.black.overlay { RailGlyph(systemName: "film").foregroundStyle(.white.opacity(0.55)) } } }
                    .frame(width: 112, height: 72).clipped().clipShape(WildPanelShape(cut: 9))
                Text(String(format: "%02d", index + 1)).font(.system(size: 9, weight: .black, design: .monospaced)).foregroundStyle(WildColor.onAcid).padding(5).background(WildColor.acid)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(recording.title).font(.system(.body, design: .rounded, weight: .black)).lineLimit(1)
                Text("\(recording.durationText) · \(recording.url.pathExtension.uppercased()) · \(recording.sizeText)").font(.system(.caption2, design: .monospaced)).foregroundStyle(WildColor.secondary(scheme)).lineLimit(1)
            }
            Spacer(); RailGlyph(systemName: "arrow.up.right").foregroundStyle(WildColor.violet)
        }.foregroundStyle(WildColor.ink(scheme)).padding(12).background(WildColor.paper(scheme)).clipShape(WildPanelShape())
            .overlay { WildPanelShape().stroke(WildColor.rule(scheme), lineWidth: 1) }.task { thumbnail = await ThumbnailLoader.image(for: recording.url) }
    }
}
