import CryptoKit
import Foundation

final class ModelManager: @unchecked Sendable {
    struct Progress: Sendable {
        let completedBytes: Int64
        let totalBytes: Int64
    }

    private let manifest: ModelManifest
    private let fileManager: FileManager
    private let sessionFactory: @Sendable () -> URLSession
    private let downloadConfigurationFactory: @Sendable () -> URLSessionConfiguration
    private let modelRootOverride: URL?

    init(
        manifest: ModelManifest,
        fileManager: FileManager = .default,
        sessionFactory: @escaping @Sendable () -> URLSession = ModelManager.defaultSession,
        downloadConfigurationFactory: @escaping @Sendable () -> URLSessionConfiguration = ModelManager.downloadSessionConfiguration,
        modelRootOverride: URL? = nil
    ) {
        self.manifest = manifest
        self.fileManager = fileManager
        self.sessionFactory = sessionFactory
        self.downloadConfigurationFactory = downloadConfigurationFactory
        self.modelRootOverride = modelRootOverride
    }

    var installedDirectory: URL {
        modelRoot.appendingPathComponent(manifest.revision, isDirectory: true)
    }

    func prepare(
        source preference: ModelSourcePreference,
        progress: @escaping @MainActor @Sendable (Progress) -> Void,
        activeSource: @escaping @MainActor @Sendable (ModelDownloadSource) -> Void = { _ in }
    ) async throws -> URL {
        if let override = ProcessInfo.processInfo.environment[manifest.environmentOverrideKey],
           !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            try verify(directory: url)
            return url
        }

        // Installed models are entirely offline. Auto source probing is only
        // performed when bytes are actually missing.
        if fileManager.fileExists(atPath: installedDirectory.path) {
            do {
                try verify(directory: installedDirectory)
                await progress(.init(completedBytes: manifest.totalBytes, totalBytes: manifest.totalBytes))
                return installedDirectory
            } catch {
                let quarantine = modelRoot.appendingPathComponent(
                    "\(manifest.revision).corrupt-\(Int(Date().timeIntervalSince1970))"
                )
                try? fileManager.moveItem(at: installedDirectory, to: quarantine)
            }
        }

        try fileManager.createDirectory(at: modelRoot, withIntermediateDirectories: true)
        let staging = modelRoot.appendingPathComponent("\(manifest.revision).installing", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        let completedBefore = manifest.files.reduce(Int64(0)) { partial, file in
            let target = staging.appendingPathComponent(file.path)
            return partial + ((try? isValid(file: file, at: target)) == true ? file.size : 0)
        }
        try ensureDiskCapacity(requiredBytes: max(0, manifest.totalBytes - completedBefore))

        var source = try await selectSource(preference)
        await activeSource(source)
        var consecutiveFailures = 0
        var completedFiles: Int64 = 0

        for file in manifest.files {
            try Task.checkCancellation()
            let target = staging.appendingPathComponent(file.path)
            if try isValid(file: file, at: target) {
                completedFiles += file.size
                await progress(.init(completedBytes: completedFiles, totalBytes: manifest.totalBytes))
                consecutiveFailures = 0
                continue
            }

            if fileManager.fileExists(atPath: target.path) {
                let existing = fileSize(at: target)
                if existing > file.size { try fileManager.removeItem(at: target) }
            }

            var downloaded = false
            var lastError: Error = ModelManagerError.noReachableSource
            var sourceSwitches = 0
            while !downloaded, sourceSwitches < 2 {
                do {
                    guard let remote = ModelRemoteURLBuilder.url(
                        source: source,
                        manifest: manifest,
                        filePath: file.path
                    ) else {
                        throw ModelManagerError.invalidRemoteURL(file.path)
                    }
                    let base = completedFiles
                    let transfer = HTTPRangeDownload(
                        remoteURL: remote,
                        destinationURL: target,
                        expectedBytes: file.size,
                        sessionConfiguration: downloadConfigurationFactory(),
                        progress: { bytes in
                            Task { @MainActor in
                                progress(.init(
                                    completedBytes: base + min(bytes, file.size),
                                    totalBytes: self.manifest.totalBytes
                                ))
                            }
                        }
                    )
                    try await transfer.start()
                    guard try isValid(file: file, at: target) else {
                        throw ModelManagerError.checksumMismatch(file.path)
                    }
                    downloaded = true
                    consecutiveFailures = 0
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    lastError = error
                    consecutiveFailures += 1
                    if case ModelManagerError.checksumMismatch = error {
                        try? fileManager.removeItem(at: target)
                    }

                    if consecutiveFailures >= 3 {
                        // Completed files remain. Only the current unfinished
                        // file is discarded before changing mirrors.
                        try? fileManager.removeItem(at: target)
                        source = source.fallback
                        sourceSwitches += 1
                        consecutiveFailures = 0
                        await activeSource(source)
                    }
                }
            }
            guard downloaded else { throw lastError }
            completedFiles += file.size
            await progress(.init(completedBytes: completedFiles, totalBytes: manifest.totalBytes))
        }

        try verify(directory: staging)
        if fileManager.fileExists(atPath: installedDirectory.path) {
            try fileManager.removeItem(at: installedDirectory)
        }
        try fileManager.moveItem(at: staging, to: installedDirectory)
        return installedDirectory
    }

