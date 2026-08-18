import Foundation

enum ModelSourcePreference: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case modelScope
    case huggingFace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "自动"
        case .modelScope: "ModelScope"
        case .huggingFace: "Hugging Face"
        }
    }
}

enum ModelDownloadSource: String, Sendable {
    case modelScope
    case huggingFace

    var displayName: String {
        switch self {
        case .modelScope: "ModelScope"
        case .huggingFace: "Hugging Face"
        }
    }

    var fallback: ModelDownloadSource {
        self == .modelScope ? .huggingFace : .modelScope
    }
}

@MainActor
final class DictationPreferences: ObservableObject {
    static let shared = DictationPreferences()

    private enum Key {
        static let modelSource = "modelDownloadSource"
    }

    private let defaults: UserDefaults

    @Published private(set) var modelSource: ModelSourcePreference {
        didSet { defaults.set(modelSource.rawValue, forKey: Key.modelSource) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        modelSource = ModelSourcePreference(
            rawValue: defaults.string(forKey: Key.modelSource) ?? ""
        ) ?? .automatic
    }

    func selectModelSource(_ source: ModelSourcePreference) {
        modelSource = source
    }
}
