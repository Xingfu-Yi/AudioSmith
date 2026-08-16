import XCTest
@testable import AudioSmith

final class ModelManifestTests: XCTestCase {
    func testPinnedManifestIsComplete() {
        let asr = ModelManifest.qwen3ASR06B8Bit
        let refiner = ModelManifest.qwen3Refiner17B4Bit

        XCTAssertEqual(asr.revision.count, 40)
        XCTAssertEqual(asr.environmentOverrideKey, "AUDIO_SMITH_ASR_MODEL_PATH")
        XCTAssertNotEqual(asr.environmentOverrideKey, "AUDIO_SMITH_MODEL_PATH")
        XCTAssertEqual(asr.files.count, 9)
        XCTAssertEqual(asr.files.first(where: { $0.path == "model.safetensors" })?.size, 1_006_229_426)
        XCTAssertEqual(refiner.revision.count, 40)
        XCTAssertEqual(refiner.files.count, 7)
        XCTAssertEqual(refiner.files.first(where: { $0.path == "model.safetensors" })?.size, 914_316_100)
        XCTAssertTrue((asr.files + refiner.files).allSatisfy {
            $0.sha256.count == 64 && $0.size > 0
        })
    }

    func testBothSourcesResolveTheSameManifestPaths() {
        let manifest = ModelManifest.qwen3ASR06B8Bit
        let huggingFace = ModelRemoteURLBuilder.url(
            source: .huggingFace,
            manifest: manifest,
            filePath: "config.json"
        )
        let modelScope = ModelRemoteURLBuilder.url(
            source: .modelScope,
            manifest: manifest,
            filePath: "config.json"
        )

        XCTAssertEqual(huggingFace?.host, "huggingface.co")
        XCTAssertTrue(huggingFace?.path.contains(manifest.revision) == true)
        XCTAssertEqual(modelScope?.host, "modelscope.cn")
        XCTAssertTrue(modelScope?.query?.contains("Revision=master") == true)
        XCTAssertTrue(modelScope?.query?.contains("FilePath=config.json") == true)
    }
}
