import AppKit
import Foundation
import OSLog

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    private struct RequestSnapshot: Sendable {
        let id: UUID
        let refinementMode: RefinementMode
        let skill: DomainSkill
    }

    private let state = AppState.shared
    private let logger = Logger(subsystem: "com.xingfuyi.AudioSmith", category: "runtime")
    private let skills = SkillManager.shared
    private let hotkeySettings = HotkeySettings.shared
    private let preferences = DictationPreferences.shared
    private let memory = MemoryMonitor()
    private let asrModelManager = ModelManager(manifest: .qwen3ASR06B8Bit)
    private let refinerModelManager = ModelManager(manifest: .qwen3Refiner17B4Bit)
    private let engine = QwenStreamingEngine()
    private let refiner = ProfessionalRefiner()
    private let audio = AudioCapture()
    private let inserter = TextInserter()
    private lazy var overlay = OverlayPanelController(state: state)

    private var hotkey: PushToTalkKeyMonitor?
    private var targetApplication: TargetApplication?
    private var activeRequest: RequestSnapshot?
    private var pendingASRText: String?
    private var skipProfessionalRefinement = false
    private var refinerIsLoaded = false
    private var maxDurationTask: Task<Void, Never>?
    private var refinementTask: Task<Void, Never>?
    private var memoryTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?
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
        settingsTask?.cancel()
        maxDurationTask?.cancel()
        refinementTask?.cancel()
        memoryTask?.cancel()
        hotkey?.stop()
        _ = audio.stop()
        engine.unload()
        Task { await refiner.unload() }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    func requestPermissions() async {
        state.permissions = await Permissions.requestAll()
        logger.notice("Permission snapshot: microphone=\(self.state.permissions.microphone, privacy: .public) shortcutMonitoring=\(self.state.permissions.shortcutMonitoring, privacy: .public) accessibility=\(self.state.permissions.accessibility, privacy: .public)")
        configureHotkey()
    }

    func selectHotkey(_ selection: DictationHotkey) {
        hotkeySettings.select(selection)
        configureHotkey()
        state.lastMessage = "听写快捷键已设为 \(selection.displayName)。"
    }

    func selectRefinementMode(_ mode: RefinementMode) {
        preferences.selectRefinementMode(mode)
        if state.phase == .recording || state.phase == .finalizing {
            state.lastMessage = "模式将在下一次听写时生效。"
            return
        }
        settingsTask?.cancel()
        settingsTask = Task { [weak self] in
            await self?.reconcileRefinerWithPreferences()
        }
    }

    func selectModelSource(_ source: ModelSourcePreference) {
        preferences.selectModelSource(source)
        state.lastMessage = "下载源已设为 \(source.displayName)，下次缺少模型文件时生效。"
    }

    func reinstallModels() {
        guard state.phase != .recording, state.phase != .finalizing else { return }
        do {
            try asrModelManager.removeInstalledModel()
            try refinerModelManager.removeInstalledModel()
            engine.unload()
            Task { await refiner.unload() }
            refinerIsLoaded = false
            state.lastMessage = "旧模型已移入隔离目录，准备重新下载。"
            startupTask?.cancel()
            startupTask = Task { [weak self] in await self?.loadRequiredModels() }
        } catch {
            state.phase = .error(error.localizedDescription)
        }
    }

    private func refreshPermissions() {
        let latest = Permissions.snapshot()
        guard latest != state.permissions else { return }
        state.permissions = latest
        logger.notice("Permission state refreshed: microphone=\(latest.microphone, privacy: .public) shortcutMonitoring=\(latest.shortcutMonitoring, privacy: .public) accessibility=\(latest.accessibility, privacy: .public)")
        configureHotkey()
    }

    private func bootstrap() async {
        state.phase = .checking
        guard memory.isSupported else {
            state.phase = .unsupported("需要至少 24GB 统一内存；此 Mac 为 \(memory.formattedPhysicalMemory)。")
            return
        }
        await requestPermissions()
        await loadRequiredModels()
    }

    private func loadRequiredModels() async {
        do {
            if !engine.isLoaded {
                let directory = try await prepareModel(
                    asrModelManager,
                    name: "Qwen3-ASR-0.6B 8-bit"
                )
                try Task.checkCancellation()
                state.phase = .loading
                state.downloadingModelName = "Qwen3-ASR-0.6B 8-bit"
                try await engine.load(from: directory)
                await engine.prewarm()
            }

            if preferences.refinementMode == .professional {
                try await loadProfessionalRefiner()
            } else if refinerIsLoaded {
                await refiner.unload()
                refinerIsLoaded = false
            }

            try Task.checkCancellation()
            state.downloadingModelName = nil
            state.activeDownloadSource = nil
            state.phase = .ready
            logger.notice("Required models are ready; professional=\(self.preferences.refinementMode == .professional, privacy: .public)")
            state.lastMessage = state.permissions.allGranted
                ? nil
                : "请补齐系统权限后按住 \(hotkeySettings.selected.displayName) 听写。"
        } catch is CancellationError {
            return
        } catch {
            state.phase = .error(error.localizedDescription)
        }
    }

    private func prepareModel(_ manager: ModelManager, name: String) async throws -> URL {
        state.phase = .downloading
        state.downloadingModelName = name
        state.downloadedBytes = 0
        state.totalDownloadBytes = 0
        state.downloadProgress = 0
        return try await manager.prepare(
            source: preferences.modelSource,
            progress: { [weak state] progress in
                state?.downloadedBytes = progress.completedBytes
                state?.totalDownloadBytes = progress.totalBytes
                state?.downloadProgress = progress.totalBytes > 0
                    ? Double(progress.completedBytes) / Double(progress.totalBytes)
                    : 0
            },
            activeSource: { [weak state] source in
                state?.activeDownloadSource = source
            }
        )
    }

    private func loadProfessionalRefiner() async throws {
        guard !refinerIsLoaded else { return }
        let directory = try await prepareModel(
            refinerModelManager,
            name: "Qwen3-1.7B MLX 4-bit 精修"
        )
        try Task.checkCancellation()
        state.phase = .loading
        state.downloadingModelName = "Qwen3-1.7B MLX 4-bit 精修"
        try await refiner.load(from: directory)
        await refiner.prewarm()
        refinerIsLoaded = true
    }

    private func reconcileRefinerWithPreferences() async {
        switch preferences.refinementMode {
        case .fast:
            if refinerIsLoaded {
                await refiner.unload()
                refinerIsLoaded = false
            }
            if engine.isLoaded { state.phase = .ready }
            state.lastMessage = "已切换到极速听写；1.7B 精修模型已从内存卸载。"
        case .professional:
            if refinerIsLoaded {
                if engine.isLoaded { state.phase = .ready }
                return
            }
            do {
                try await loadProfessionalRefiner()
                state.downloadingModelName = nil
                state.activeDownloadSource = nil
                state.phase = .ready
                state.lastMessage = "专业精修已就绪。"
            } catch is CancellationError {
                return
            } catch {
                state.phase = .error(error.localizedDescription)
            }
        }
    }

    private func configureHotkey() {
        hotkey?.stop()
        hotkey = nil
        guard state.permissions.shortcutMonitoring else {
            logger.error("Hotkey monitor not configured because keyboard event access is unavailable")
            return
        }
        let selection = hotkeySettings.selected
        let monitor = PushToTalkKeyMonitor(hotkey: selection, handlers: .init(
            pressed: { [weak self] in self?.beginRecording() },
            released: { [weak self] in self?.finishRecording() },
            cancelled: { [weak self] in self?.cancelRecording(message: "已取消") },
            escapePressed: { [weak self] in self?.handleStandaloneEscape() }
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
            logger.notice("Push-to-talk press ignored because required models are not ready")
            return
        }
        guard state.permissions.microphone else {
            state.lastMessage = "请先允许麦克风权限。"
            return
        }
        guard preferences.refinementMode != .professional || refinerIsLoaded else {
            state.lastMessage = "专业精修模型仍在准备中。"
            settingsTask?.cancel()
            settingsTask = Task { [weak self] in await self?.reconcileRefinerWithPreferences() }
            return
        }

        skills.reload()
        let mode = preferences.refinementMode
        let skill = mode == .professional ? skills.selectionSnapshot : .general
        let snapshot = RequestSnapshot(id: UUID(), refinementMode: mode, skill: skill)
        activeRequest = snapshot
        pendingASRText = nil
        skipProfessionalRefinement = false
        state.resetTranscript()
        targetApplication = inserter.captureTarget()
        state.phase = .recording
        state.finalizationKind = mode == .professional ? .professional : .fast
        overlay.show(on: ScreenLocator.screenForFocusedWindow(pid: targetApplication?.pid))
        engine.begin()

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
            activeRequest = nil
            targetApplication = nil
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
        guard state.phase == .recording, let request = activeRequest else { return }
        maxDurationTask?.cancel()
        let capture = audio.stop()
        logger.notice("Recording stopped after \(capture.duration, format: .fixed(precision: 2)) seconds; speech=\(capture.containedSpeech)")
        guard capture.containedSpeech, capture.duration >= 0.08 else {
            cancelRecording(message: nil)
            return
        }

        // The visible state changes before any tail decode or model await.
        state.finalizationKind = request.refinementMode == .professional ? .professional : .fast
        state.phase = .finalizing
        refinementTask?.cancel()
        refinementTask = Task { [weak self] in
            await self?.finalize(capture: capture, request: request)
        }
    }

    private func finalize(capture: AudioCaptureResult, request: RequestSnapshot) async {
        var result = await engine.finish()
        guard isActive(request.id), !Task.isCancelled else { return }
        var rawText = TextCleaner.clean(result?.text ?? "")

        if rawText.isEmpty {
            logger.notice("ASR returned no text for voiced audio; retrying once with 250ms trailing silence")
            var retrySamples = capture.samples + Array(repeating: Float(0), count: 4_000)
            retrySamples = ASRAudioPadding.trailingSilence(
                retrySamples,
                minimumSampleCount: Int(ASRAudioPadding.minimumInferenceSeconds * 16_000)
            )
            result = await engine.transcribe(samples: retrySamples)
            guard isActive(request.id), !Task.isCancelled else { return }
            rawText = TextCleaner.clean(result?.text ?? "")
        }

        recordPerformance(result)
        pendingASRText = rawText
        guard !rawText.isEmpty else {
            await complete(rawText: "", request: request)
            return
        }

        var finalText = rawText
        if ProfessionalRefinementPolicy.invocationCount(
            mode: request.refinementMode,
            transcript: rawText
        ) == 1, !skipProfessionalRefinement {
            do {
                logger.notice("Starting the single whole-transcript professional refinement pass")
                finalText = try await refiner.refine(.init(
                    transcript: rawText,
                    skill: request.skill
                ))
            } catch is CancellationError {
                guard isActive(request.id) else { return }
                finalText = rawText
            } catch {
                logger.error("Professional refinement fell back to ASR: \(error.localizedDescription, privacy: .public)")
                finalText = rawText
            }
        }

        guard isActive(request.id), !Task.isCancelled else { return }
        await complete(rawText: finalText, request: request)
    }

    private func recordPerformance(_ result: LongContextTranscription?) {
        guard let result else { return }
        state.performance = .init(
            realTimeFactor: result.realTimeFactor,
            tokensPerSecond: result.tokensPerSecond,
            peakMemoryGB: result.peakMemoryGB,
            audioSeconds: result.audioSeconds
        )
        logger.notice("ASR decode finished: audio=\(result.audioSeconds, format: .fixed(precision: 2))s totalDecode=\(result.decodeSeconds, format: .fixed(precision: 2))s finalDecode=\(result.finalDecodeSeconds, format: .fixed(precision: 2))s outputChars=\(result.text.count) encoderWindows=\(result.encodedWindowCount) checkpoints=\(result.checkpointCount) peak=\(result.peakMemoryGB, format: .fixed(precision: 2))GB")
        if result.peakMemoryGB >= 5.0 {
            state.memoryWarning = String(format: "峰值 %.2fGB，已超过 5GB 发布阻断线。", result.peakMemoryGB)
        } else if result.peakMemoryGB >= 4.7 {
            state.memoryWarning = String(format: "峰值 %.2fGB，已超过 4.7GB 诊断线。", result.peakMemoryGB)
        }
    }

    private func handleStandaloneEscape() {
        guard state.phase == .finalizing,
              state.finalizationKind == .professional,
              let request = activeRequest else { return }
        skipProfessionalRefinement = true
        state.finalizationKind = .fast
        state.lastMessage = "已跳过专业精修，使用 ASR 原文。"

        // If ASR has already finished, paste the fallback without waiting for
        // the generation task to unwind. Its late result is ignored by UUID.
        if let pendingASRText {
            refinementTask?.cancel()
            Task { [weak self] in
                await self?.complete(rawText: pendingASRText, request: request)
            }
        }
    }

    private func cancelRecording(message: String?) {
        guard state.phase == .recording || state.phase == .finalizing else { return }
        maxDurationTask?.cancel()
        refinementTask?.cancel()
        _ = audio.stop()
        engine.cancel()
        overlay.hide()
        activeRequest = nil
        pendingASRText = nil
        targetApplication = nil
        state.resetTranscript()
        state.phase = .ready
        state.lastMessage = message
        settingsTask?.cancel()
        settingsTask = Task { [weak self] in await self?.reconcileRefinerWithPreferences() }
    }

    private func complete(rawText: String, request: RequestSnapshot) async {
        guard isActive(request.id), state.phase == .finalizing else { return }
        activeRequest = nil
        refinementTask = nil
        pendingASRText = nil
        // Skill pronunciation rows are contextual hints for the professional
        // refiner, never unconditional string replacements. A spoken form such
        // as "unit" may legitimately be an ordinary English word.
        let text = TextCleaner.clean(rawText)
        let target = targetApplication
        targetApplication = nil

        if text.isEmpty {
            state.lastMessage = "未识别到语音。"
        } else {
            let result = await inserter.insert(text, into: target)
            switch result {
            case .pasted: state.lastMessage = "已粘贴并保留在剪贴板。"
            case .clipboardOnly(let reason): state.lastMessage = reason
            }
        }

        try? await Task.sleep(for: .milliseconds(180))
        overlay.hide()
        state.phase = .ready
        skipProfessionalRefinement = false
        settingsTask?.cancel()
        settingsTask = Task { [weak self] in await self?.reconcileRefinerWithPreferences() }
    }

    private func isActive(_ id: UUID) -> Bool {
        activeRequest?.id == id && state.phase == .finalizing
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
