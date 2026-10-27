import SwiftUI

struct PearlMotionPanel: View {
    @ObservedObject var editor: VideoEditor
    var seek: (Bool) -> Void
    @State private var editingEnd = false
    private var motion: ClipMotion { editor.selectedClip?.motion ?? ClipMotion() }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("运动关键帧").font(.headline)
                Spacer()
                Button("重置") { editor.updateMotion(nil) }.font(.caption).frame(minHeight: 44)
            }
            Text("在片段的起点与终点设置构图，中间自动插值。平移受画面边界约束，不露黑边。")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                preset("推进", end: .init(zoom: 1.3))
                preset("拉远", start: .init(zoom: 1.3))
                preset("横移", start: .init(zoom: 1.3, x: -1), end: .init(zoom: 1.3, x: 1))
            }
            Picker("编辑关键帧", selection: $editingEnd) {
                Text("◇ 起点").tag(false); Text("◆ 终点").tag(true)
            }.pickerStyle(.segmented).onChange(of: editingEnd) { _, value in seek(value) }
            control("缩放", key: \.zoom, range: 1...3)
            control("水平位置", key: \.x, range: -1...1)
            control("垂直位置", key: \.y, range: -1...1)
            Label(editor.selectedClip?.motion == nil ? "当前片段无运动" : "关键帧已应用到当前片段", systemImage: "diamond.fill")
                .font(.caption2).foregroundStyle(.orange)
        }
    }
    private func preset(_ title: String, start: ClipPose = .init(), end: ClipPose = .init()) -> some View {
        Button(title) { editor.updateMotion(.init(start: start, end: end)) }
            .font(.caption.weight(.medium)).frame(maxWidth: .infinity).frame(height: 44)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
    private func control(_ name: String, key: WritableKeyPath<ClipPose, Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 4) {
            HStack { Text(name); Spacer(); Text(String(format: "%.2f", (editingEnd ? motion.end : motion.start)[keyPath: key])).monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
            Slider(value: Binding(get: { (editingEnd ? motion.end : motion.start)[keyPath: key] }, set: { value in
                var next = motion
                if editingEnd { next.end[keyPath: key] = value } else { next.start[keyPath: key] = value }
                editor.updateMotion(next)
            }), in: range, onEditingChanged: { $0 ? editor.beginContinuousEdit() : editor.endContinuousEdit() })
                .frame(minHeight: 44)
        }
    }
}
