import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics
import OSLog

enum Permissions {
    private static let logger = Logger(
        subsystem: "io.dictateagent.DictateAgent",
        category: "permissions"
    )

    static func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            inputMonitoring: CGPreflightListenEventAccess(),
            accessibility: AXIsProcessTrusted()
        )
    }

    @MainActor
    static func requestAll() async -> PermissionSnapshot {
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.notice("Microphone authorization before request: \(String(describing: microphoneStatus), privacy: .public)")

        if microphoneStatus == .notDetermined {
            // LSUIElement menu-bar apps can otherwise ask while they are hidden in
            // the background. Bring the visible setup window forward first so the
            // TCC prompt has an active owning application.
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(for: .milliseconds(150))
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            logger.notice("Microphone authorization request completed: granted=\(granted, privacy: .public)")
        }

        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }

        if !AXIsProcessTrusted() {
            // String value of kAXTrustedCheckOptionPrompt. Using the literal avoids
            // Swift 6 treating the imported C global as mutable shared state.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        // TCC changes are asynchronous. Avoid publishing the stale value returned
        // in the same run-loop turn as a permission prompt or System Settings edit.
        var latest = snapshot()
        for _ in 0..<4 where !latest.allGranted {
            try? await Task.sleep(for: .milliseconds(250))
            latest = snapshot()
        }
        logger.notice("Permission request finished: microphone=\(latest.microphone, privacy: .public) inputMonitoring=\(latest.inputMonitoring, privacy: .public) accessibility=\(latest.accessibility, privacy: .public)")
        return latest
    }

    @MainActor
    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") else { return }
        NSWorkspace.shared.open(url)
    }
}
