import AppKit
import SwiftUI

/// Reports whether the hosting window is actually on screen. MenuBarExtra keeps its
/// window alive when hidden and SwiftUI's onAppear/onDisappear fire unreliably there,
/// so this watches the window's occlusion state instead.
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            }
            report()
        }

        private func report() {
            guard let window else { return }
            onChange?(window.isVisible && window.occlusionState.contains(.visible))
        }
    }
}

