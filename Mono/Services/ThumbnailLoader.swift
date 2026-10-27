import AVFoundation
import UIKit

enum ThumbnailLoader {
    static func image(for url: URL, at seconds: Double = 0) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        do {
            let result = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            return UIImage(cgImage: result.image)
        } catch {
            return nil
        }
    }
}
