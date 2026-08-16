import AppKit
import SwiftUI

@MainActor
final class OverlayPanelController {
    private let panel: NSPanel

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
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: OverlayView(state: state))
        panel.alphaValue = 0
    }

    func show(on screen: NSScreen?) {
        let screen = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 28
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            Task { @MainActor in panel?.orderOut(nil) }
        })
    }
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
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(.white.opacity(0.88))
                    .frame(width: 18, height: 18)
                    .accessibilityLabel("正在处理")
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
                .fill(Color(red: 0.075, green: 0.082, blue: 0.105).opacity(0.94))
                .background(.ultraThinMaterial, in: Capsule())
        }
        .overlay {
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0.07)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        }
        .shadow(color: .black.opacity(0.34), radius: 16, y: 7)
        .padding(6)
    }

    private var formattedDuration: String {
        let seconds = max(0, Int(state.recordingSeconds.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
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
