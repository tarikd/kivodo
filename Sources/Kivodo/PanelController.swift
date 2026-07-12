import AppKit
import SwiftUI
import KivodoCore

@MainActor
final class PanelController {
    private let viewModel: CaptureViewModel
    private var panel: FloatingPanel?

    init(viewModel: CaptureViewModel) {
        self.viewModel = viewModel
    }

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        let panel = ensurePanel()
        viewModel.reset()
        position(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    /// Dismissal requested by the view or panel (Escape, click outside, focus
    /// loss). Ignored while a save is in flight so the first-run permission
    /// dialog stealing key status doesn't hide the panel mid-save.
    private func dismissRequested() {
        guard viewModel.phase != .saving else { return }
        close()
    }

    private func ensurePanel() -> FloatingPanel {
        if let panel { return panel }
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 64))
        panel.onDismiss = { [weak self] in self?.dismissRequested() }
        let view = CaptureView(viewModel: viewModel) { [weak self] in self?.dismissRequested() }
        panel.contentView = NSHostingView(rootView: view)
        self.panel = panel
        return panel
    }

    /// Spotlight position: centered, a third of the way down the screen
    /// that currently contains the mouse pointer.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - frame.height / 3 - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}
