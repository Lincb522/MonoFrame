import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct SpatialStudioView: View {
    enum Kind: String, CaseIterable { case video = "视频"; case audio = "音频" }
    @State private var kind: Kind = .video
    @State private var importing = false
    @State private var importedVideo: Recording?
    @State private var importedAudio: AudioRecording?
    @EnvironmentObject private var library: RecordingLibrary
    @Namespace private var kindSpace

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                editorSurface(size: proxy.size)
                editorHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                referenceToolShelf
                    .frame(width: proxy.size.width, height: 208)
                    .offset(y: proxy.size.height * 0.69)
                    .zIndex(3)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: kind == .video ? [.movie] : [.audio]) { result in
            Task { await importMedia(result) }
        }
        .navigationDestination(isPresented: Binding(get: { importedVideo != nil }, set: { if !$0 { importedVideo = nil } })) {
            if let importedVideo { EditorView(recording: importedVideo) }
        }
        .navigationDestination(isPresented: Binding(get: { importedAudio != nil }, set: { if !$0 { importedAudio = nil } })) {
            if let importedAudio { AudioEditorView(recording: importedAudio) }
        }
    }

    private func editorSurface(size: CGSize) -> some View {
        let previewHeight = size.height * 0.41
        let timelineHeight = size.height * 0.39
        return VStack(spacing: 0) {
            Button { importing = true } label: {
                Image("SpatialIceBackdrop")
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: previewHeight)
                    .clipped()
            }
            .buttonStyle(.plain)

            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    Text("00:08.6 / 00:24.0")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Spacer()
                    Image(systemName: "play.fill").font(.system(size: 17, weight: .bold))
                    Spacer()
                    Image(systemName: "arrow.uturn.backward")
                    Image(systemName: "arrow.uturn.forward")
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .frame(height: 48)

                timelineRuler
                referenceTimeline
                    .padding(.horizontal, 14)
                    .padding(.bottom, 18)
            }
            .frame(width: size.width, height: timelineHeight, alignment: .top)
            .background(Color.white.opacity(0.76))

            Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var timelineRuler: some View {
        HStack {
            ForEach(["00:04", "00:08", "00:12", "00:16"], id: \.self) { value in
                Text(value).frame(maxWidth: .infinity)
            }
        }
        .font(.system(size: 7, weight: .medium, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(height: 18)
    }

    private var referenceTimeline: some View {
        ZStack {
            VStack(spacing: 7) {
                HStack(spacing: 2) {
                    ForEach(0..<8, id: \.self) { index in
                        Image("SpatialIceBackdrop")
                            .resizable().scaledToFill()
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .clipped()
                            .opacity(index.isMultiple(of: 3) ? 1 : 0.78)
                    }
                }
                timelineTrack("美光滤镜", tint: SpatialColor.ice.opacity(0.26), symbol: "plus")
                timelineTrack("清洁声", tint: SpatialColor.ice.opacity(0.34), symbol: "plus")
                timelineTrack("氛围音", tint: SpatialColor.sea.opacity(0.25), symbol: "plus")
            }
            Rectangle()
                .fill(.white)
                .frame(width: 2)
                .shadow(color: SpatialColor.iceDeep.opacity(0.26), radius: 4)
        }
    }

    private func timelineTrack(_ title: String, tint: Color, symbol: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(SpatialColor.ink.opacity(0.64))
                .padding(.leading, 10)
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
                .spatialGlass(Circle(), interactive: true)
                .padding(.trailing, 4)
        }
        .frame(height: 30)
        .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var referenceToolShelf: some View {
        ZStack(alignment: .top) {
            Ellipse()
                .fill(Color.clear)
                .frame(width: 520, height: 230)
                .spatialGlass(Ellipse())
            HStack(alignment: .top, spacing: 22) {
                editorTool("分割", "rectangle.split.2x1")
                editorTool("变速", "speedometer")
                editorTool("剪辑", "scissors", active: true)
                editorTool("音频", "music.note")
                editorTool("调色", "wand.and.stars")
            }
            .padding(.top, 28)

            Image(systemName: "chevron.down")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .offset(y: 174)
        }
    }

    private var editorHeader: some View {
        HStack(spacing: 10) {
            Button { importing = false } label: { Image(systemName: "xmark").frame(width: 42, height: 42).spatialGlass(Circle(), interactive: true) }
            .buttonStyle(SpatialGlassButtonStyle())
            Spacer()
            Button("1080P") { }
                .font(.caption.bold()).foregroundStyle(.primary)
                .padding(.horizontal, 13).frame(height: 40)
                .spatialGlass(Capsule(), interactive: true)
            Button { importing = false } label: { Image(systemName: "square.and.arrow.up").frame(width: 42, height: 42).spatialGlass(Circle(), interactive: true) }
            .buttonStyle(SpatialGlassButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .zIndex(8)
    }

    private var kindSelector: some View {
        HStack(spacing: 22) {
            ForEach(Kind.allCases, id: \.self) { item in
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 1)) { kind = item }
                } label: {
                    VStack(spacing: 7) {
                        HStack(spacing: 7) {
                            Image(systemName: item == .video ? "film" : "waveform")
                            Text(item.rawValue)
                        }
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(kind == item ? SpatialColor.seaDeep : .secondary)
                        Rectangle()
                            .fill(kind == item ? SpatialColor.sea : .clear)
                            .frame(height: 2)
                            .matchedGeometryEffect(id: kind == item ? "kind-line" : "kind-line-\(item.rawValue)", in: kindSpace)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var creationCanvas: some View {
        Button { importing = true } label: {
            VStack(spacing: 0) {
                Image("SpatialIceBackdrop")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 238)
                    .clipped()

                HStack {
                    Text("00:00.0 / 00:24.0").font(.caption2.monospaced())
                    Spacer()
                    Image(systemName: "play.fill").font(.headline)
                    Spacer()
                    Image(systemName: "arrow.uturn.backward").foregroundStyle(.secondary)
                    Image(systemName: "arrow.uturn.forward").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 15).frame(height: 46)

                ZStack(alignment: .bottomTrailing) {
                    timelineIllustration.padding(14)
                    Rectangle().fill(.white).frame(width: 2).shadow(color: SpatialColor.iceDeep.opacity(0.22), radius: 4)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(.primary)
                        .frame(width: 44, height: 44).spatialGlass(Circle(), interactive: true)
                        .padding(12)
                }
                .frame(height: 180)
            }
            .spatialGlass(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .buttonStyle(SpatialGlassButtonStyle())
        .foregroundStyle(.primary)
    }

    private var toolArc: some View {
        ZStack(alignment: .top) {
            Ellipse()
                .fill(Color.clear)
                .frame(height: 150)
                .spatialGlass(Ellipse())
            HStack(alignment: .top, spacing: 22) {
                editorTool("分割", "rectangle.split.2x1")
                editorTool("变速", "speedometer")
                editorTool("剪辑", "scissors", active: true)
                editorTool("音频", "music.note")
                editorTool("调色", "wand.and.stars")
            }
            .padding(.top, 23)
        }
        .frame(height: 112)
    }

    private func editorTool(_ title: String, _ symbol: String, active: Bool = false) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: active ? 21 : 18, weight: .medium))
                .foregroundStyle(active ? SpatialColor.seaDeep : .primary)
                .frame(width: active ? 56 : 42, height: active ? 56 : 42)
                .spatialGlass(Circle(), tint: active ? SpatialColor.sea.opacity(0.16) : nil, interactive: true)
            Text(title).font(.system(size: 9, weight: .semibold, design: .rounded))
        }
    }

    private var timelineIllustration: some View {
        VStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<(row == 0 ? 8 : 13), id: \.self) { index in
                        RoundedRectangle(cornerRadius: row == 0 ? 5 : 3, style: .continuous)
                            .fill(row == 1 ? SpatialColor.ice.opacity(index.isMultiple(of: 4) ? 0.74 : 0.29) : SpatialColor.sea.opacity(index.isMultiple(of: 5) ? 0.68 : 0.22))
                            .frame(maxWidth: .infinity, minHeight: row == 0 ? 48 : 18)
                    }
                }
            }
        }
        .overlay { Rectangle().fill(.white).frame(width: 2).shadow(color: SpatialColor.iceDeep.opacity(0.25), radius: 3) }
        .accessibilityHidden(true)
    }

    private var recentFlow: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("继续").font(.system(.title3, design: .rounded, weight: .bold))
            if projectCount == 0 {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.to.line.compact")
                    Text("导入素材后，工程会留在这里")
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        if kind == .video {
                            ForEach(library.recordings.prefix(6)) { item in
                                NavigationLink(value: item) { project(item.title, item.durationText, "film") }.buttonStyle(.plain)
                            }
                        } else {
                            ForEach(library.audioRecordings.prefix(6)) { item in
                                NavigationLink(value: item) { project(item.title, item.durationText, "waveform") }.buttonStyle(.plain)
                            }
                        }
                    }
                }.scrollIndicators(.hidden)
            }
        }
    }

    private func project(_ title: String, _ detail: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(SpatialColor.seaDeep)
            Spacer()
            Text(title).font(.subheadline.bold()).lineLimit(1)
            Text(detail).font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
        .padding(16).frame(width: 180, height: 132, alignment: .leading)
        .spatialGlass(RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: true)
        .foregroundStyle(.primary)
    }

    private var projectCount: Int { kind == .video ? library.recordings.count : library.audioRecordings.count }

    @MainActor private func importMedia(_ result: Result<URL, Error>) async {
        do {
            let source = try result.get(); let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
            try SharedStorage.prepare(); let directory = kind == .video ? SharedStorage.localDirectory : SharedStorage.audioDirectory
            let ext = source.pathExtension.isEmpty ? (kind == .video ? "mp4" : "m4a") : source.pathExtension
            let target = directory.appendingPathComponent("Import-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: source, to: target)
            let asset = AVURLAsset(url: target); let duration = try await asset.load(.duration).seconds
            let bytes = ((try? FileManager.default.attributesOfItem(atPath: target.path)[.size]) as? NSNumber)?.int64Value ?? 0
            if kind == .video { importedVideo = Recording(id: UUID(), url: target, createdAt: .now, duration: duration, byteCount: bytes) }
            else { importedAudio = AudioRecording(id: UUID(), url: target, createdAt: .now, duration: duration, byteCount: bytes) }
        } catch { }
    }
}
