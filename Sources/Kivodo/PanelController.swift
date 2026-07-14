import AppKit
import SwiftUI
import KivodoCore

@MainActor
final class PanelController {
    private let viewModel: CaptureViewModel
    private var panel: FloatingPanel?
    private var hosting: SizingHostingView<CaptureView>?

    init(viewModel: CaptureViewModel) {
        self.viewModel = viewModel
    }

    // Intentionally calls close() directly (bypassing dismissRequested()'s
    // saving-guard) so the hotkey always works as a force-close escape hatch.
    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        let panel = ensurePanel()
        // Re-read the configured pair on every show so Settings edits apply
        // on the next open.
        viewModel.updateDestinations(DestinationConfig.load())
        viewModel.reset()
        sizeToContent(panel)
        position(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    /// Dismissal requested by the view or panel (Escape, click outside).
    /// Ignored while a save is in flight so the first-run permission dialog
    /// stealing key status doesn't hide the panel mid-save.
    private func dismissRequested() {
        guard viewModel.phase != .saving else { return }
        close()
    }

    private func ensurePanel() -> FloatingPanel {
        if let panel { return panel }
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 104))
        panel.onDismiss = { [weak self] in self?.dismissRequested() }
        panel.onTab = { [weak self] in self?.viewModel.toggleDestination() }
        panel.onSpaceChange = { [weak self] in self?.viewModel.requestFocus() }
        let view = CaptureView(viewModel: viewModel) { [weak self] in self?.dismissRequested() }
        let hosting = SizingHostingView(rootView: view)
        // The panel height varies per state (104pt idle/typing/error, 66pt
        // saved/permission). Let the SwiftUI content drive the hosting view's
        // fitting size so sizeToContent() can read it and resize the panel.
        hosting.sizingOptions = [.intrinsicContentSize]
        // The content shrinks (idle→saved) while the panel is visible; keep
        // the panel top-anchored by re-running sizeToContent on every relayout.
        hosting.onLayout = { [weak self] in
            guard let self, let panel = self.panel else { return }
            self.sizeToContent(panel)
        }
        panel.contentView = hosting
        self.hosting = hosting
        self.panel = panel
        return panel
    }

    /// Resize the panel to the SwiftUI content's fitting height, keeping the
    /// top edge fixed so a shrink (idle→saved) doesn't make the panel jump.
    private func sizeToContent(_ panel: FloatingPanel) {
        guard let hosting else { return }
        let height = hosting.fittingSize.height
        guard height > 0, abs(panel.frame.height - height) > 0.5 else { return }
        let top = panel.frame.maxY
        var frame = panel.frame
        frame.size.height = height
        frame.origin.y = top - height
        panel.setFrame(frame, display: true)
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

/// Hosting view that reports each relayout. The panel resizes with its SwiftUI
/// content, but a borderless NSPanel's frame is independent of the hosting
/// view — the controller uses this hook to keep the panel top-anchored as the
/// content grows or collapses between states.
final class SizingHostingView<Content: View>: NSHostingView<Content> {
    var onLayout: (() -> Void)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        onLayout?()
    }
}
