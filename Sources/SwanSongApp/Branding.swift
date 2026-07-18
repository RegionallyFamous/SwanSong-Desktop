import AppKit
import SwiftUI

enum SwanTheme {
    // These colors are sampled from the app icon so the chrome, player, and
    // Translation Lab feel like one product without tinting the whole app.
    static let accent = Color(red: 0.31, green: 0.48, blue: 0.98)
    static let cyan = Color(red: 0.20, green: 0.82, blue: 0.98)
    static let violet = Color(red: 0.57, green: 0.31, blue: 0.98)
    static let translationAccent = violet
    static let midnight = Color(red: 0.025, green: 0.045, blue: 0.12)

    static var applicationIcon: NSImage? {
        if let bundledURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: bundledURL) {
            return image
        }
        return nil
    }

    static var compactApplicationIcon: NSImage? {
        if let bundledURL = Bundle.main.url(
            forResource: "AppIconCompact",
            withExtension: "png"
        ), let image = NSImage(contentsOf: bundledURL) {
            return image
        }
        return nil
    }

    /// Monochrome template artwork for SwanSong's menu-bar status item.
    /// AppKit applies the appropriate light/dark appearance to template images.
    static var menuBarIcon: NSImage? {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Packaging/MenuBarSwan.png")
        let candidateURLs = [
            Bundle.main.url(forResource: "MenuBarSwan", withExtension: "png"),
            sourceURL,
        ].compactMap { $0 }

        for url in candidateURLs {
            if let image = NSImage(contentsOf: url) {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                image.accessibilityDescription = "SwanSong"
                return image
            }
        }
        return nil
    }

    /// SwiftPM launches the executable outside an application bundle, so
    /// AppKit would otherwise use its generic rocket icon. Production app
    /// bundles continue to use the opaque ICNS declared by Info.plist.
    @MainActor
    static var unbundledApplicationIcon: NSImage? {
        // A direct `swift run` still has the checkout beside its build output.
        // Prefer the real compact artwork both for fidelity and so Intel CI
        // does not need SwiftUI's GPU-backed ImageRenderer just to verify it.
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Packaging/AppIconCompact.png")
        if let image = NSImage(contentsOf: sourceURL) {
            image.size = NSSize(width: 512, height: 512)
            return image
        }

        let renderer = ImageRenderer(
            content: SwanSongFallbackMark()
                .frame(width: 512, height: 512)
        )
        renderer.proposedSize = ProposedViewSize(width: 512, height: 512)
        renderer.scale = 2
        return renderer.nsImage
    }

    static var libraryBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                accent.opacity(0.060),
                cyan.opacity(0.028),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var playerBackground: LinearGradient {
        LinearGradient(
            colors: [
                midnight,
                Color(red: 0.035, green: 0.045, blue: 0.085),
                Color(red: 0.020, green: 0.055, blue: 0.085),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var iconGlow: RadialGradient {
        RadialGradient(
            colors: [cyan.opacity(0.22), violet.opacity(0.10), .clear],
            center: .center,
            startRadius: 0,
            endRadius: 120
        )
    }
}

struct SwanSongIcon: View {
    var size: CGFloat
    var showsShadow = true

    var body: some View {
        let preferredIcon = size <= 64
            ? (SwanTheme.compactApplicationIcon ?? SwanTheme.applicationIcon)
            : SwanTheme.applicationIcon

        Group {
            if let image = preferredIcon {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            } else {
                SwanSongFallbackMark()
            }
        }
        .frame(width: size, height: size)
        .shadow(
            color: showsShadow ? SwanTheme.violet.opacity(0.22) : .clear,
            radius: size * 0.18,
            y: size * 0.08
        )
        .accessibilityHidden(true)
    }
}

struct SwanSongWordmark: View {
    var iconSize: CGFloat = 34
    var includesSubtitle = true

    var body: some View {
        HStack(spacing: 10) {
            SwanSongIcon(size: iconSize, showsShadow: false)
            VStack(alignment: .leading, spacing: 0) {
                Text("SwanSong")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                if includesSubtitle {
                    Text("FOR WONDERSWAN")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .tracking(1.35)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SwanSong, for WonderSwan")
    }
}

struct SwanSongFallbackMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.23, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.08, green: 0.10, blue: 0.22),
                                Color(red: 0.24, green: 0.14, blue: 0.46),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                SwanGlyph()
                    .stroke(
                        LinearGradient(
                            colors: [.white, SwanTheme.cyan.opacity(0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(
                            lineWidth: side * 0.105,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .padding(side * 0.19)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct SwanGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX * 0.83, y: rect.minY + rect.height * 0.16))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.31, y: rect.minY + rect.height * 0.47),
            control1: CGPoint(x: rect.maxX * 0.57, y: rect.minY - rect.height * 0.01),
            control2: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.minY + rect.height * 0.16)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX * 0.79, y: rect.minY + rect.height * 0.80),
            control1: CGPoint(x: rect.minX + rect.width * 0.43, y: rect.minY + rect.height * 0.69),
            control2: CGPoint(x: rect.maxX * 0.89, y: rect.minY + rect.height * 0.55)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.76),
            control1: CGPoint(x: rect.maxX * 0.59, y: rect.maxY),
            control2: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY * 0.96)
        )
        return path
    }
}
