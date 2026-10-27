import CoreGraphics
import Foundation

struct ClipPose: Equatable, Codable {
    var zoom: Double = 1
    var x: Double = 0
    var y: Double = 0
    func interpolated(to end: Self, at t: Double) -> Self {
        .init(zoom: zoom + (end.zoom - zoom) * t, x: x + (end.x - x) * t, y: y + (end.y - y) * t)
    }
}

/// Two editable endpoint keyframes. Linear interpolation keeps split clips continuous.
struct ClipMotion: Equatable, Codable {
    var start = ClipPose()
    var end = ClipPose()
    func pose(at progress: Double) -> ClipPose { start.interpolated(to: end, at: min(1, max(0, progress))) }
    func sliced(from lower: Double, to upper: Double) -> Self { .init(start: pose(at: lower), end: pose(at: upper)) }
}
