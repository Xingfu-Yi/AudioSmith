import AppKit
import CryptoKit
import Foundation

@MainActor
final class SkillManager: ObservableObject {
    static let shared = SkillManager()

    @Published private(set) var skills: [DomainSkill] = [.general]
    @Published private(set) var selectedSkillIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(selectedSkillIDs).sorted(), forKey: Self.selectedKey)
        }
    }

    private static let selectedKey = "selectedSkillIDs"
    private static let activeKey = "activeSkillID"
    private static let starterSkillID = "aigc"
    private static let starterSeedKey = "didSeedEditableAIGCSkillV1"
    private static let pronunciationMigrationKey = "didMigrateAIGCPronunciationTableV2"
    private static let observedConfusionsMigrationKey = "didMigrateAIGCObservedConfusionsV3"
    private static let observedNormalizationMigrationKey = "didMigrateAIGCObservedNormalizationV4"
    private static let contextualNormalizationMigrationKey = "didMigrateAIGCContextualNormalizationV5"
    private static let legacyStarterSHA256 = "463e57feb51a10db369852cc844ed9736232f5508f62b25ef64bc7c7e4471b54"
    private static let pronunciationTableV2SHA256 = "cf98daf004faec36b6b49d1e10300851803399ad7cc61bd0ea6de5af688cd455"
    private static let observedConfusionsV3SHA256 = "12daefc1c5eebcec4eaa2b0680ef8ab011671cfa99cca7dd4ee8da5f1b507890"
    private static let observedNormalizationV4SHA256 = "9dd63d7c41fed0b019d9d8ca0605799e93a6a690900b45af5146f271a6b7ad10"
    private let fileManager = FileManager.default

    private init() {
        if let stored = UserDefaults.standard.stringArray(forKey: Self.selectedKey) {
            selectedSkillIDs = Set(stored)
        } else if let legacy = UserDefaults.standard.string(forKey: Self.activeKey),
                  legacy != DomainSkill.general.id {
            selectedSkillIDs = [legacy]
        } else {
            selectedSkillIDs = []
        }
        seedEditableAIGCSkillIfNeeded()
        migrateUnmodifiedStarterToPronunciationTableIfNeeded()
        migrateUnmodifiedStarterToObservedConfusionsIfNeeded()
        migrateUnmodifiedStarterToObservedNormalizationIfNeeded()
        migrateUnmodifiedStarterToContextualNormalizationIfNeeded()
        reload()
    }

    var selectedSkills: [DomainSkill] {
        skills.filter { selectedSkillIDs.contains($0.id) }
    }

    var selectionSnapshot: DomainSkill {
        DomainSkill.combined(selectedSkills)
    }

    func isSelected(_ skill: DomainSkill) -> Bool {
        selectedSkillIDs.contains(skill.id)
    }

    func setSelected(_ selected: Bool, skillID: String) {
        guard skillID != DomainSkill.general.id else { return }
        if selected {
            selectedSkillIDs.insert(skillID)
        } else {
            selectedSkillIDs.remove(skillID)
        }
    }

    func reload() {
        var loadedByID: [String: DomainSkill] = [DomainSkill.general.id: .general]
        let sources = [Bundle.main.resourceURL?.appendingPathComponent("Skills", isDirectory: true), Self.userSkillsDirectory]
        for source in sources.compactMap({ $0 }) {
            guard let enumerator = fileManager.enumerator(
                at: source,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let file as URL in enumerator where file.lastPathComponent == "SKILL.md" {
                guard let skill = try? load(file) else { continue }
                // Sources are ordered built-in first, user directory second, so
                // an editable user copy with the same identifier overrides it.
                loadedByID[skill.id] = skill
            }
        }
        skills = loadedByID.values.sorted { lhs, rhs in
            if lhs.id == DomainSkill.general.id { return true }
            if rhs.id == DomainSkill.general.id { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        let available = Set(skills.map(\.id))
        selectedSkillIDs = selectedSkillIDs.intersection(available)
    }

    private func seedEditableAIGCSkillIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.starterSeedKey) else { return }

        let destinationDirectory = Self.userSkillsDirectory.appendingPathComponent(Self.starterSkillID, isDirectory: true)
        let destination = destinationDirectory.appendingPathComponent("SKILL.md")
        if fileManager.fileExists(atPath: destination.path) {
            finishStarterSeed(defaults: defaults)
            return
        }

        guard let source = Bundle.main.resourceURL?
            .appendingPathComponent("Skills/\(Self.starterSkillID)/SKILL.md"),
              fileManager.fileExists(atPath: source.path) else { return }

        do {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
            finishStarterSeed(defaults: defaults)
        } catch {
            // The bundled fallback remains available. Retry seeding next launch
            // rather than overwriting a partially managed user directory.
        }
    }

    private func finishStarterSeed(defaults: UserDefaults) {
        selectedSkillIDs.insert(Self.starterSkillID)
        defaults.set(true, forKey: Self.starterSeedKey)
    }

    /// Upgrade only the exact previous bundled starter. Any user edit changes
    /// the digest and is therefore preserved verbatim.
    private func migrateUnmodifiedStarterToPronunciationTableIfNeeded() {
        migrateUnmodifiedStarterIfNeeded(
            defaultsKey: Self.pronunciationMigrationKey,
            expectedSHA256: Self.legacyStarterSHA256
        )
    }

    /// Add newly observed ASR confusions only to an untouched V2 starter.
    private func migrateUnmodifiedStarterToObservedConfusionsIfNeeded() {
        migrateUnmodifiedStarterIfNeeded(
            defaultsKey: Self.observedConfusionsMigrationKey,
            expectedSHA256: Self.pronunciationTableV2SHA256
        )
    }

    /// Add the next observed pronunciation only to an untouched V3 starter.
    private func migrateUnmodifiedStarterToObservedNormalizationIfNeeded() {
        migrateUnmodifiedStarterIfNeeded(
            defaultsKey: Self.observedNormalizationMigrationKey,
            expectedSHA256: Self.observedConfusionsV3SHA256
        )
    }

    /// Add the observed Adam/AdaLN confusion only to an untouched V4 starter.
    private func migrateUnmodifiedStarterToContextualNormalizationIfNeeded() {
        migrateUnmodifiedStarterIfNeeded(
            defaultsKey: Self.contextualNormalizationMigrationKey,
            expectedSHA256: Self.observedNormalizationV4SHA256
        )
    }

    private func migrateUnmodifiedStarterIfNeeded(
        defaultsKey: String,
        expectedSHA256: String
    ) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: defaultsKey) else { return }

        let destination = Self.userSkillsDirectory
            .appendingPathComponent(Self.starterSkillID, isDirectory: true)
            .appendingPathComponent("SKILL.md")
        guard let source = Bundle.main.resourceURL?
            .appendingPathComponent("Skills/\(Self.starterSkillID)/SKILL.md"),
              fileManager.fileExists(atPath: source.path),
              fileManager.fileExists(atPath: destination.path) else { return }

        do {
            let existing = try Data(contentsOf: destination)
            let digest = SHA256.hash(data: existing).map { String(format: "%02x", $0) }.joined()
            if digest == expectedSHA256 {
                let replacement = try Data(contentsOf: source)
                try replacement.write(to: destination, options: .atomic)
            }
            defaults.set(true, forKey: defaultsKey)
        } catch {
            // Retry next launch. Never replace a file unless its exact legacy
            // digest was verified and the atomic write succeeds.
        }
    }

    func revealUserSkillsDirectory() {
        try? fileManager.createDirectory(at: Self.userSkillsDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.userSkillsDirectory)
    }

    private func load(_ url: URL) throws -> DomainSkill {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) <= 256 * 1_024 else {
            throw SkillValidationError.tooLarge
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return try SkillDocumentParser.parse(
            markdown,
            folderName: url.deletingLastPathComponent().lastPathComponent
        )
    }

    static var userSkillsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AudioSmith/Skills", isDirectory: true)
    }
}
