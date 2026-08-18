import XCTest
@testable import AudioSmith

@MainActor
final class DictationPreferencesTests: XCTestCase {
    func testAutomaticSourceIsDefault() {
        let suite = "DictationPreferencesTests.defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = DictationPreferences(defaults: defaults)
        XCTAssertEqual(preferences.modelSource, .automatic)
    }

    func testSourcePersists() {
        let suite = "DictationPreferencesTests.persistence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = DictationPreferences(defaults: defaults)
        first.selectModelSource(.modelScope)

        let restored = DictationPreferences(defaults: defaults)
        XCTAssertEqual(restored.modelSource, .modelScope)
    }
}