    func removeInstalledModel() throws {
        guard fileManager.fileExists(atPath: installedDirectory.path) else { return }
        try fileManager.createDirectory(at: modelRoot, withIntermediateDirectories: true)
        let old = modelRoot.appendingPathComponent(
            "\(manifest.revision).removed-\(Int(Date().timeIntervalSince1970))"
        )
        try fileManager.moveItem(at: installedDirectory, to: old)
    }

    func verify(directory: URL) throws {
        for file in manifest.files {
            let url = directory.appendingPathComponent(file.path)
            guard try isValid(file: file, at: url) else {
                throw ModelManagerError.checksumMismatch(file.path)
            }
        }
    }

    private func selectSource(_ preference: ModelSourcePreference) async throws -> ModelDownloadSource {
        switch preference {
        case .modelScope:
            return .modelScope
        case .huggingFace:
            return .huggingFace
        case .automatic:
            return try await fastestVerifiedSource()
        }
    }

    private func fastestVerifiedSource() async throws -> ModelDownloadSource {
        try await withThrowingTaskGroup(of: (ModelDownloadSource, TimeInterval)?.self) { group in
            defer { group.cancelAll() }
            for source in [ModelDownloadSource.modelScope, .huggingFace] {
                group.addTask { [manifest, sessionFactory] in
                    guard let url = ModelRemoteURLBuilder.url(
                        source: source,
                        manifest: manifest,
                        filePath: manifest.probeFile.path
                    ) else { return nil }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 3
                    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                    let start = ContinuousClock.now
                    do {
                        let (data, response) = try await sessionFactory().data(for: request)
                        guard let http = response as? HTTPURLResponse,
                              (200..<300).contains(http.statusCode),
                              Int64(data.count) == manifest.probeFile.size,
                              Self.sha256(data) == manifest.probeFile.sha256 else {
                            return nil
                        }
                        return (source, start.duration(to: .now).timeInterval)
                    } catch {
                        return nil
                    }
                }
            }

            while let result = try await group.next() {
                // The first manifest-verified response is, by definition, the
                // faster source for this download attempt.
                if let result { return result.0 }
            }
            throw ModelManagerError.noReachableSource
        }
    }

    private var modelRoot: URL {
        if let modelRootOverride { return modelRootOverride }
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioSmith/Models", isDirectory: true)
            .appendingPathComponent(manifest.identifier, isDirectory: true)
    }

    private func ensureDiskCapacity(requiredBytes: Int64) throws {
        let values = try modelRoot.deletingLastPathComponent().resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        guard available >= requiredBytes + 1_000_000_000 else {
            throw ModelManagerError.insufficientDisk(
                required: requiredBytes + 1_000_000_000,
                available: available
            )
        }
    }

    private func isValid(file: ModelFile, at url: URL) throws -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        let size = fileSize(at: url)
        guard size == file.size else { return false }
        return try sha256(url) == file.sha256
    }

    /// `URL.resourceValues` may retain a stale file-size cache when a target URL
    /// existed before an asynchronous download replaced its contents. Fetching
    /// fresh filesystem attributes avoids false checksum failures after a
    /// successful transfer or mirror switch.
    private func fileSize(at url: URL) -> Int64 {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? -1
    }

    private func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            guard let data = try? handle.read(upToCount: 4 * 1_024 * 1_024), !data.isEmpty else {
                return false
            }
            hasher.update(data: data)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func defaultSession() -> URLSession {
        URLSession(configuration: probeSessionConfiguration())
    }

    private static func probeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 3
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return configuration
    }

    private static func downloadSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60
        return configuration
    }
}

