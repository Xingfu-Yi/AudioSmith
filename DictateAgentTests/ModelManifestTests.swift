import XCTest
@testable import DictateAgent

final class ModelManifestTests: XCTestCase {
    func testPinnedManifestIsComplete() {
        let manifest = ModelManifest.qwen3ASR8Bit
        XCTAssertEqual(manifest.revision.count, 40)
        XCTAssertEqual(manifest.files.count, 9)
        XCTAssertEqual(manifest.files.first(where: { $0.path == "model.safetensors" })?.size, 2_463_307_541)
        XCTAssertTrue(manifest.files.allSatisfy { $0.sha256.count == 64 && $0.size > 0 })
    }
}

