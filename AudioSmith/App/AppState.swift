import Foundation

enum AppPhase: Equatable, Sendable {
    case checking
    case unsupported(String)
    case downloading
    case loading
    case ready
    case recording
    case finalizing
    case error(String)

    var title: String {
        switch self {
        case .checking: "正在检查运行环境"
        case .unsupported: "此 Mac 不受支持"
        case .downloading: "正在下载模型"
        case .loading: "正在加载模型"
        case .ready: "可以开始听写"
        case .recording: "正在听写"
        case .finalizing: "正在定稿"
        case .error: "需要处理"
        }
    }

    var detail: String? {
        switch self {
        case .unsupported(let message), .error(let message): message
        default: nil
        }
    }
}

struct PermissionSnapshot: Equatable, Sendable {
    var microphone = false
    var shortcutMonitoring = false
    var accessibility = false

    var allGranted: Bool { microphone && shortcutMonitoring && accessibility }
}

struct TranscriptionPerformance: Equatable, Sendable {
    var realTimeFactor = 0.0
    var tokensPerSecond = 0.0
    var peakMemoryGB = 0.0
    var audioSeconds = 0.0
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var phase: AppPhase = .checking
    @Published var permissions = PermissionSnapshot()
    @Published var waveform = Array(repeating: CGFloat(0.08), count: 28)
    @Published var recordingSeconds = 0.0
    @Published var downloadProgress = 0.0
    @Published var downloadedBytes: Int64 = 0
    @Published var totalDownloadBytes: Int64 = 0
    @Published var downloadingModelName: String?
    @Published var activeDownloadSource: ModelDownloadSource?
    @Published var performance = TranscriptionPerformance()
    @Published var memoryWarning: String?
    @Published var lastMessage: String?
    private init() {}

    var statusSymbol: String {
        switch phase {
        case .recording: "waveform"
        case .finalizing, .downloading, .loading: "ellipsis.circle"
        case .ready: "mic.fill"
        case .checking: "hourglass"
        case .unsupported, .error: "exclamationmark.triangle"
        }
    }

    func resetTranscript() {
        performance = .init()
        waveform = Array(repeating: 0.08, count: 28)
        recordingSeconds = 0
        memoryWarning = nil
    }

    func appendWaveform(_ level: CGFloat) {
        waveform.removeFirst()
        waveform.append(max(0.08, min(1, level)))
    }
}
