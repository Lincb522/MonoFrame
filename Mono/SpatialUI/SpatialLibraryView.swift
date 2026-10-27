import SwiftUI
import UIKit

struct SpatialLibraryView: View {
    enum Filter: String, CaseIterable { case video = "视频"; case audio = "音频"; case projects = "工程" }
    @State private var filter: Filter = .video
    @EnvironmentObject private var library: RecordingLibrary

    var body: some View {
        VStack(spacing: 16) {
            libraryHeader
            filterBar
            ScrollView {
                Group {
                    switch filter {
                    case .video: videoWall
                    case .audio: audioFlow
                    case .projects: projectFlow
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .refreshable { await library.reload() }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private var libraryHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("媒体库")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-1.35)
                Text("所有媒体都在本机")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { } label: {
                Image(systemName: "magnifyingglass")
                    .frame(width: 42, height: 42)
                    .spatialGlass(Circle(), interactive: true)
            }
            Button { Task { await library.reload() } } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 42, height: 42)
                    .spatialGlass(Circle(), interactive: true)
            }
        }
        .buttonStyle(SpatialGlassButtonStyle())
    }

    private var filterBar: some View {
        HStack(spacing: 24) {
            ForEach(Filter.allCases, id: \.self) { item in
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 1)) { filter = item }
                } label: {
                    VStack(spacing: 6) {
                        Text(item.rawValue).font(.system(.subheadline, design: .rounded, weight: filter == item ? .bold : .medium))
                        Capsule().fill(filter == item ? SpatialColor.sea : .clear).frame(width: 22, height: 2)
                    }
                    .foregroundStyle(filter == item ? .primary : .secondary)
                }.buttonStyle(.plain)
            }
            Spacer()
        }
    }

    @ViewBuilder private var videoWall: some View {
        if library.recordings.isEmpty { placeholderWall }
        else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                ForEach(Array(library.recordings.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: item) {
                        SpatialVideoPiece(recording: item, tall: index.isMultiple(of: 3))
                            .offset(y: index % 2 == 1 ? 28 : 0)
                    }.buttonStyle(SpatialGlassButtonStyle())
                }
            }
            .padding(.bottom, 34)
        }
    }

    private var placeholderWall: some View {
        ZStack {
            samplePiece(width: 174, height: 236, x: 76, y: -82, rotation: 4, label: "00:24")
            samplePiece(width: 144, height: 190, x: -82, y: -28, rotation: -5, label: "00:18")
            samplePiece(width: 166, height: 218, x: 72, y: 112, rotation: 5, label: "00:15")
            samplePiece(width: 130, height: 164, x: -72, y: 154, rotation: -3, label: "00:09")
        }
        .frame(maxWidth: .infinity, minHeight: 500)
        .overlay(alignment: .bottomLeading) {
            EmptyView()
        }
    }

    private func samplePiece(width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat, rotation: Double, label: String) -> some View {
        Image("SpatialIceBackdrop")
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Text(label).font(.caption2.monospaced()).foregroundStyle(.white)
                    .padding(.horizontal, 8).frame(height: 27)
                    .background(.black.opacity(0.34), in: Capsule()).padding(9)
            }
            .rotationEffect(.degrees(rotation))
            .offset(x: x, y: y)
            .shadow(color: SpatialColor.iceDeep.opacity(0.10), radius: 18, y: 10)
    }

    @ViewBuilder private var audioFlow: some View {
        if library.audioRecordings.isEmpty { empty("还没有录音", "录音和混音结果会出现在这里") }
        else {
            LazyVStack(spacing: 2) {
                ForEach(library.audioRecordings) { item in
                    NavigationLink(value: item) {
                        HStack(spacing: 14) {
                            SpatialWave(active: false, phase: 0, tint: SpatialColor.sea, count: 9).frame(width: 82, height: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.system(.body, design: .rounded, weight: .bold))
                                Text("\(item.durationText)  ·  \(item.formatText)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 15)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.primary)
                    Divider().opacity(0.18)
                }
            }
        }
    }

    @ViewBuilder private var projectFlow: some View {
        let count = library.recordings.count + library.audioRecordings.count
        if count == 0 { empty("还没有工程", "从创作页导入一段素材") }
        else {
            VStack(alignment: .leading, spacing: 16) {
                Text("最近处理").font(.title3.bold())
                HStack(alignment: .bottom, spacing: 10) {
                    projectMetric("视频", value: "\(library.recordings.count)", height: 154, tint: SpatialColor.ice)
                    projectMetric("音频", value: "\(library.audioRecordings.count)", height: 118, tint: SpatialColor.sea)
                }
            }.padding(.top, 8)
        }
    }

    private func projectMetric(_ title: String, value: String, height: CGFloat, tint: Color) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(.system(size: 38, weight: .light, design: .rounded)); Spacer(); Text(title).font(.caption.bold())
        }
        .padding(18).frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
        .background(tint.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private func empty(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(SpatialColor.ice.opacity(0.26), lineWidth: 1).frame(width: 110, height: 82).rotationEffect(.degrees(-7))
                RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(SpatialColor.sea.opacity(0.28), lineWidth: 1).frame(width: 110, height: 82).rotationEffect(.degrees(7))
            }.frame(height: 116)
            Text(title).font(.title3.bold()); Text(detail).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 390)
    }
}

private struct SpatialVideoPiece: View {
    let recording: Recording
    let tall: Bool
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill() }
                else { LinearGradient(colors: [SpatialColor.ice.opacity(0.28), SpatialColor.sea.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing).overlay(Image(systemName: "play.fill").foregroundStyle(SpatialColor.seaDeep)) }
            }
            .frame(maxWidth: .infinity).frame(height: tall ? 232 : 174).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Text(recording.durationText).font(.caption2.monospaced()).foregroundStyle(.white).padding(.horizontal, 8).frame(height: 28).background(.black.opacity(0.40), in: Capsule()).padding(9)
            }
            Text(recording.title).font(.system(.caption, design: .rounded, weight: .bold)).lineLimit(1)
        }
        .foregroundStyle(.primary)
        .task { thumbnail = await ThumbnailLoader.image(for: recording.url) }
    }
}
