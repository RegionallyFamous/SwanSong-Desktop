import CoreGraphics
import Foundation

public enum PlayerWindowOrientation: String, Codable, Sendable {
    case horizontal
    case vertical
}

public struct PlayerWindowLayout: Sendable {
    public static let screenMargin: CGFloat = 20
    private static let nativeHorizontalSurfaceSize = CGSize(width: 224, height: 157)
    private static let windowChromeAllowance = CGSize(width: 48, height: 96)
    private static let idealNativeScale: CGFloat = 4

    public static func idealSize(
        for orientation: PlayerWindowOrientation
    ) -> CGSize {
        windowSize(
            for: orientation,
            nativeScale: idealNativeScale
        )
    }

    public static func minimumSize(
        for orientation: PlayerWindowOrientation,
        visibleFrame: CGRect
    ) -> CGSize {
        let requested: CGSize
        switch orientation {
        case .horizontal:
            requested = CGSize(width: 620, height: 500)
        case .vertical:
            requested = CGSize(width: 360, height: 540)
        }
        let target = fittedSize(for: orientation, visibleFrame: visibleFrame)
        return CGSize(
            width: min(requested.width, target.width),
            height: min(requested.height, target.height)
        )
    }

    public static func fittedSize(
        for orientation: PlayerWindowOrientation,
        visibleFrame: CGRect
    ) -> CGSize {
        let available = insetVisibleFrame(visibleFrame)
        let nativeSurface = nativeSurfaceSize(for: orientation)
        let availableSurface = CGSize(
            width: max(0, available.width - windowChromeAllowance.width),
            height: max(0, available.height - windowChromeAllowance.height)
        )
        let scale = max(
            0,
            min(
                idealNativeScale,
                min(
                    availableSurface.width / nativeSurface.width,
                    availableSurface.height / nativeSurface.height
                )
            )
        )
        let fitted = windowSize(for: orientation, nativeScale: scale)
        return CGSize(
            width: floor(min(fitted.width, available.width)),
            height: floor(min(fitted.height, available.height))
        )
    }

    public static func targetFrame(
        currentFrame: CGRect,
        visibleFrame: CGRect,
        orientation: PlayerWindowOrientation
    ) -> CGRect {
        let available = insetVisibleFrame(visibleFrame)
        let size = fittedSize(for: orientation, visibleFrame: visibleFrame)
        let proposedOrigin = CGPoint(
            x: currentFrame.midX - size.width / 2,
            y: currentFrame.midY - size.height / 2
        )
        return CGRect(
            origin: clampedOrigin(
                proposedOrigin,
                size: size,
                visibleFrame: available
            ),
            size: size
        )
    }

    public static func restoredFrame(
        libraryFrame: CGRect,
        currentFrame: CGRect,
        visibleFrame: CGRect
    ) -> CGRect {
        let available = insetVisibleFrame(visibleFrame)
        let size = CGSize(
            width: min(libraryFrame.width, available.width),
            height: min(libraryFrame.height, available.height)
        )
        let centeredOrigin = CGPoint(
            x: currentFrame.midX - size.width / 2,
            y: currentFrame.midY - size.height / 2
        )
        return CGRect(
            origin: clampedOrigin(
                centeredOrigin,
                size: size,
                visibleFrame: available
            ),
            size: size
        )
    }

    private static func insetVisibleFrame(_ visibleFrame: CGRect) -> CGRect {
        let horizontalInset = min(screenMargin, visibleFrame.width / 4)
        let verticalInset = min(screenMargin, visibleFrame.height / 4)
        return visibleFrame.insetBy(dx: horizontalInset, dy: verticalInset)
    }

    private static func nativeSurfaceSize(
        for orientation: PlayerWindowOrientation
    ) -> CGSize {
        switch orientation {
        case .horizontal:
            nativeHorizontalSurfaceSize
        case .vertical:
            CGSize(
                width: nativeHorizontalSurfaceSize.height,
                height: nativeHorizontalSurfaceSize.width
            )
        }
    }

    private static func windowSize(
        for orientation: PlayerWindowOrientation,
        nativeScale: CGFloat
    ) -> CGSize {
        let nativeSurface = nativeSurfaceSize(for: orientation)
        return CGSize(
            width: nativeSurface.width * nativeScale + windowChromeAllowance.width,
            height: nativeSurface.height * nativeScale + windowChromeAllowance.height
        )
    }

    private static func clampedOrigin(
        _ origin: CGPoint,
        size: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        CGPoint(
            x: min(
                max(origin.x, visibleFrame.minX),
                visibleFrame.maxX - size.width
            ),
            y: min(
                max(origin.y, visibleFrame.minY),
                visibleFrame.maxY - size.height
            )
        )
    }
}
