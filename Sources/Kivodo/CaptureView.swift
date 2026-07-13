import SwiftUI
import KivodoCore

struct CaptureView: View {
    @Bindable var viewModel: CaptureViewModel
    var onDismiss: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if viewModel.phase == .needsPermission {
                permissionRow
            } else {
                inputRow
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 560, height: 64)
        .background(VisualEffectBlur())
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .modifier(Shake(animatableData: CGFloat(viewModel.shakeCount)))
        .animation(.default, value: viewModel.shakeCount)
        .onExitCommand { onDismiss() }
        .onChange(of: viewModel.presentationCount) {
            focused = true
        }
        .onAppear { focused = true }
    }

    private var inputRow: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.phase == .saved
                  ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 20))
                .foregroundStyle(viewModel.phase == .saved ? .green : .secondary)
            TextField("Add a reminder…", text: $viewModel.text)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .regular))
                .focused($focused)
                .onSubmit { submit() }
            if let destination = viewModel.selectedDestination {
                Text(destination.title)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    .contentShape(Capsule())
                    .onTapGesture { viewModel.toggleDestination() }
                    .help("Tab or click to switch list")
            }
            if case .failed(let message) = viewModel.phase {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: 160)
            }
        }
    }

    private var permissionRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.circle")
                .font(.system(size: 20))
                .foregroundStyle(.orange)
            Text("Kivodo needs Reminders access")
                .font(.system(size: 16))
            Spacer()
            Button("Open Settings") {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
                NSWorkspace.shared.open(url)
                onDismiss()
            }
        }
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
