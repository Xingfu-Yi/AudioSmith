import XCTest
@testable import AudioSmith

@MainActor
final class DictationPreferencesTests: XCTestCase {
    func testProfessionalModeAndAutomaticSourceAreDefaults() {
        let suite = "DictationPreferencesTests.defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = DictationPreferences(defaults: defaults)
        XCTAssertEqual(preferences.refinementMode, .professional)
        XCTAssertEqual(preferences.modelSource, .automatic)
    }

    func testModeAndSourcePersist() {
        let suite = "DictationPreferencesTests.persistence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = DictationPreferences(defaults: defaults)
        first.selectRefinementMode(.fast)
        first.selectModelSource(.modelScope)

        let restored = DictationPreferences(defaults: defaults)
        XCTAssertEqual(restored.refinementMode, .fast)
        XCTAssertEqual(restored.modelSource, .modelScope)
    }
}
