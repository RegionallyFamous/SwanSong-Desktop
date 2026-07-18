import AppKit
import SwiftUI

/// Shared visual primitives for SwanSong's native macOS surfaces.
///
/// The app intentionally relies on system colors and controls. These helpers
/// provide a consistent hierarchy without replacing macOS conventions with a
/// custom, game-themed chrome layer.
enum SwanSurfaceLevel {
    case recessed
    case standard
    case elevated
}

private struct SwanSurfaceModifier: ViewModifier {
    let level: SwanSurfaceLevel
    let tint: Color?
    let cornerRadius: CGFloat
    let isEmphasized: Bool

    private var backgroundColor: Color {
        switch level {
        case .recessed:
            Color(nsColor: .windowBackgroundColor)
        case .standard:
            Color(nsColor: .controlBackgroundColor)
        case .elevated:
            Color(nsColor: .textBackgroundColor)
        }
    }

    private var borderColor: Color {
        if isEmphasized, let tint {
            return tint.opacity(0.58)
        }
        return Color(nsColor: .separatorColor).opacity(level == .elevated ? 0.78 : 0.58)
    }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
                if let tint {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint.opacity(level == .recessed ? 0.025 : 0.04))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: isEmphasized ? 1.5 : 1)
            }
            .shadow(
                color: level == .elevated ? Color.black.opacity(0.075) : .clear,
                radius: 14,
                y: 5
            )
    }
}

extension View {
    func swanSurface(
        _ level: SwanSurfaceLevel = .standard,
        tint: Color? = nil,
        cornerRadius: CGFloat = 16,
        emphasized: Bool = false
    ) -> some View {
        modifier(
            SwanSurfaceModifier(
                level: level,
                tint: tint,
                cornerRadius: cornerRadius,
                isEmphasized: emphasized
            )
        )
    }
}

struct SwanIconTile: View {
    let symbol: String
    var tint: Color = SwanTheme.accent
    var size: CGFloat = 58

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.78), SwanTheme.cyan.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .stroke(.white.opacity(0.20), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.43, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: tint.opacity(0.20), radius: size * 0.16, y: size * 0.08)
        .accessibilityHidden(true)
    }
}

struct SwanSidebarBrand: View {
    var body: some View {
        SwanSongWordmark(iconSize: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background {
                LinearGradient(
                    colors: [
                        SwanTheme.accent.opacity(0.075),
                        SwanTheme.violet.opacity(0.025),
                        .clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .overlay(alignment: .bottom) {
                Divider().opacity(0.72)
            }
    }
}

struct SwanEmptyState: View {
    let title: String
    let description: String
    let symbol: String
    var tint: Color = SwanTheme.accent
    var showsBrandMark = false

    var body: some View {
        VStack(spacing: 20) {
            if showsBrandMark {
                SwanSongIcon(size: 82)
            } else {
                SwanIconTile(symbol: symbol, tint: tint, size: 68)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 500)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct SwanEmptyStateContainerModifier: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 44)
            .padding(.vertical, 40)
            .frame(minWidth: 420, maxWidth: 660)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(tint.opacity(0.38), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.075), radius: 14, y: 5)
    }
}

extension View {
    func swanEmptyStateContainer(tint: Color = SwanTheme.accent) -> some View {
        modifier(SwanEmptyStateContainerModifier(tint: tint))
    }
}
