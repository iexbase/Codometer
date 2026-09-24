import CoreGraphics

/// A MacBook camera notch in screen coordinates (origin bottom-left, like `NSScreen.frame`).
public struct NotchGeometry: Hashable, Sendable {
    /// Narrower "notches" are measurement noise, not hardware.
    public static let minimumWidth: CGFloat = 60
    /// A notch never takes more than this share of the screen width.
    public static let maximumWidthFraction: CGFloat = 0.4

    public let rect: CGRect
    /// The menu bar height beside the notch (`NSScreen.safeAreaInsets.top`).
    public let menuBarHeight: CGFloat
    public let leftAuxiliaryWidth: CGFloat
    public let rightAuxiliaryWidth: CGFloat

    private init(rect: CGRect, menuBarHeight: CGFloat, leftAuxiliaryWidth: CGFloat, rightAuxiliaryWidth: CGFloat) {
        self.rect = rect
        self.menuBarHeight = menuBarHeight
        self.leftAuxiliaryWidth = leftAuxiliaryWidth
        self.rightAuxiliaryWidth = rightAuxiliaryWidth
    }

    /// The notch between the two auxiliary top areas (`NSScreen.auxiliaryTopLeftArea`/`auxiliaryTopRightArea`).
    ///
    /// `nil` when either area is missing, a value is not finite, `safeTop` is not positive or not smaller than the
    /// screen, the areas overlap (left.maxX > right.minX), or the gap between them is narrower than 60 pt or wider
    /// than 40 % of the screen (external displays and clamshell mode report no areas).
    public static func make(screen: CGRect, safeTop: CGFloat, auxLeft: CGRect?, auxRight: CGRect?) -> NotchGeometry? {
        guard let auxLeft, let auxRight else { return nil }
        let values = [screen.minX, screen.minY, screen.width, screen.height, safeTop,
                      auxLeft.minX, auxLeft.width, auxRight.minX, auxRight.width]
        guard values.allSatisfy(\.isFinite), !screen.isNull, !auxLeft.isNull, !auxRight.isNull else { return nil }
        guard safeTop > 0, safeTop < screen.height, screen.width > 0 else { return nil }
        let left = auxLeft.standardized
        let right = auxRight.standardized
        guard left.maxX <= right.minX else { return nil }
        let width = right.minX - left.maxX
        guard width >= minimumWidth, width <= screen.width * maximumWidthFraction else { return nil }
        guard left.maxX >= screen.minX, right.minX <= screen.maxX else { return nil }
        let rect = CGRect(x: left.maxX, y: screen.maxY - safeTop, width: width, height: safeTop)
        return NotchGeometry(
            rect: rect,
            menuBarHeight: safeTop,
            leftAuxiliaryWidth: left.width,
            rightAuxiliaryWidth: right.width
        )
    }
}
