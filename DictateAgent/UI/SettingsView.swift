import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var skills: SkillManager
    @ObservedObject var hotkeys: HotkeySettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: state.statusSymbol)
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Audio Smith").font(.title2.bold())
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
                    permissionRow("输入监控", granted: state.permissions.inputMonitoring)
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
                    Text("Qwen3-ASR-1.7B · MLX 8-bit · 纯本地")
                    if state.phase == .downloading {
                        ProgressView(value: state.downloadProgress)
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
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                    }
                    Text(skills.selectedSkillIDs.isEmpty
                         ? "未选择 Skill：使用通用听写。"
                         : "已选择 \(skills.selectedSkillIDs.count) 个 Skill；上下文会在每次听写开始前合并为不可变快照。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("打开 Skills 文件夹") { skills.revealUserSkillsDirectory() }
                    Text("组合 prompt 最多 8,000 字符和 300 个去重术语；修改将在下一次听写自动生效。")
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
                Button("重新下载模型") { AppRuntime.shared.reinstallModel() }
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
}
