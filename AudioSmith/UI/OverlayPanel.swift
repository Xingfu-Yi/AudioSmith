import AppKit
import OSLog
import SwiftUI

@MainActor
final class OverlayPanelController {
    private let panel: NSPanel
    private let logger = Logger(subsystem: "com.xingfuyi.AudioSmith", category: "overlay")
    private var presentationGeneration: UInt = 0
    private var visibilityTask: Task<Void, Never>?

    init(state: AppState) {
        panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // NSWindow shadows are calculated from the rectangular window frame,
        // not from the SwiftUI capsule. Keeping this disabled prevents a gray
        // rectangle from appearing around the otherwise transparent overlay.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // The panel never activates the app, but it does accept mouse drags so the
        // user can move it out of the way for the current recording. Its position
        // is intentionally reset the next time recording starts.
        panel.ignoresMouseEvents = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        // `canJoinAllSpaces` alone is not sufficient for another app's full-screen
        // Space. `canJoinAllApplications` is the macOS 13+ behavior intended for
        // system overlays that must accompany whichever application is active.
        panel.collectionBehavior = [
            .canJoinAllApplications,
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .fullScreenDisallowsTiling,
            .transient,
            .ignoresCycle,
        ]
        let hostingView = DraggableHostingView(rootView: OverlayView(state: state))
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        panel.alphaValue = 0
    }

    func show(on screen: NSScreen?, resetPosition: Bool = true) {
        presentationGeneration &+= 1
        let generation = presentationGeneration
        visibilityTask?.cancel()

        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else {
            logger.error("Could not present overlay because no screen is available")
            return
        }
        present(on: screen, generation: generation, resetPosition: resetPosition)

        // Space/full-screen transitions can finish just after the Fn event. Reassert
        // ordering twice so the panel follows the destination Space without stealing
        // focus. Each presentation owns a generation, so stale work cannot resurrect
        // a panel after recording has ended.
        visibilityTask = Task { [weak self, weak screen] in
            for delay in [80, 280] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled, let self, let screen else { return }
                self.present(on: screen, generation: generation, resetPosition: false)
            }
        }
    }

    func hide() {
        presentationGeneration &+= 1
        visibilityTask?.cancel()
        visibilityTask = nil

        // Ordering out synchronously avoids a race where an old fade-out completion
        // hides the panel after a new recording has already started.
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    private func present(on screen: NSScreen, generation: UInt, resetPosition: Bool) {
        guard generation == presentationGeneration else { return }
        let visible = screen.visibleFrame
        if let origin = OverlayPlacement.origin(
            panelFrame: panel.frame,
            visibleFrame: visible,
            resetPosition: resetPosition
        ) {
            panel.setFrameOrigin(origin)
        }
        panel.level = .statusBar
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        logger.debug("Overlay presented on \(screen.localizedName, privacy: .public); visible=\(self.panel.isVisible, privacy: .public)")
    }
}

enum OverlayPlacement {
    /// Returns a new origin when the panel should be repositioned. `nil` means the
    /// current dragged location remains valid and must be preserved.
    static func origin(
        panelFrame: NSRect,
        visibleFrame: NSRect,
        resetPosition: Bool
    ) -> NSPoint? {
        if resetPosition || !panelFrame.intersects(visibleFrame) {
            return NSPoint(
                x: visibleFrame.midX - panelFrame.width / 2,
                y: visibleFrame.minY + 28
            )
        }
        return nil
    }
}

private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct OverlayView: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            WaveformView(levels: state.waveform)
                .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                .opacity(state.phase == .finalizing ? 0.45 : 1)

            if state.phase == .recording {
                Text(formattedDuration)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
            } else if state.phase == .finalizing {
                FinalizingSpinner()
            }

            if state.phase == .recording {
                Text("ESC 取消")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(Color.black.opacity(0.94))
        }
        // Do not add a SwiftUI shadow here. The capsule lives inside a transparent
        // rectangular NSPanel, so a blurred shadow is clipped at that rectangle's
        // edges and reads as a gray box on light backgrounds.
        .padding(6)
    }

    private var formattedDuration: String {
        let seconds = max(0, Int(state.recordingSeconds.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct FinalizingSpinner: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let turn = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 0.82) / 0.82
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 2.2)

                Circle()
                    .trim(from: 0.08, to: 0.76)
                    .stroke(
                        AngularGradient(
                            colors: [
                                .white.opacity(0.98),
                                Color(red: 0.40, green: 0.82, blue: 1),
                                Color(red: 0.58, green: 0.50, blue: 1),
                                .white.opacity(0.18),
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(turn * 360))
            }
        }
        .frame(width: 17, height: 17)
        .accessibilityLabel("正在处理")
    }
}

private struct WaveformView: View {
    let levels: [CGFloat]

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.34, green: 0.78, blue: 0.98),
                                    Color(red: 0.52, green: 0.48, blue: 0.96)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .opacity(0.9)
                        .frame(height: max(3, proxy.size.height * level))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}
