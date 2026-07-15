import CoreGraphics
import Foundation

public enum PlayerWindowOrientation: String, Codable, Sendable {
    case horizontal
    case vertical
}

public struct PlayerWindowLayout: Sendable {
    public static let screenMargin: CGFloat = 20

    public static func idealSize(
        for orientation: PlayerWindowOrientation
    ) -> CGSize {
        switch orientation {
        case .horizontal:
            CGSize(width: 1_040, height: 680)
        case .vertical:
            CGSize(width: 700, height: 860)
        }
    }

    public static func minimumSize(
        for orientation: PlayerWindowOrientation,
        visibleFrame: CGRect
    ) -> CGSize {
        let requested: CGSize
        switch orientation {
        case .horizontal:
            requested = CGSize(width: 820, height: 560)
        case .vertical:
            requested = CGSize(width: 620, height: 720)
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
        let ideal = idealSize(for: orientation)
        let scale = min(
            1,
            min(
                available.width / ideal.width,
                available.height / ideal.height
            )
        )
        return CGSize(
            width: floor(ideal.width * scale),
            height: floor(ideal.height * scale)
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
