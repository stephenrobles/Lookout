import UIKit

/// Turns a picked photo into a board-sized JPEG small enough to ride along in
/// the CloudKit record. 1920×1080 aspect-fill, cropped from the center.
nonisolated enum WallpaperImporter {
    static let targetSize = CGSize(width: 1920, height: 1080)

    static func prepare(_ data: Data) -> Data? {
        guard let source = UIImage(data: data), source.size.width > 0, source.size.height > 0 else {
            return nil
        }
        let scale = max(targetSize.width / source.size.width, targetSize.height / source.size.height)
        let drawSize = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let origin = CGPoint(x: (targetSize.width - drawSize.width) / 2,
                             y: (targetSize.height - drawSize.height) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let image = renderer.image { _ in
            source.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return image.jpegData(compressionQuality: 0.82)
    }
}
