import SwiftUI
import KivodoCore

struct CaptureView: View {
    @Bindable var viewModel: CaptureViewModel
    var onDismiss: () -> Void
    @FocusState private var focused: Bool

    /// The hint footer shows for idle / typing / failed, but not for saved
    /// (which collapses to the input row) or needs-permission (its own layout).
    private var showsFooter: Bool {
        switch viewModel.phase {
        case .idle, .saving, .failed: return true
        case .saved, .needsPermission: return false
        }
    }

    var body: some View {
        Group {
            if viewModel.phase == .needsPermission {
                permissionRow
                    .frame(height: 66)
            } else {
                VStack(spacing: 0) {
                    inputRow
                        .frame(height: 66)
                    if showsFooter {
                        divider
                        hintFooter
                    }
                }
            }
        }
        .frame(width: 560)
        .background(VisualEffectBlur())
        .overlay(borderOverlay)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.default, value: viewModel.phase)
        .modifier(Shake(animatableData: CGFloat(viewModel.shakeCount)))
        .animation(.default, value: viewModel.shakeCount)
        .onExitCommand { onDismiss() }
        .onChange(of: viewModel.presentationCount) {
            focused = true
        }
        .onAppear { focused = true }
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(spacing: 14) {
            statusGlyph
            if viewModel.phase == .saved {
                Text("Added to \(viewModel.selectedDestination?.title ?? "Reminders")")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Add a reminder…", text: $viewModel.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .regular))
                    .focused($focused)
                    .onSubmit { submit() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                if viewModel.selectedDestination != nil {
                    destinationChip
                }
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch viewModel.phase {
        case .saved:
            glyph("checkmark.circle.fill", .green)
        case .failed:
            glyph("exclamationmark.circle.fill", .red)
        case .needsPermission:
            glyph("lock.circle", .orange)
        case .idle, .saving:
            glyph("checkmark.circle", .secondary)
        }
    }

    private func glyph(_ name: String, _ style: some ShapeStyle) -> some View {
        Image(systemName: name)
            .font(.system(size: 24))
            .foregroundStyle(style)
    }

    private var destinationChip: some View {
        HStack(spacing: 6) {
            Text(viewModel.selectedDestination?.title ?? "")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.chipText)
            keycap("⇥", chip: true)
        }
        .padding(.vertical, 5)
        .padding(.leading, 11)
        .padding(.trailing, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.chipFill)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture { viewModel.toggleDestination() }
        .help("Tab or click to switch list")
    }

    // MARK: - Divider + footer

    private var divider: some View {
        Rectangle()
            .fill(dividerTint)
            .frame(height: 0.5)
    }

    private var dividerTint: Color {
        if case .failed = viewModel.phase { return .red.opacity(0.2) }
        return .primary.opacity(0.08)
    }

    private var hintFooter: some View {
        HStack(spacing: 0) {
            footerLeading
            Spacer(minLength: 12)
            footerHints
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .frame(minHeight: 38)
        .transition(.opacity)
    }

    @ViewBuilder
    private var footerLeading: some View {
        if case .failed(let message) = viewModel.phase {
            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.errorFooter)
                .lineLimit(2)
        } else {
            Text("Reminders · \(viewModel.selectedDestination?.title ?? "Reminders")")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var footerHints: some View {
        HStack(spacing: 14) {
            if case .failed = viewModel.phase {
                hint("⏎", "Retry")
            } else {
                hint("⏎", "Save")
                if isTyping {
                    if viewModel.selectedDestination != nil {
                        hint("⇥", "List")
                    }
                } else {
                    hint("esc", "Cancel")
                }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }

    /// "Typing" is idle-with-text; the footer swaps esc→Cancel for ⇥→List once
    /// the field is non-empty (matching the mockup's idle vs typing states).
    private var isTyping: Bool {
        viewModel.phase == .idle
            && !viewModel.text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            keycap(key, chip: false)
            Text(label)
        }
    }

    private func keycap(_ symbol: String, chip: Bool) -> some View {
        Text(symbol)
            .font(.system(size: 11))
            .foregroundStyle(chip ? Color.chipGlyph : .secondary)
            .frame(minWidth: chip ? 18 : 20, minHeight: chip ? 18 : 20)
            .padding(.horizontal, chip ? 0 : 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(chip ? Color.chipGlyphFill : Color.keycapFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(chip ? .clear : Color.keycapBorder, lineWidth: 0.5)
            )
    }

    // MARK: - Permission

    private var permissionRow: some View {
        HStack(spacing: 14) {
            glyph("lock.circle", .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Kivodo needs access")
                    .font(.system(size: 17))
                Text("to add reminders to your lists")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: openPrivacySettings) {
                Text("Open Settings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    private func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
        NSWorkspace.shared.open(url)
        onDismiss()
    }

    // MARK: - Border

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.panelBorder, lineWidth: 0.5)
    }

    private func submit() {
        Task {
            // If the panel is re-presented while the save or the confirmation
            // delay is in flight, this stale task must not dismiss the fresh
            // presentation.
            let presentation = viewModel.presentationCount
            await viewModel.submit()
            if viewModel.phase == .saved, viewModel.presentationCount == presentation {
                try? await Task.sleep(for: .milliseconds(350))
                if viewModel.presentationCount == presentation { onDismiss() }
            }
        }
    }
}

// MARK: - Adaptive tokens

/// Colors that flip on appearance. Semantic SwiftUI colors cover most of the
/// palette; these few are the hairline/keycap fills the spec pins per mode.
private extension Color {
    static let panelBorder = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 0, alpha: 0.08)
    })
    static let keycapFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.05)
    })
    static let keycapBorder = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.1) : NSColor(white: 0, alpha: 0.08)
    })
    /// Softened red for the error footer message (spec #FF8B83 in dark).
    static let errorFooter = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(red: 1, green: 0.545, blue: 0.514, alpha: 1)
            : NSColor(red: 0.85, green: 0.18, blue: 0.13, alpha: 1)
    })

    // Destination chip. A near-solid accent fill (rather than the old faint
    // tint) so it reads as a filled pill, with white text/glyph for contrast.
    static let chipFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(red: 0.369, green: 0.663, blue: 1, alpha: 0.95)   // #5EA9FF
            : NSColor(red: 0.039, green: 0.518, blue: 1, alpha: 0.95)   // #0A84FF
    })
    static let chipText = Color.white
    /// The trailing ⇥ glyph, also white, sitting in its own translucent chip.
    static let chipGlyph = Color.white
    static let chipGlyphFill = Color(nsColor: NSColor(name: nil) { _ in
        NSColor(white: 1, alpha: 0.22)
    })
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

/// Frosted-glass background matching Spotlight/ChatGPT.
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Login-window-style horizontal shake, driven by incrementing shakeCount.
struct Shake: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: amount * sin(animatableData * .pi * shakesPerUnit),
            y: 0
        ))
    }
}
