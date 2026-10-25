import UIKit
import XCTest

@MainActor
final class FocusWidgetAvatarSimulatorTests: XCTestCase {
    func testEveryAvatarProducesABoundedBitmapForWidgetArchiving() throws {
        let names = ["dragon", "puppy", "cat", "hedgehog", "rabbit", "chick", "bird", "penguin_blue", "penguin_pink", "slime"]
        for name in names {
            let image = try XCTUnwrap(FocusWidgetAvatar.image(named: name), "Missing widget avatar: \(name)")
            let bitmap = try XCTUnwrap(image.cgImage, "Widget avatar has no bitmap: \(name)")
            XCTAssertLessThanOrEqual(bitmap.width, FocusWidgetAvatar.maximumPixelDimension, name)
            XCTAssertLessThanOrEqual(bitmap.height, FocusWidgetAvatar.maximumPixelDimension, name)
        }
    }
}
