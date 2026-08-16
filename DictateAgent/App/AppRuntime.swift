import AppKit
import Foundation
import OSLog

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    private let state = AppState.shared
    private let logger = Logger(subsystem: "io.dictateagent.DictateAgent", category: "runtime")
    private let skills = SkillManager.shared
    private let hotkeySettings = HotkeySettings.shared
    private let memory = MemoryMonitor()
    private let modelManager = ModelManager()
    private let engine = QwenStreamingEngine()
    private let audio = AudioCapture()
    private let inserter = TextInserter()
    private lazy var overlay = OverlayPanelController(state: state)
    private var hotkey: PushToTalkKeyMonitor?
    private var targetApplication: TargetApplication?
    private var recordingSkill: DomainSkill = .general
    private var maxDurationTask: Task<Void, Never>?
    private var refinementTask: Task<Void, Never>?
    private var memoryTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    func start() {
        guard startupTask == nil else { return }
        startupTask = Task { [weak self] in
            guard let self else { return }
            await self.bootstrap()
        }
        observeSystemEvents()
        startMemoryMonitor()
    }

    func shutdown() {
        startupTask?.cancel()
        maxDurationTask?.cancel()
        refinementTask?.cancel()
        memoryTask?.cancel()
        hotkey?.stop()
        _ = audio.stop()
        engine.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    func requestPermissions() async {
        state.permissions = await Permissions.requestAll()
        logger.notice("Permission snapshot: microphone=\(self.state.permissions.microphone, privacy: .public) inputMonitoring=\(self.state.permissions.inputMonitoring, privacy: .public) accessibility=\(self.state.permissions.accessibility, privacy: .public)")
        configureHotkey()
    }

    func selectHotkey(_ selection: DictationHotkey) {
        hotkeySettings.select(selection)
        configureHotkey()
        state.lastMessage = "听写快捷键已设为 \(selection.displayName)。"
    }

    private func refreshPermissions() {
        let latest = Permissions.snapshot()
        guard latest != state.permissions else { return }
        state.permissions = latest
        logger.notice("Permission state refreshed: microphone=\(latest.microphone, privacy: .public) inputMonitoring=\(latest.inputMonitoring, privacy: .public) accessibility=\(latest.accessibility, privacy: .public)")
        configureHotkey()
    }

    func reinstallModel() {
        guard state.phase != .recording, state.phase != .finalizing else { return }
        do {
            try modelManager.removeInstalledModel()
            state.lastMessage = "旧模型已移入隔离目录，准备重新下载。"
            startupTask?.cancel()
            startupTask = Task { [weak self] in await self?.loadModel() }
        } catch {
            state.phase = .error(error.localizedDescription)
        }
    }

    private func bootstrap() async {
        state.phase = .checking
        guard memory.isSupported else {
            state.phase = .unsupported("需要至少 24GB 统一内存；此 Mac 为 \(memory.formattedPhysicalMemory)。")
            return
        }
        await requestPermissions()
        await loadModel()
    }

    private func loadModel() async {
        do {
            state.phase = .downloading
            let directory = try await modelManager.prepare { [weak state] progress in
                state?.downloadedBytes = progress.completedBytes
                state?.totalDownloadBytes = progress.totalBytes
                state?.downloadProgress = progress.totalBytes > 0
                    ? Double(progress.completedBytes) / Double(progress.totalBytes)
                    : 0
            }
            try Task.checkCancellation()
            state.phase = .loading
            try await engine.load(from: directory)
            await engine.prewarm()
            try Task.checkCancellation()
            state.phase = .ready
            logger.notice("Model is ready")
            state.lastMessage = state.permissions.allGranted
                ? nil
                : "请补齐系统权限后按住 (hotkeySettings.selected.displayName) 听写。"
        } catch is CancellationError {
            return
        } catch {
            state.phase = .error(error.localizedDescription)
        }
    }

    private func configureHotkey() {
        hotkey?.stop()
        hotkey = nil
        guard state.permissions.inputMonitoring else {
            logger.error("Hotkey monitor not configured because Input Monitoring is unavailable")
            return
        }
        let selection = hotkeySettings.selected
        let monitor = PushToTalkKeyMonitor(hotkey: selection, handlers: .init(
            pressed: { [weak self] in self?.beginRecording() },
            released: { [weak self] in self?.finishRecording() },
            cancelled: { [weak self] in self?.cancelRecording(message: "已取消") }
        ))
        do {
            try monitor.start()
            hotkey = monitor
            logger.notice("Hotkey monitor configured for \(selection.displayName, privacy: .public)")
        } catch {
            logger.error("Hotkey monitor failed: \(error.localizedDescription, privacy: .public)")
            state.lastMessage = error.localizedDescription
        }
    }

    private func beginRecording() {
        logger.notice("Push-to-talk press received")
        guard state.phase == .ready else {
            logger.notice("Push-to-talk press ignored because the model is not ready")
            return
        }
        guard state.permissions.microphone else {
            state.lastMessage = "请先允许麦克风权限。"
            return
        }

        // Skills are inexpensive Markdown files. Reload before every dictation so
        // edits take effect on the next push-to-talk press without restarting the app.
        skills.reload()
        recordingSkill = skills.selectionSnapshot
        state.resetTranscript()
        targetApplication = inserter.captureTarget()
        state.phase = .recording
        overlay.show(on: ScreenLocator.screenForFocusedWindow(pid: targetApplication?.pid))
        engine.begin(skill: recordingSkill)

        do {
            let audioSink = engine.makeAudioSink()
            try audio.start { [weak self] samples, level in
                audioSink(samples)
                Task { @MainActor in
                    guard let self, self.state.phase == .recording else { return }
                    self.state.appendWaveform(CGFloat(level))
                    self.state.recordingSeconds += Double(samples.count) / 16_000.0
                }
            }
        } catch {
            engine.cancel()
            overlay.hide()
            state.phase = .ready
            state.lastMessage = error.localizedDescription
            return
        }

        maxDurationTask?.cancel()
        maxDurationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled else { return }
            self?.finishRecording()
        }
    }

    private func finishRecording() {
        guard state.phase == .recording else { return }
        maxDurationTask?.cancel()
        let capture = audio.stop()
        logger.notice("Recording stopped after \(capture.duration, format: .fixed(precision: 2)) seconds; speech=\(capture.containedSpeech)")
        guard capture.containedSpeech, capture.duration >= 0.08 else {
            cancelRecording(message: nil)
            return
        }
        state.phase = .finalizing
        logger.notice("Finalizing the rolling tail")
        refinementTask?.cancel()
        let skill = recordingSkill
        refinementTask = Task { [weak self] in
            guard let self else { return }
            var result = await self.engine.finish()
            guard !Task.isCancelled else { return }

            if result == nil {
                self.logger.error("Rolling-window stitching was unavailable or low-confidence; retrying one safe full-context pass")
                result = await self.engine.transcribe(samples: capture.samples, skill: skill)
            }
            guard !Task.isCancelled else { return }

            if let result {
                self.state.performance = .init(
                    realTimeFactor: result.realTimeFactor,
                    tokensPerSecond: result.tokensPerSecond,
                    peakMemoryGB: result.peakMemoryGB,
                    audioSeconds: result.audioSeconds
                )
                self.logger.notice("Rolling decode finished: audio=\(result.audioSeconds, format: .fixed(precision: 2))s totalDecode=\(result.decodeSeconds, format: .fixed(precision: 2))s finalDecode=\(result.finalDecodeSeconds, format: .fixed(precision: 2))s encoderWindows=\(result.encodedWindowCount) checkpoints=\(result.checkpointCount) peak=\(result.peakMemoryGB, format: .fixed(precision: 2))GB")
                if result.peakMemoryGB >= 5.0 {
                    self.state.memoryWarning = String(format: "峰值 %.2fGB，已超过 5GB 发布阻断线。", result.peakMemoryGB)
                } else if result.peakMemoryGB >= 4.7 {
                    self.state.memoryWarning = String(format: "峰值 %.2fGB，已超过 4.7GB 诊断线。", result.peakMemoryGB)
                }
            }
            await self.complete(result?.text ?? "")
        }
    }

    private func cancelRecording(message: String?) {
        guard state.phase == .recording || state.phase == .finalizing else { return }
        maxDurationTask?.cancel()
        refinementTask?.cancel()
        _ = audio.stop()
        engine.cancel()
        overlay.hide()
        targetApplication = nil
        recordingSkill = .general
        state.resetTranscript()
        state.phase = .ready
        state.lastMessage = message
    }

    private func complete(_ rawText: String) async {
        guard state.phase == .finalizing else { return }
        refinementTask = nil
        let text = TextCleaner.clean(rawText, replacements: recordingSkill.deterministicReplacements)
        if text.isEmpty {
            state.lastMessage = "未识别到语音。"
        } else {
            let result = await inserter.insert(text, into: targetApplication)
            switch result {
            case .pasted: state.lastMessage = "已粘贴并保留在剪贴板。"
            case .clipboardOnly(let reason): state.lastMessage = reason
            }
        }
        targetApplication = nil
        recordingSkill = .general
        try? await Task.sleep(for: .milliseconds(180))
        overlay.hide()
        state.phase = .ready
    }

    private func startMemoryMonitor() {
        memoryTask?.cancel()
        memoryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.refreshPermissions()
                let footprint = self.memory.currentFootprintBytes()
                if footprint >= MemoryMonitor.warningBytes {
                    let value = Double(footprint) / 1_000_000_000
                    self.state.memoryWarning = String(format: "应用 footprint %.2fGB；4.7GB 为诊断线，5GB 为发布阻断线。", value)
                }
            }
        }
    }

    private func observeSystemEvents() {
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.state.permissions = Permissions.snapshot()
                self?.configureHotkey()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in self?.refreshPermissions() }
        })
    }
}
