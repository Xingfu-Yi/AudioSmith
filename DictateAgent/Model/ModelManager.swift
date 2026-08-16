import CryptoKit
import Foundation

final class ModelManager: @unchecked Sendable {
    struct Progress: Sendable {
        let completedBytes: Int64
        let totalBytes: Int64
    }

    private let manifest: ModelManifest
    private let fileManager: FileManager

    init(manifest: ModelManifest = .qwen3ASR8Bit, fileManager: FileManager = .default) {
        self.manifest = manifest
        self.fileManager = fileManager
    }

    var installedDirectory: URL {
        modelsRoot.appendingPathComponent(manifest.revision, isDirectory: true)
    }

    func prepare(progress: @escaping @MainActor @Sendable (Progress) -> Void) async throws -> URL {
        if let override = ProcessInfo.processInfo.environment["DICTATE_AGENT_MODEL_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            try verify(directory: url)
            return url
        }

        if fileManager.fileExists(atPath: installedDirectory.path) {
            do {
                try verify(directory: installedDirectory)
                await progress(.init(completedBytes: manifest.totalBytes, totalBytes: manifest.totalBytes))
                return installedDirectory
            } catch {
                let quarantine = modelsRoot.appendingPathComponent("\(manifest.revision).corrupt-\(Int(Date().timeIntervalSince1970))")
                try? fileManager.moveItem(at: installedDirectory, to: quarantine)
            }
        }

        try fileManager.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        let staging = modelsRoot.appendingPathComponent("\(manifest.revision).installing", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        let completedBefore = manifest.files.reduce(Int64(0)) { partial, file in
            let target = staging.appendingPathComponent(file.path)
            let size = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            return partial + min(size, file.size)
        }
        try ensureDiskCapacity(requiredBytes: max(0, manifest.totalBytes - completedBefore))

        var completedFiles: Int64 = 0
        for file in manifest.files {
            let target = staging.appendingPathComponent(file.path)
            if try isValid(file: file, at: target) {
                completedFiles += file.size
                await progress(.init(completedBytes: completedFiles, totalBytes: manifest.totalBytes))
                continue
            }

            if fileManager.fileExists(atPath: target.path) {
                let existing = Int64((try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                if existing > file.size { try fileManager.removeItem(at: target) }
            }

            guard let remote = remoteURL(for: file) else { throw ModelManagerError.invalidRemoteURL(file.path) }
            let base = completedFiles
            let transfer = HTTPRangeDownload(
                remoteURL: remote,
                destinationURL: target,
                expectedBytes: file.size,
                progress: { bytes in
                    Task { @MainActor in
                        progress(.init(completedBytes: base + bytes, totalBytes: self.manifest.totalBytes))
                    }
                }
            )
            try await transfer.start()
            guard try isValid(file: file, at: target) else {
                throw ModelManagerError.checksumMismatch(file.path)
            }
            completedFiles += file.size
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
        let old = modelsRoot.appendingPathComponent("\(manifest.revision).removed-\(Int(Date().timeIntervalSince1970))")
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

    private var modelsRoot: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DictateAgent/Models", isDirectory: true)
    }

    private func remoteURL(for file: ModelFile) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.path = "/\(manifest.repository)/resolve/\(manifest.revision)/\(file.path)"
        return components.url
    }

    private func ensureDiskCapacity(requiredBytes: Int64) throws {
        let values = try modelsRoot.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        guard available >= requiredBytes + 1_000_000_000 else {
            throw ModelManagerError.insufficientDisk(required: requiredBytes + 1_000_000_000, available: available)
        }
    }

    private func isValid(file: ModelFile, at url: URL) throws -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        let size = Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1)
        guard size == file.size else { return false }
        return try sha256(url) == file.sha256
    }

    private func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            guard let data = try? handle.read(upToCount: 4 * 1_024 * 1_024), !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum ModelManagerError: LocalizedError {
    case invalidRemoteURL(String)
    case checksumMismatch(String)
    case insufficientDisk(required: Int64, available: Int64)
    case invalidHTTPStatus(Int)
    case unexpectedDownloadSize(expected: Int64, actual: Int64)

    var errorDescription: String? {
        switch self {
        case .invalidRemoteURL(let path): "模型文件地址无效：\(path)"
        case .checksumMismatch(let path): "模型文件校验失败：\(path)"
        case .insufficientDisk(let required, let available):
            "磁盘空间不足，需要 \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file))，当前可用 \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))。"
        case .invalidHTTPStatus(let status): "模型下载失败，HTTP 状态码 \(status)。"
        case .unexpectedDownloadSize(let expected, let actual): "下载大小不正确：应为 \(expected)，实际为 \(actual)。"
        }
    }
}

private final class HTTPRangeDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let remoteURL: URL
    private let destinationURL: URL
    private let expectedBytes: Int64
    private let progress: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var fileHandle: FileHandle?
    private var session: URLSession?
    private var currentBytes: Int64 = 0
    private var initialOffset: Int64 = 0
    private var terminalError: Error?

    init(remoteURL: URL, destinationURL: URL, expectedBytes: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        self.remoteURL = remoteURL
        self.destinationURL = destinationURL
        self.expectedBytes = expectedBytes
        self.progress = progress
    }

    func start() async throws {
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        }
        initialOffset = Int64((try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        currentBytes = initialOffset
        fileHandle = try FileHandle(forWritingTo: destinationURL)
        try fileHandle?.seekToEnd()

        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 60
        if initialOffset > 0 { request.setValue("bytes=\(initialOffset)-", forHTTPHeaderField: "Range") }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.withLock { self.continuation = continuation }
            let configuration = URLSessionConfiguration.default
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForResource = 60 * 60
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.dataTask(with: request).resume()
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
            continuation?.resume(throwing: ModelManagerError.unexpectedDownloadSize(expected: expectedBytes, actual: actual))
        } else {
            continuation?.resume()
        }
    }
}
