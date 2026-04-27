import Foundation

actor MatrixDebugLogger {
    static let shared = MatrixDebugLogger()

    private let fileManager = FileManager.default
    private let logURL: URL
    private let isoFormatter = ISO8601DateFormatter()
    private var currentLevel: MatrixDebugLogLevel

    private init() {
        let matrixLogsURL = Self.logDirectoryURL()
        try? fileManager.createDirectory(at: matrixLogsURL, withIntermediateDirectories: true)
        logURL = Self.logFileURL()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        currentLevel = Self.loadPersistedLevel()
    }

    func configure(level: MatrixDebugLogLevel) {
        currentLevel = level
    }

    func log(_ message: String, level: MatrixDebugLogLevel = .debug) {
        guard shouldLog(level) else { return }
        let line = "[\(isoFormatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if fileManager.fileExists(atPath: logURL.path) == false {
            fileManager.createFile(atPath: logURL.path, contents: data)
            return
        }

        do {
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            try? data.write(to: logURL, options: .atomic)
        }
    }

    func log(event: String, metadata: [String: String], level: MatrixDebugLogLevel = .debug) {
        guard shouldLog(level) else { return }
        let rendered = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        log("\(event) \(rendered)", level: level)
    }

    func path() -> String {
        logURL.path
    }

    private func shouldLog(_ level: MatrixDebugLogLevel) -> Bool {
        currentLevel != .off && level.priority >= currentLevel.priority
    }

    nonisolated private static func loadPersistedLevel() -> MatrixDebugLogLevel {
        let defaults = UserDefaults.standard
        let key = "matrix.app-settings"
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .off
        }
        return settings.debugLogLevel
    }

    nonisolated static func logDirectoryURL() -> URL {
        let fileManager = FileManager.default
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directoryName = Bundle.main.bundleIdentifier ?? "Matrix"
        return cachesURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    nonisolated static func logFileURL() -> URL {
        logDirectoryURL().appendingPathComponent("matrix.log")
    }
}
