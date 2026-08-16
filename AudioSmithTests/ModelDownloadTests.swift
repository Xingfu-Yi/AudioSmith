import CryptoKit
import XCTest
@testable import AudioSmith

final class ModelDownloadTests: XCTestCase {
    override func tearDown() {
        MockModelURLProtocol.handler = nil
        super.tearDown()
    }

    func testRangeDownloadResumesAnExistingPartialFile() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("model.bin")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: destination)

        MockModelURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=3-")
            return .init(status: 206, data: Data("def".utf8))
        }
        let download = HTTPRangeDownload(
            remoteURL: URL(string: "https://huggingface.co/test/model.bin")!,
            destinationURL: destination,
            expectedBytes: 6,
            sessionConfiguration: Self.mockConfiguration(),
            progress: { _ in }
        )

        try await download.start()
        XCTAssertEqual(try Data(contentsOf: destination), Data("abcdef".utf8))
    }

    func testRangeDownloadRestartsWhenServerIgnoresRange() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("model.bin")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: destination)

        MockModelURLProtocol.handler = { request in
            XCTAssertNotNil(request.value(forHTTPHeaderField: "Range"))
            return .init(status: 200, data: Data("complete".utf8))
        }
        let download = HTTPRangeDownload(
            remoteURL: URL(string: "https://modelscope.cn/test/model.bin")!,
            destinationURL: destination,
            expectedBytes: 8,
            sessionConfiguration: Self.mockConfiguration(),
            progress: { _ in }
        )

        try await download.start()
        XCTAssertEqual(try Data(contentsOf: destination), Data("complete".utf8))
    }

    @MainActor
    func testAutomaticSourceUsesTheOnlyManifestVerifiedProbe() async throws {
        let payload = Data("verified-config".utf8)
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = testManifest(payload: payload, revision: String(repeating: "a", count: 40))
        var selected: ModelDownloadSource?

        MockModelURLProtocol.handler = { request in
            if request.url?.host == "modelscope.cn" {
                return .init(status: 503, data: Data())
            }
            return .init(status: 200, data: payload)
        }
        let manager = ModelManager(
            manifest: manifest,
            sessionFactory: { URLSession(configuration: Self.mockConfiguration()) },
            downloadConfigurationFactory: Self.mockConfiguration,
            modelRootOverride: root
        )

        let installed = try await manager.prepare(
            source: .automatic,
            progress: { _ in },
            activeSource: { selected = $0 }
        )

        XCTAssertEqual(selected, .huggingFace)
        XCTAssertEqual(
            try Data(contentsOf: installed.appendingPathComponent("config.json")),
            payload
        )
    }

    @MainActor
    func testThreeConsecutiveFailuresSwitchToBackupSource() async throws {
        let payload = Data("mirror-identical".utf8)
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = testManifest(payload: payload, revision: String(repeating: "b", count: 40))
        let counter = RequestCounter()
        var sources: [ModelDownloadSource] = []

        MockModelURLProtocol.handler = { request in
            if request.url?.host == "modelscope.cn" {
                counter.increment()
                return .init(status: 503, data: Data())
            }
            return .init(status: 200, data: payload)
        }
        let manager = ModelManager(
            manifest: manifest,
            downloadConfigurationFactory: Self.mockConfiguration,
            modelRootOverride: root
        )

        let installed = try await manager.prepare(
            source: .modelScope,
            progress: { _ in },
            activeSource: { sources.append($0) }
        )

        XCTAssertEqual(counter.value, 3)
        XCTAssertEqual(sources, [.modelScope, .huggingFace])
        XCTAssertEqual(
            try Data(contentsOf: installed.appendingPathComponent("config.json")),
            payload
        )
    }

    private func testManifest(payload: Data, revision: String) -> ModelManifest {
        ModelManifest(
            identifier: "unit-test-model",
            purpose: .speechRecognition,
            repository: "example/unit-test-model",
            revision: revision,
            modelScopeRevision: "master",
            environmentOverrideKey: "AUDIO_SMITH_UNUSED_TEST_MODEL_PATH",
            files: [
                .init(
                    path: "config.json",
                    size: Int64(payload.count),
                    sha256: SHA256.hash(data: payload)
                        .map { String(format: "%02x", $0) }
                        .joined()
                )
            ]
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioSmithTests-\(UUID().uuidString)", isDirectory: true)
    }

    private static func mockConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockModelURLProtocol.self]
        return configuration
    }
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

private final class MockModelURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        let status: Int
        let data: Data
    }

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Response)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler,
              let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let result = handler(request)
        let response = HTTPURLResponse(
            url: url,
            statusCode: result.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": String(result.data.count)]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !result.data.isEmpty { client?.urlProtocol(self, didLoad: result.data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
