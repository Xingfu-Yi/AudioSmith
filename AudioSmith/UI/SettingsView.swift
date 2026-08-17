import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var skills: SkillManager
    @ObservedObject var hotkeys: HotkeySettings
    @ObservedObject var preferences: DictationPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: state.statusSymbol)
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Audio Smith").font(.title2.bold())
                        Text(AppVersion.displayName)
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                    Text(state.phase == .ready
                         ? "按住 \(hotkeys.selected.displayName) 开始听写"
                         : state.phase.title)
                        .foregroundStyle(.secondary)
                }
            }

            if let detail = state.phase.detail {
                Text(detail).foregroundStyle(.red)
            }

            GroupBox("听写快捷键") {
                Picker("按住说话", selection: hotkeyBinding) {
                    ForEach(DictationHotkey.allCases) { candidate in
                        Text(candidate.displayName).tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                .padding(6)
            }

            GroupBox("系统权限") {
                VStack(alignment: .leading, spacing: 10) {
                    permissionRow("麦克风", granted: state.permissions.microphone)
                    permissionRow("快捷键监听", granted: state.permissions.shortcutMonitoring)
                    permissionRow("辅助功能（自动粘贴）", granted: state.permissions.accessibility)
                    HStack {
                        Button("请求权限") {
                            Task { await AppRuntime.shared.requestPermissions() }
                        }
                        Button("打开系统设置") {
                            Permissions.openPrivacySettings()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("模型与性能") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("专业精修（Qwen3-1.7B + Skills）", isOn: professionalBinding)
                        .toggleStyle(.switch)
                    Text(preferences.refinementMode == .professional
                         ? "0.6B ASR 后对完整文本精修一次；准确性更高。"
                         : "极速听写仅使用 0.6B ASR；延迟和内存更低。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("下载源", selection: sourceBinding) {
                        ForEach(ModelSourcePreference.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(preferences.refinementMode == .professional
                         ? "Qwen3-ASR-0.6B 8-bit + Qwen3-1.7B MLX 4-bit · 纯本地"
                         : "Qwen3-ASR-0.6B 8-bit · 纯本地")
                    if state.phase == .downloading {
                        ProgressView(value: state.downloadProgress)
                        if let model = state.downloadingModelName {
                            Text(model + sourceSuffix)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(ByteCountFormatter.string(fromByteCount: state.downloadedBytes, countStyle: .file)
                             + " / "
                             + ByteCountFormatter.string(fromByteCount: state.totalDownloadBytes, countStyle: .file))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if state.performance.peakMemoryGB > 0 {
                        Text(String(
                            format: "本次峰值 %.2f GB · %.1f token/s · RTF %.3f",
                            state.performance.peakMemoryGB,
                            state.performance.tokensPerSecond,
                            state.performance.realTimeFactor
                        ))
                            .font(.caption.monospacedDigit())
                    }
                    if let warning = state.memoryWarning {
                        Text(warning).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("术语 Skills") {
                VStack(alignment: .leading, spacing: 10) {
                    if skills.skills.filter({ $0.id != DomainSkill.general.id }).isEmpty {
                        Text("尚未找到可选择的 Skill。")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(skills.skills.filter { $0.id != DomainSkill.general.id }) { skill in
                                    Toggle(isOn: selectionBinding(for: skill)) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(skill.name)
                                            Text(skill.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                    .disabled(preferences.refinementMode == .fast)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                    }
                    Text(preferences.refinementMode == .fast
                         ? "极速听写不加载 Skills；勾选会保留到下次开启专业精修。"
                         : (skills.selectedSkillIDs.isEmpty
                            ? "未选择 Skill：使用通用专业精修。"
                            : "已选择 \(skills.selectedSkillIDs.count) 个 Skill；上下文和词汇会进入下一次整段精修快照。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("打开 Skills 文件夹") { skills.revealUserSkillsDirectory() }
                    Text("Skills 不会进入 ASR；专业模式只在松开快捷键后，将最多 300 个去重术语和限额上下文提交给一次整段精修。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            Text("按住 \(hotkeys.selected.displayName) 时只显示波形；松开后使用完整语音上下文定稿并粘贴。按住期间按 Esc 取消，音频、转写正文和历史均不会写入磁盘。")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("重新下载模型") { AppRuntime.shared.reinstallModels() }
                Button("退出") { NSApp.terminate(nil) }
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func permissionRow(_ title: String, granted: Bool) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(title)
            Spacer()
            Text(granted ? "已允许" : "未允许").foregroundStyle(.secondary)
        }
    }

    private func selectionBinding(for skill: DomainSkill) -> Binding<Bool> {
        Binding(
            get: { skills.isSelected(skill) },
            set: { skills.setSelected($0, skillID: skill.id) }
        )
    }

    private var hotkeyBinding: Binding<DictationHotkey> {
        Binding(
            get: { hotkeys.selected },
            set: { AppRuntime.shared.selectHotkey($0) }
        )
    }

    private var professionalBinding: Binding<Bool> {
        Binding(
            get: { preferences.refinementMode == .professional },
            set: { AppRuntime.shared.selectRefinementMode($0 ? .professional : .fast) }
        )
    }

    private var sourceBinding: Binding<ModelSourcePreference> {
        Binding(
            get: { preferences.modelSource },
            set: { AppRuntime.shared.selectModelSource($0) }
        )
    }

    private var sourceSuffix: String {
        guard let source = state.activeDownloadSource else { return "" }
        return " · " + source.displayName
    }
}
