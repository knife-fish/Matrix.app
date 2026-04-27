import Foundation
import Darwin

struct Aria2RuntimePaths {
    let supportDirectory: URL
    let configURL: URL
    let sessionURL: URL
    let dhtURL: URL
    let dht6URL: URL
    let pidURL: URL
}

nonisolated private struct Aria2PIDRecord: Codable {
    let pid: Int32
    let rpcPort: Int
}

enum Aria2ProcessError: LocalizedError {
    case executableNotFound
    case configFileNotFound
    case processStartFailed(String)
    case processNotRunning

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "aria2c executable not found."
        case .configFileNotFound:
            return "aria2 config file not found."
        case .processStartFailed(let message):
            return "aria2 failed to start: \(message)"
        case .processNotRunning:
            return "aria2 process is not running."
        }
    }
}

actor Aria2ProcessManager {
    static let shared = Aria2ProcessManager()
    
    private var process: Process?
    private var externalPID: pid_t?
    private var isRunning: Bool = false
    private var configPath: String?
    private var currentPort: Int = 16800
    private var lastErrorOutput: String = ""
    private var runtimePaths: Aria2RuntimePaths?
    
    private init() {}
    
    // MARK: - Configuration
    
    func setupConfiguration() async throws {
        let fileManager = FileManager.default

        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw Aria2ProcessError.configFileNotFound
        }

        let matrixSupportURL = appSupportURL.appendingPathComponent("Matrix", isDirectory: true)
        let configURL = matrixSupportURL.appendingPathComponent("aria2.conf")
        let sessionURL = matrixSupportURL.appendingPathComponent("download.session")
        let dhtURL = matrixSupportURL.appendingPathComponent("dht.dat")
        let dht6URL = matrixSupportURL.appendingPathComponent("dht6.dat")
        let pidURL = matrixSupportURL.appendingPathComponent("aria2.pid")

        if !fileManager.fileExists(atPath: matrixSupportURL.path) {
            try fileManager.createDirectory(at: matrixSupportURL, withIntermediateDirectories: true)
        }

        if !fileManager.fileExists(atPath: configURL.path) {
            if let bundleConfigURL = Bundle.main.url(forResource: "aria2", withExtension: "conf") {
                try fileManager.copyItem(at: bundleConfigURL, to: configURL)
            }
        }

        if !fileManager.fileExists(atPath: sessionURL.path) {
            fileManager.createFile(atPath: sessionURL.path, contents: Data())
        }

        configPath = configURL.path
        runtimePaths = Aria2RuntimePaths(
            supportDirectory: matrixSupportURL,
            configURL: configURL,
            sessionURL: sessionURL,
            dhtURL: dhtURL,
            dht6URL: dht6URL,
            pidURL: pidURL
        )
    }
    
    // MARK: - Process Control
    
    func start(preferredRPCPort: Int? = nil, rpcListenAll: Bool = false, additionalArgs: [String] = [], forceFresh: Bool = false) async throws -> Int{
        if !forceFresh, await checkStatus() {
            return currentPort
        }
        
        // Setup configuration on first start
        if configPath == nil {
            try await setupConfiguration()
        }
        
        guard let executableURL = findAria2Executable() else {
            throw Aria2ProcessError.executableNotFound
        }

        if !forceFresh, let recovered = recoverManagedProcessFromPIDFile() {
            currentPort = recovered.rpcPort ?? (preferredRPCPort ?? 16800)
            externalPID = recovered.pid
            process = nil
            isRunning = true
            return currentPort
        }
        
        // Use preferred port when provided; otherwise select an available port.
        currentPort = findAvailablePort(startingAt: preferredRPCPort ?? 16800)

        let process = Process()
        process.executableURL = executableURL
        
        // Build arguments - use command line args for RPC settings to override config
        var args: [String] = [
            "--enable-rpc=true",
            "--rpc-listen-port=\(currentPort)",
            "--rpc-allow-origin-all=true",
            "--rpc-listen-all=\(rpcListenAll ? "true" : "false")",
            "--rpc-max-request-size=1024M"
        ]
        
        // Add config file if available (command line args override config file)
        if let configPath = configPath, FileManager.default.fileExists(atPath: configPath) {
            args.append("--conf-path=\(configPath)")
        }
        
        // Add additional arguments
        args.append(contentsOf: additionalArgs)
        
        process.arguments = args
        process.terminationHandler = { [weak self] _ in
            Task {
                await self?.handleProcessTermination()
            }
        }
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        lastErrorOutput = ""
        
        do {
            try process.run()
            self.process = process
            self.externalPID = process.processIdentifier
            self.isRunning = true
            persistPID(process.processIdentifier, rpcPort: currentPort)
            
            Task {
                await monitorOutput(pipe: outputPipe, isError: false)
            }
            Task {
                await monitorOutput(pipe: errorPipe, isError: true)
            }
            
            try await Task.sleep(nanoseconds: 500_000_000)
            
            if !process.isRunning {
                let message = lastErrorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                throw Aria2ProcessError.processStartFailed(message.isEmpty ? "Process terminated immediately." : message)
            }
            
        } catch {
            if let processError = error as? Aria2ProcessError {
                throw processError
            }
            let message = lastErrorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Aria2ProcessError.processStartFailed(message.isEmpty ? error.localizedDescription : message)
        }
        return currentPort
    }
    
    func getCurrentPort() -> Int {
        return currentPort
    }

    func getRuntimePaths() async throws -> Aria2RuntimePaths {
        if runtimePaths == nil || configPath == nil {
            try await setupConfiguration()
        }
        guard let runtimePaths else {
            throw Aria2ProcessError.configFileNotFound
        }
        return runtimePaths
    }

    func clearSessionFile() async throws {
        let runtimePaths = try await getRuntimePaths()
        try Data().write(to: runtimePaths.sessionURL, options: .atomic)
    }
    
    func stop() async throws {
        if let process = process, process.isRunning {
            await terminate(process: process, gracefulTimeoutNanoseconds: 800_000_000)
            return
        }

        if let externalPID, isProcessAlive(pid: externalPID) {
            await terminate(pid: externalPID, gracefulTimeoutNanoseconds: 800_000_000)
            return
        }

        self.process = nil
        self.externalPID = nil
        self.isRunning = false
        throw Aria2ProcessError.processNotRunning
    }

    func stopIfRunning() async {
        if let process = process, process.isRunning {
            await terminate(process: process, gracefulTimeoutNanoseconds: 800_000_000)
            return
        }

        if let externalPID, isProcessAlive(pid: externalPID) {
            await terminate(pid: externalPID, gracefulTimeoutNanoseconds: 800_000_000)
            return
        }

        self.process = nil
        self.externalPID = nil
        self.isRunning = false
    }
    
    func checkStatus() async -> Bool {
        if let process = process, process.isRunning {
            externalPID = process.processIdentifier
            isRunning = true
            return true
        }

        if let externalPID, isProcessAlive(pid: externalPID) {
            isRunning = true
            return true
        }

        if let recovered = recoverManagedProcessFromPIDFile() {
            currentPort = recovered.rpcPort ?? currentPort
            externalPID = recovered.pid
            isRunning = true
            return true
        }

        process = nil
        externalPID = nil
        isRunning = false
        clearPIDFile()
        return false
    }
    
    func restart(preferredRPCPort: Int? = nil, rpcListenAll: Bool = false, additionalArgs: [String] = []) async throws {
        if isRunning {
            try? await stop()
        }
        _ = try await start(preferredRPCPort: preferredRPCPort, rpcListenAll: rpcListenAll, additionalArgs: additionalArgs, forceFresh: true)
    }
    
    // MARK: - Executable Discovery
    
    private func findAria2Executable() -> URL? {
        let fileManager = FileManager.default
        let architecture = getCurrentArchitecture()

        // Method 1: Try to find in Engine subdirectory using path(forResource:)
        let binaryName = architecture == .arm64 ? "aria2c" : "aria2c-\(architecture.rawValue)"

        if let bundleURL = Bundle.main.url(forResource: binaryName, withExtension: nil) {
            if fileManager.isExecutableFile(atPath: bundleURL.path) {
                return bundleURL
            }
        }
        
        // Method 2: Try direct path construction
        if let resourcePath = Bundle.main.resourcePath {
            let enginePath = URL(fileURLWithPath: resourcePath).appendingPathComponent("Engine")
            let aria2cPath = enginePath.appendingPathComponent("aria2c")

            if fileManager.isExecutableFile(atPath: aria2cPath.path) {
                return aria2cPath
            }
        }
        
        // Method 3: Check for architecture-specific binary
        if let resourcePath = Bundle.main.resourcePath {
            let enginePath = URL(fileURLWithPath: resourcePath).appendingPathComponent("Engine")
            let archBinaryPath = enginePath.appendingPathComponent(binaryName)
            if fileManager.isExecutableFile(atPath: archBinaryPath.path) {
                return archBinaryPath
            }
        }
        
        // Method 4: Check system paths
        let systemPaths = [
            "/usr/local/bin/aria2c",
            "/opt/homebrew/bin/aria2c",
            "/usr/bin/aria2c",
        ]
        
        for path in systemPaths {
            let url = URL(fileURLWithPath: path)
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        
        // Method 5: Check PATH environment
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            let paths = path.split(separator: ":").map(String.init)
            for dir in paths {
                let url = URL(fileURLWithPath: dir).appendingPathComponent("aria2c")
                if fileManager.isExecutableFile(atPath: url.path) {
                    return url
                }
            }
        }

        return nil
    }
    
    // MARK: - Port Management
    
    private func findAvailablePort(startingAt startPort: Int) -> Int {
        if startPort > 0, isPortAvailable(startPort) {
            return startPort
        }

        for port in 16800...16850 where isPortAvailable(port) {
            return port
        }

        for _ in 0..<64 {
            let candidate = Int.random(in: 50000...65000)
            if isPortAvailable(candidate) {
                return candidate
            }
        }

        return startPort > 0 ? startPort : 16800
    }

    
    // MARK: - Architecture Detection
    
    enum Architecture: String {
        case arm64 = "arm64"
        case x86_64 = "x86_64"
        case unknown = "unknown"
    }
    
    private func getCurrentArchitecture() -> Architecture {
#if arch(arm64)
        return .arm64
#elseif arch(x86_64)
        return .x86_64
#else
        return .unknown
#endif
    }
    
    func getArchitecture() -> Architecture {
        return getCurrentArchitecture()
    }
    
    // MARK: - Private Helpers
    
    private func handleProcessTermination() {
        isRunning = false
        process = nil
        externalPID = nil
        clearPIDFile()
    }

    private func terminate(process: Process, gracefulTimeoutNanoseconds: UInt64) async {
        let pid = process.processIdentifier
        if pid > 0 {
            kill(pid, SIGTERM)
        } else {
            process.terminate()
        }

        let startTime = ContinuousClock().now
        while isProcessAlive(pid: pid) {
            let elapsed = startTime.duration(to: ContinuousClock().now)
            if elapsed >= .nanoseconds(gracefulTimeoutNanoseconds) {
                if pid > 0 {
                    kill(pid, SIGKILL)
                } else {
                    process.interrupt()
                    process.terminate()
                }
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        self.process = nil
        self.externalPID = nil
        self.isRunning = false
        clearPIDFile()
    }

    private func terminate(pid: pid_t, gracefulTimeoutNanoseconds: UInt64) async {
        guard pid > 0 else {
            self.process = nil
            self.externalPID = nil
            self.isRunning = false
            return
        }

        kill(pid, SIGTERM)

        let startTime = ContinuousClock().now
        while isProcessAlive(pid: pid) {
            let elapsed = startTime.duration(to: ContinuousClock().now)
            if elapsed >= .nanoseconds(gracefulTimeoutNanoseconds) {
                kill(pid, SIGKILL)
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        self.process = nil
        self.externalPID = nil
        self.isRunning = false
        clearPIDFile()
    }
    
    private func monitorOutput(pipe: Pipe, isError: Bool) async {
        let fileHandle = pipe.fileHandleForReading
        
        do {
            for try await line in fileHandle.bytes.lines {
                if isError {
                    if !line.isEmpty {
                        if lastErrorOutput.isEmpty {
                            lastErrorOutput = line
                        } else {
                            lastErrorOutput += "\n\(line)"
                        }
                    }
                }
            }
        } catch {}
    }
    
    // MARK: - Configuration Management
    
    func getConfigPath() -> String? {
        return configPath
    }
    
    func updateConfigFile(content: String) async throws {
        guard let configPath = configPath else {
            throw Aria2ProcessError.configFileNotFound
        }
        
        let url = URL(fileURLWithPath: configPath)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    func readConfigFile() async throws -> String {
        guard let configPath = configPath else {
            throw Aria2ProcessError.configFileNotFound
        }
        
        let url = URL(fileURLWithPath: configPath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func isPortAvailable(_ port: Int) -> Bool {
        if isTCPPortListening(port) {
            return false
        }

        return canBindIPv4(port) && canBindIPv6(port)
    }

    private func isProcessAlive(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    private func recoverManagedProcessFromPIDFile() -> (pid: pid_t, rpcPort: Int?)? {
        guard let runtimePaths else { return nil }
        guard let persisted = loadPIDRecord(from: runtimePaths.pidURL) else {
            return nil
        }
        guard isProcessAlive(pid: persisted.pid) else {
            clearPIDFile()
            return nil
        }
        return (pid: persisted.pid, rpcPort: persisted.rpcPort)
    }

    private func persistPID(_ pid: pid_t, rpcPort: Int) {
        guard let runtimePaths else { return }
        let record = Aria2PIDRecord(pid: pid, rpcPort: rpcPort)
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: runtimePaths.pidURL, options: .atomic)
    }

    private func clearPIDFile() {
        guard let runtimePaths else { return }
        try? FileManager.default.removeItem(at: runtimePaths.pidURL)
    }

    private func loadPIDRecord(from url: URL) -> (pid: pid_t, rpcPort: Int?)? {
        if let data = try? Data(contentsOf: url),
           let record = try? JSONDecoder().decode(Aria2PIDRecord.self, from: data),
           record.pid > 0 {
            let rpcPort = record.rpcPort > 0 ? record.rpcPort : nil
            return (pid: record.pid, rpcPort: rpcPort)
        }

        guard let pidString = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = pid_t(pidString),
              pid > 0 else {
            return nil
        }

        let fallbackPort = currentPort > 0 ? currentPort : nil
        return (pid: pid, rpcPort: fallbackPort)
    }

    private func isTCPPortListening(_ port: Int) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return false
        }

        guard task.terminationStatus == 0 else {
            return false
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output
            .split(separator: "\n")
            .contains(where: { $0.contains(":\(port)") })
    }

    private func canBindIPv4(_ port: Int) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("0.0.0.0"))

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.stride)) == 0
            }
        }
    }

    private func canBindIPv6(_ port: Int) -> Bool {
        let socketFD = socket(AF_INET6, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }

        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.stride)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = in_port_t(UInt16(port).bigEndian)
        address.sin6_addr = in6addr_any

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in6>.stride)) == 0
            }
        }
    }
}
