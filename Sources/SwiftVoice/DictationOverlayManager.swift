import AppKit
import SwiftUI

@MainActor
final class DictationOverlayManager {
    static let shared = DictationOverlayManager()
    static let enabledKey = "showDictationOverlay"

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?

    var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    private init() {}

    func showRecording(recorder: AudioRecorder) {
        guard isEnabled else { return }
        presentView(AnyView(DictationOverlayView(recorder: recorder, state: .recording)))
    }

    func showTranscribing(recorder: AudioRecorder) {
        guard isEnabled else { return }
        presentView(AnyView(DictationOverlayView(recorder: recorder, state: .transcribing)))
    }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0.0
        } completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
            }
        }
    }

    private func presentView(_ view: AnyView) {
        if panel == nil {
            createPanel()
        }

        guard let panel else { return }
        if hostingView == nil {
            let hosting = NSHostingView(rootView: view)
            hosting.autoresizingMask = [.width, .height]
            panel.contentView = hosting
            hostingView = hosting
        } else {
            hostingView?.rootView = view
        }

        updatePanelPosition()
        panel.alphaValue = 0.0
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1.0
        }
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.panel = panel
    }

    private func updatePanelPosition() {
        guard let panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 220
        let panelHeight: CGFloat = 44
        let x = screenFrame.midX - (panelWidth / 2)
        // Position near top of screen (just below menu bar / notch)
        let y = screenFrame.maxY - panelHeight - 16
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }
}
