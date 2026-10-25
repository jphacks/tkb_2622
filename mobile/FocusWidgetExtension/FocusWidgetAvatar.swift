import UIKit

@MainActor
enum FocusWidgetAvatar {
    // The largest character is 54 pt, including on a 3x display.
    static let maximumPixelDimension = 162

    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 10
        cache.totalCostLimit = 2 * 1024 * 1024
        return cache
    }()

    static func image(named name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        let size = CGSize(width: CGFloat(maximumPixelDimension), height: CGFloat(maximumPixelDimension))
        guard let image = UIImage(named: name)?.preparingThumbnail(of: size),
              let bitmap = image.cgImage else { return nil }
        // Give WidgetKit a small, self-contained bitmap rather than the original catalog image.
        cache.setObject(image, forKey: name as NSString, cost: bitmap.bytesPerRow * bitmap.height)
        return image
    }
}
