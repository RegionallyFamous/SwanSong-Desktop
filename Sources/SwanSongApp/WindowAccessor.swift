import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onWindowChange: @MainActor (NSWindow?) -> Void

    func makeNSView(context: Context) -> AccessView {
        AccessView(onWindowChange: onWindowChange)
    }

    func updateNSView(_ nsView: AccessView, context: Context) {
        nsView.onWindowChange = onWindowChange
        nsView.reportWindowIfNeeded()
    }

    @MainActor
    final class AccessView: NSView {
        var onWindowChange: @MainActor (NSWindow?) -> Void
        private weak var reportedWindow: NSWindow?

        init(onWindowChange: @escaping @MainActor (NSWindow?) -> Void) {
            self.onWindowChange = onWindowChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportWindowIfNeeded()
        }

        func reportWindowIfNeeded() {
            guard reportedWindow !== window else { return }
            reportedWindow = window
            let resolvedWindow = window
            Task { @MainActor in
                onWindowChange(resolvedWindow)
            }
        }
    }
}