enum ModelRemoteURLBuilder {
    static func url(
        source: ModelDownloadSource,
        manifest: ModelManifest,
        filePath: String
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        switch source {
        case .huggingFace:
            components.host = "huggingface.co"
            components.path = "/\(manifest.repository)/resolve/\(manifest.revision)/\(filePath)"
        case .modelScope:
            components.host = "modelscope.cn"
            components.path = "/api/v1/models/\(manifest.repository)/repo"
            components.queryItems = [
                .init(name: "Revision", value: manifest.modelScopeRevision),
                .init(name: "FilePath", value: filePath),
            ]
        }
        return components.url
    }
}

enum ModelManagerError: LocalizedError {
    case invalidRemoteURL(String)
    case checksumMismatch(String)
    case insufficientDisk(required: Int64, available: Int64)
    case invalidHTTPStatus(Int)
    case unexpectedDownloadSize(expected: Int64, actual: Int64)
    case noReachableSource

    var errorDescription: String? {
        switch self {
        case .invalidRemoteURL(let path): "模型文件地址无效：\(path)"
        case .checksumMismatch(let path): "模型文件校验失败：\(path)"
        case .insufficientDisk(let required, let available):
            "磁盘空间不足，需要 \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file))，当前可用 \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))。"
        case .invalidHTTPStatus(let status): "模型下载失败，HTTP 状态码 \(status)。"
        case .unexpectedDownloadSize(let expected, let actual):
            "下载大小不正确：应为 \(expected)，实际为 \(actual)。"
        case .noReachableSource:
            "ModelScope 与 Hugging Face 均无法通过模型清单校验，请检查网络后重试。"
        }
    }
}

final class HTTPRangeDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let remoteURL: URL
    private let destinationURL: URL
    private let expectedBytes: Int64
    private let sessionConfiguration: URLSessionConfiguration
    private let progress: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var fileHandle: FileHandle?
    private var session: URLSession?
    private var currentBytes: Int64 = 0
    private var initialOffset: Int64 = 0
    private var terminalError: Error?

    init(
        remoteURL: URL,
        destinationURL: URL,
        expectedBytes: Int64,
        sessionConfiguration: URLSessionConfiguration,
        progress: @escaping @Sendable (Int64) -> Void
    ) {
        self.remoteURL = remoteURL
        self.destinationURL = destinationURL
        self.expectedBytes = expectedBytes
        self.sessionConfiguration = sessionConfiguration
        self.progress = progress
    }

    func start() async throws {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: destinationURL.path)
        initialOffset = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        currentBytes = initialOffset
        fileHandle = try FileHandle(forWritingTo: destinationURL)
        try fileHandle?.seekToEnd()

        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 60
        if initialOffset > 0 {
            request.setValue("bytes=\(initialOffset)-", forHTTPHeaderField: "Range")
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock { self.continuation = continuation }
                let session = URLSession(
                    configuration: sessionConfiguration,
                    delegate: self,
                    delegateQueue: nil
                )
                self.session = session
                let task = session.dataTask(with: request)
                task.resume()
                if Task.isCancelled { session.invalidateAndCancel() }
            }
        } onCancel: {
            self.session?.invalidateAndCancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse else {
            terminalError = URLError(.badServerResponse)
            completionHandler(.cancel)
            return
        }
        guard response.statusCode == 200 || response.statusCode == 206 else {
            terminalError = ModelManagerError.invalidHTTPStatus(response.statusCode)
            completionHandler(.cancel)
            return
        }
        if initialOffset > 0, response.statusCode == 200 {
            do {
                try fileHandle?.truncate(atOffset: 0)
                try fileHandle?.seek(toOffset: 0)
                currentBytes = 0
            } catch {
                terminalError = error
                completionHandler(.cancel)
                return
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try fileHandle?.write(contentsOf: data)
            currentBytes += Int64(data.count)
            progress(currentBytes)
        } catch {
            terminalError = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? fileHandle?.close()
        fileHandle = nil
        session.finishTasksAndInvalidate()
        let resultError = terminalError ?? error
        let actual = currentBytes
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        if let resultError {
            continuation?.resume(throwing: resultError)
        } else if actual != expectedBytes {
            continuation?.resume(throwing: ModelManagerError.unexpectedDownloadSize(
                expected: expectedBytes,
                actual: actual
            ))
        } else {
            continuation?.resume()
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let values = components
        return TimeInterval(values.seconds) + TimeInterval(values.attoseconds) / 1e18
    }
}
