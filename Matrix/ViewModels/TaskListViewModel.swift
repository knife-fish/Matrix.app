import Foundation
import Combine
import AppKit
import Darwin

@MainActor
final class TaskListViewModel: ObservableObject {
    @Published private(set) var tasks: [DownloadTask] = []
    @Published var filter: TaskFilter = .all
    @Published var globalDownloadSpeed: Int64 = 0
    @Published var globalUploadSpeed: Int64 = 0
    @Published var lastErrorMessage: String?

    private var cancellables = Set<AnyCancellable>()
    private let aria2Service: Aria2RPCService
    private let settingsStore: SettingsStore
    private let persistenceURL: URL
    private var recentlyDeletedGIDs = [String: Date]()
    private var recentlyDeletedIdentityKeys = [String: Date]()
    private var isRefreshingTasks = false
    private var lastRemoteDiscoveryAt: Date?

    private let summaryStatusKeys = [
        "gid",
        "status",
        "totalLength",
        "completedLength",
        "downloadSpeed",
        "uploadSpeed",
        "connections",
        "errorMessage",
        "numSeeders",
        "seeder",
        "pieceLength",
        "bitfield"
    ]

    private let discoveryStatusKeys = [
        "gid",
        "status",
        "totalLength",
        "completedLength",
        "downloadSpeed",
        "uploadSpeed",
        "connections",
        "errorMessage",
        "numSeeders",
        "seeder",
        "pieceLength",
        "bitfield",
        "dir",
        "files",
        "bittorrent"
    ]

    init(settingsStore: SettingsStore, aria2Service: Aria2RPCService = .shared) {
        self.aria2Service = aria2Service
        self.settingsStore = settingsStore

        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Matrix", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Matrix", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true, attributes: nil)
        self.persistenceURL = supportDirectory.appendingPathComponent("tasks.json")

        loadTasks()
        setupTimer()
    }

    var filteredTasks: [DownloadTask] {
        switch filter {
        case .all:
            return tasks
        case .downloading:
            return tasks.filter { $0.status == .downloading }
        case .waiting:
            return tasks.filter { $0.status == .waiting }
        case .completed:
            return tasks.filter { $0.status == .completed }
        case .stopped:
            return tasks.filter { $0.status == .paused || $0.status == .error }
        }
    }

    func loadTasks() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let decoded = try? JSONDecoder().decode([DownloadTask].self, from: data) else {
            tasks = []
            return
        }
        let refreshed = decoded
            .map(refreshFromFilesystem)
            .reduce(into: [DownloadTask]()) { partialResult, task in
                mergeRecoveredTask(task, into: &partialResult)
            }
            .sorted { $0.createdAt > $1.createdAt }
        tasks = refreshed
        if refreshed != decoded.sorted(by: { $0.createdAt > $1.createdAt }) {
            persist()
        }
    }

    func addURLTasks(
        urls: [String],
        savePath: String,
        filename: String?,
        threadCount: Int
    ) async {
        await MatrixDebugLogger.shared.log(
            event: "task.addURLTasks.begin",
            metadata: [
                "count": String(urls.count),
                "filename": filename ?? "<nil>",
                "savePath": savePath,
                "threadCount": String(threadCount)
            ],
            level: .info
        )
        do {
            try await ensureRPCReady()
        } catch {
            await MatrixDebugLogger.shared.log(
                event: "task.addURLTasks.rpcNotReady",
                metadata: [
                    "error": error.localizedDescription
                ],
                level: .error
            )
            lastErrorMessage = L10n.format("download_engine_not_ready", language: settingsStore.settings.appLanguage, error.localizedDescription)
            return
        }
        let startImmediately = settingsStore.settings.autoStartDownloads

        for urlString in urls {
            let resolvedName = filename?.nilIfBlank
                ?? URL(string: urlString)?.lastPathComponent.nilIfBlank
                ?? "untitled"
            if hasExistingTask(url: urlString, savePath: savePath, filename: resolvedName) {
                await MatrixDebugLogger.shared.log(
                    event: "task.addURLTasks.duplicateSkipped",
                    metadata: [
                        "filename": resolvedName,
                        "url": urlString
                    ],
                    level: .debug
                )
                continue
            }
            var task = DownloadTask(
                url: urlString,
                filename: resolvedName,
                kind: urlString.hasPrefix("magnet:") ? .magnet : .direct,
                status: startImmediately ? .waiting : .paused,
                savePath: savePath
            )
            tasks.insert(task, at: 0)
            persist()

            do {
                await MatrixDebugLogger.shared.log(
                    event: "task.addURLTasks.addDownload",
                    metadata: [
                        "filename": resolvedName,
                        "startImmediately": startImmediately ? "true" : "false",
                        "url": urlString
                    ],
                    level: .info
                )
                let gid = try await aria2Service.addDownload(
                    url: urlString,
                    savePath: savePath,
                    filename: filename?.nilIfBlank,
                    threadCount: threadCount,
                    startImmediately: startImmediately
                )
                task.gid = gid
                update(task)
                await MatrixDebugLogger.shared.log(
                    event: "task.addURLTasks.success",
                    metadata: [
                        "filename": resolvedName,
                        "gid": gid,
                        "url": urlString
                    ],
                    level: .info
                )
            } catch {
                task.status = .error
                task.errorMessage = error.localizedDescription
                update(task)
                await MatrixDebugLogger.shared.log(
                    event: "task.addURLTasks.failure",
                    metadata: [
                        "error": error.localizedDescription,
                        "filename": resolvedName,
                        "url": urlString
                    ],
                    level: .error
                )
                lastErrorMessage = L10n.format("add_task_failed", language: settingsStore.settings.appLanguage, error.localizedDescription)
            }
        }
    }

    func addTorrentFile(fileURL: URL, savePath: String, selectedFileIndexes: Set<Int>? = nil) async {
        do {
            try await ensureRPCReady()
        } catch {
            lastErrorMessage = L10n.format("download_engine_not_ready", language: settingsStore.settings.appLanguage, error.localizedDescription)
            return
        }
        let requestedIndexes = selectedFileIndexes?.sorted()
        let hasCustomSelection = !(requestedIndexes?.isEmpty ?? true)
        let startImmediately = settingsStore.settings.autoStartDownloads && !hasCustomSelection
        do {
            let data = try Data(contentsOf: fileURL)
            var task = DownloadTask(
                url: fileURL.path,
                filename: fileURL.lastPathComponent,
                kind: .torrent,
                status: startImmediately ? .waiting : .paused,
                savePath: savePath
            )
            tasks.insert(task, at: 0)
            persist()

            let gid = try await aria2Service.addTorrent(
                base64Torrent: data.base64EncodedString(),
                savePath: savePath,
                startImmediately: startImmediately
            )
            task.gid = gid

            if let requestedIndexes, !requestedIndexes.isEmpty {
                try await aria2Service.changeOption(
                    gid: gid,
                    options: ["select-file": requestedIndexes.map(String.init).joined(separator: ",")]
                )
                if settingsStore.settings.autoStartDownloads {
                    _ = try await aria2Service.resumeDownload(gid: gid)
                    task.status = .waiting
                }
            }

            update(task)
        } catch {
            lastErrorMessage = L10n.format("import_torrent_failed", language: settingsStore.settings.appLanguage, error.localizedDescription)
        }
    }

    func addMetalinkFile(fileURL: URL, savePath: String) async {
        do {
            try await ensureRPCReady()
        } catch {
            lastErrorMessage = L10n.format("download_engine_not_ready", language: settingsStore.settings.appLanguage, error.localizedDescription)
            return
        }
        let startImmediately = settingsStore.settings.autoStartDownloads
        do {
            let data = try Data(contentsOf: fileURL)
            let gids = try await aria2Service.addMetalink(
                metalink: data.base64EncodedString(),
                savePath: savePath,
                startImmediately: startImmediately
            )

            if gids.isEmpty {
                lastErrorMessage = L10n.text("metalink_empty", language: settingsStore.settings.appLanguage)
                return
            }

            for (index, gid) in gids.enumerated() {
                let task = DownloadTask(
                    url: fileURL.path,
                    filename: gids.count == 1 ? fileURL.lastPathComponent : "\(fileURL.deletingPathExtension().lastPathComponent)-\(index + 1)",
                    kind: .metalink,
                    status: startImmediately ? .waiting : .paused,
                    savePath: savePath,
                    gid: gid
                )
                tasks.insert(task, at: 0)
            }
            persist()
        } catch {
            lastErrorMessage = L10n.format("import_metalink_failed", language: settingsStore.settings.appLanguage, error.localizedDescription)
        }
    }

    func pauseTask(_ task: DownloadTask) async {
        await syncRPCPort()
        guard let gid = task.gid else { return }
        do {
            _ = try await aria2Service.pauseDownload(gid: gid)
            if let status = try? await aria2Service.getStatus(gid: gid) {
                let updated = merge(task: self.task(with: task.id) ?? task, with: status)
                update(updated)
            } else {
                mutate(id: task.id) { $0.status = .paused }
            }
        } catch {
            lastErrorMessage = L10n.format("pause_failed", language: settingsStore.settings.appLanguage, error.localizedDescription)
        }
    }

    func resumeTask(_ task: DownloadTask) async {
        await syncRPCPort()
        guard let gid = task.gid else { return }
        do {
            _ = try await aria2Service.resumeDownload(gid: gid)
            mutate(id: task.id) { $0.status = .downloading }
        } catch {
            lastErrorMessage = L10n.format("resume_failed", language: settingsStore.settings.appLanguage, error.localizedDescription)
        }
    }

    func deleteTask(_ task: DownloadTask, deleteFiles: Bool? = nil) async {
        await syncRPCPort()
        markTaskAsRecentlyDeleted(task)
        if let gid = task.gid {
            _ = try? await aria2Service.removeDownload(gid: gid)
            _ = try? await aria2Service.removeDownloadResult(gid: gid)
            if (try? await aria2Service.forceSaveSession()) == nil {
                lastErrorMessage = L10n.format(
                    "remove_remote_task_failed",
                    language: settingsStore.settings.appLanguage,
                    L10n.text("error_generic", language: settingsStore.settings.appLanguage)
                )
            }
        }

        if deleteFiles ?? settingsStore.settings.deleteFilesWhenRemoving {
            deleteTaskArtifacts(task)
        }

        tasks.removeAll { $0.id == task.id }
        persist()
    }

    func refreshTasks() async {
        let isRunning = await Aria2ProcessManager.shared.checkStatus()
        guard isRunning else { return }
        guard !isRefreshingTasks else { return }
        isRefreshingTasks = true
        defer { isRefreshingTasks = false }
        await syncRPCPort()
        pruneRecentlyDeletedMarkers()

        do {
            let gids = tasks.compactMap(\.gid)
            await MatrixDebugLogger.shared.log(
                event: "task.refresh.begin",
                metadata: [
                    "gidCount": String(gids.count),
                    "taskCount": String(tasks.count)
                ],
                level: .debug
            )
            let batch = try await aria2Service.getStatusesBatch(gids: gids, keys: summaryStatusKeys)
            let knownStatuses = batch.statuses
            await MatrixDebugLogger.shared.log(
                event: "task.refresh.statuses",
                metadata: [
                    "missingGIDCount": String(batch.missingGIDs.count),
                    "receivedStatusCount": String(knownStatuses.count)
                ],
                level: .debug
            )
            if !batch.missingGIDs.isEmpty {
                let beforeCount = tasks.count
                tasks.removeAll { task in
                    guard let gid = task.gid else { return false }
                    return batch.missingGIDs.contains(gid)
                }
                if tasks.count != beforeCount {
                    await MatrixDebugLogger.shared.log(
                        event: "task.refresh.removedMissingGIDs",
                        metadata: [
                            "removedCount": String(beforeCount - tasks.count),
                            "missingGIDs": batch.missingGIDs.joined(separator: ",")
                        ],
                        level: .info
                    )
                }
            }
            var totalDownloadSpeed: Int64 = 0
            var totalUploadSpeed: Int64 = 0
            var matchedTaskIDs = Set<UUID>()

            for status in knownStatuses {
                guard let index = tasks.firstIndex(where: { $0.gid == status.gid }) else { continue }
                let previous = tasks[index]
                let updated = merge(task: tasks[index], with: status)
                tasks[index] = updated
                matchedTaskIDs.insert(updated.id)
                totalDownloadSpeed += updated.speed
                totalUploadSpeed += updated.uploadSpeed

                if previous.status != .completed,
                   updated.status == .completed,
                   settingsStore.settings.enableNotifications {
                    await NotificationManager.notifyDownloadCompleted(task: updated)
                }

                if previous.status != .error,
                   updated.status == .error {
                    let reason = updated.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let reason, !reason.isEmpty {
                        lastErrorMessage = "\(updated.filename): \(reason)"
                    } else {
                        lastErrorMessage = "\(updated.filename): \(L10n.text("error_generic", language: settingsStore.settings.appLanguage))"
                    }
                }
            }

            if shouldPerformRemoteDiscovery() {
                let discoveryStatuses = try await fetchDiscoveryStatuses()
                for status in discoveryStatuses {
                    guard tasks.contains(where: { $0.gid == status.gid }) == false else { continue }
                    guard !isRecentlyDeleted(status: status) else { continue }
                    guard let recoveredTask = recoveredTask(from: status) else { continue }
                    tasks.insert(recoveredTask, at: 0)
                    matchedTaskIDs.insert(recoveredTask.id)
                    totalDownloadSpeed += recoveredTask.speed
                    totalUploadSpeed += recoveredTask.uploadSpeed
                }
                lastRemoteDiscoveryAt = .now
            }

            globalDownloadSpeed = totalDownloadSpeed
            globalUploadSpeed = totalUploadSpeed
            persist()
        } catch {
            await MatrixDebugLogger.shared.log(
                event: "task.refresh.failure",
                metadata: [
                    "error": error.localizedDescription
                ],
                level: .error
            )
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && (nsError.code == -1003 || nsError.code == -1004) {
                return
            }
            if Aria2RPCService.isTransientTransportError(error) {
                return
            }
            lastErrorMessage = L10n.format("refresh_tasks_failed", language: settingsStore.settings.appLanguage, error.localizedDescription)
        }
    }

    private func setupTimer() {
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.refreshTasks() }
            }
            .store(in: &cancellables)
    }

    private func shouldPerformRemoteDiscovery(now: Date = .now) -> Bool {
        guard let lastRemoteDiscoveryAt else { return true }
        return now.timeIntervalSince(lastRemoteDiscoveryAt) >= 15
    }

    private func fetchDiscoveryStatuses() async throws -> [Aria2Status] {
        async let active = aria2Service.getActiveDownloads(keys: discoveryStatusKeys)
        async let waiting = aria2Service.getWaitingDownloads(keys: discoveryStatusKeys)
        async let stopped = aria2Service.getStoppedDownloads(keys: discoveryStatusKeys)
        return try await active + waiting + stopped
    }

    private func merge(task: DownloadTask, with status: Aria2Status) -> DownloadTask {
        var updated = task
        let topLevelTotal = Int64(status.totalLength) ?? 0
        let topLevelCompleted = Int64(status.completedLength) ?? 0
        let fileTotal = status.files?.reduce(into: Int64(0)) { partialResult, file in
            partialResult += Int64(file.length) ?? 0
        } ?? 0
        let fileCompleted = status.files?.reduce(into: Int64(0)) { partialResult, file in
            partialResult += Int64(file.completedLength) ?? 0
        } ?? 0

        updated.totalSize = max(topLevelTotal, fileTotal)
        updated.downloadedSize = max(topLevelCompleted, fileCompleted)
        updated.speed = Int64(status.downloadSpeed) ?? 0
        updated.uploadSpeed = Int64(status.uploadSpeed ?? "0") ?? 0
        updated.connections = Int(status.connections) ?? 0
        updated.seeders = Int(status.numSeeders ?? "0") ?? 0
        updated.isSeeding = status.seeder == "true"
        updated.progress = updated.totalSize > 0 ? Double(updated.downloadedSize) / Double(updated.totalSize) : 0
        updated.errorMessage = status.errorMessage

        switch status.status {
        case "complete":
            updated.status = .completed
            updated.speed = 0
            updated.uploadSpeed = 0
            updated.connections = 0
            if updated.completedAt == nil {
                updated.completedAt = .now
            }
        case "error":
            updated.status = .error
            updated.speed = 0
            updated.uploadSpeed = 0
            updated.connections = 0
        case "paused":
            updated.status = .paused
            updated.speed = 0
            updated.uploadSpeed = 0
            updated.connections = 0
        case "active":
            updated.status = .downloading
        case "waiting":
            updated.status = .waiting
            updated.speed = 0
            updated.uploadSpeed = 0
            updated.connections = 0
        default:
            break
        }

        if task.kind.isBitTorrent,
           let torrentName = status.bittorrent?.info?.name,
           !torrentName.isEmpty {
            updated.filename = torrentName
        } else if let filePath = status.files?.first?.path, !filePath.isEmpty {
            updated.filename = URL(fileURLWithPath: filePath).lastPathComponent
        }
        if let dir = status.dir, !dir.isEmpty {
            updated.savePath = dir
        }

        return refreshFromFilesystem(updated)
    }

    private func matchIndex(for status: Aria2Status, excluding matchedTaskIDs: Set<UUID>) -> Int? {
        if let exactIndex = tasks.firstIndex(where: { $0.gid == status.gid }) {
            return exactIndex
        }

        let statusFilename = resolvedFilename(from: status)
        let statusSource = resolvedSource(from: status)

        return tasks.firstIndex { task in
            guard !matchedTaskIDs.contains(task.id) else { return false }
            guard task.status != .completed else { return false }

            if task.kind.isBitTorrent {
                let sameDirectory = normalizedPath(task.savePath) == normalizedPath(status.dir ?? "")
                let sameName = normalizedName(task.filename) == normalizedName(statusFilename)
                return sameDirectory && sameName
            }

            let sameDirectory = normalizedPath(task.savePath) == normalizedPath(status.dir ?? "")
            let sameName = normalizedName(task.filename) == normalizedName(statusFilename)
            if sameDirectory && sameName {
                return true
            }

            if let statusSource {
                return task.url == statusSource
            }

            return false
        }
    }

    private func resolvedFilename(from status: Aria2Status) -> String {
        if let torrentName = status.bittorrent?.info?.name, !torrentName.isEmpty {
            return torrentName
        }

        if let filePath = status.files?.first?.path, !filePath.isEmpty {
            return URL(fileURLWithPath: filePath).lastPathComponent
        }

        if let source = resolvedSource(from: status), let url = URL(string: source) {
            return url.lastPathComponent
        }

        return ""
    }

    private func resolvedSource(from status: Aria2Status) -> String? {
        status.files?
            .first?
            .uris?
            .first(where: { !$0.uri.isEmpty })?
            .uri
    }

    private func normalizedPath(_ value: String) -> String {
        NSString(string: value).standardizingPath
    }

    private func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func update(_ task: DownloadTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        persist()
    }

    private func mutate(id: UUID, _ mutate: (inout DownloadTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&tasks[index])
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: persistenceURL, options: .atomic)
    }

    private func refreshFromFilesystem(_ task: DownloadTask) -> DownloadTask {
        var updated = task
        let fileManager = FileManager.default
        let fileURL = task.fileURL

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return updated
        }

        let resourceValues = try? fileURL.resourceValues(forKeys: [
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ])
        let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)

        let logicalSize = Int64(resourceValues?.fileSize ?? 0)
        let fallbackLogicalSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let resolvedLogicalSize = max(logicalSize, fallbackLogicalSize)
        let allocatedSize = Int64(resourceValues?.totalFileAllocatedSize ?? resourceValues?.fileAllocatedSize ?? 0)
        let fallbackAllocatedSize = allocatedSizeOnDisk(for: fileURL)
        let resolvedAllocatedSize = max(allocatedSize, fallbackAllocatedSize)

        if updated.totalSize == 0, resolvedLogicalSize > 0 {
            updated.totalSize = resolvedLogicalSize
        }

        if resolvedAllocatedSize > updated.downloadedSize {
            updated.downloadedSize = min(resolvedAllocatedSize, updated.totalSize > 0 ? updated.totalSize : resolvedAllocatedSize)
        }

        if updated.status == .completed, resolvedLogicalSize > updated.downloadedSize {
            updated.downloadedSize = resolvedLogicalSize
        }
        if updated.totalSize > 0 {
            updated.progress = min(1, Double(updated.downloadedSize) / Double(updated.totalSize))
        }

        return updated
    }

    private func allocatedSizeOnDisk(for fileURL: URL) -> Int64 {
        var statBuffer = stat()
        guard lstat(fileURL.path, &statBuffer) == 0 else {
            return 0
        }
        return Int64(statBuffer.st_blocks) * 512
    }

    private func hasExistingTask(url: String, savePath: String, filename: String) -> Bool {
        tasks.contains { task in
            guard task.status != .completed else { return false }
            return task.url == url
                && normalizedPath(task.savePath) == normalizedPath(savePath)
                && normalizedName(task.filename) == normalizedName(filename)
        }
    }

    private func mergeRecoveredTask(_ task: DownloadTask, into tasks: inout [DownloadTask]) {
        guard let existingIndex = tasks.firstIndex(where: {
            taskIdentityKey(for: $0) == taskIdentityKey(for: task)
        }) else {
            tasks.append(task)
            return
        }

        let existing = tasks[existingIndex]
        tasks[existingIndex] = preferredRecoveredTask(between: existing, and: task)
    }

    private func preferredRecoveredTask(between lhs: DownloadTask, and rhs: DownloadTask) -> DownloadTask {
        let lhsScore = recoveryScore(for: lhs)
        let rhsScore = recoveryScore(for: rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? lhs : rhs
        }
        return lhs.createdAt >= rhs.createdAt ? lhs : rhs
    }

    private func recoveryScore(for task: DownloadTask) -> Int64 {
        var score = 0 as Int64
        score += max(task.totalSize, 0) * 2
        score += max(task.downloadedSize, 0)
        if task.progress > 0 {
            score += 1
        }
        if task.gid != nil {
            score += 1
        }
        return score
    }

    private func taskIdentityKey(for task: DownloadTask) -> String {
        [
            task.url,
            normalizedPath(task.savePath),
            normalizedName(task.filename)
        ].joined(separator: "|")
    }

    private func taskIdentityKey(for status: Aria2Status) -> String {
        [
            resolvedSource(from: status) ?? status.gid,
            normalizedPath(status.dir ?? settingsStore.settings.defaultDownloadPath),
            normalizedName(resolvedFilename(from: status).nilIfBlank ?? status.gid)
        ].joined(separator: "|")
    }

    private func markTaskAsRecentlyDeleted(_ task: DownloadTask) {
        let expiry = Date().addingTimeInterval(15)
        if let gid = task.gid {
            recentlyDeletedGIDs[gid] = expiry
        }
        recentlyDeletedIdentityKeys[taskIdentityKey(for: task)] = expiry
    }

    private func isRecentlyDeleted(status: Aria2Status) -> Bool {
        let now = Date()
        if let expiry = recentlyDeletedGIDs[status.gid], expiry > now {
            return true
        }
        if let expiry = recentlyDeletedIdentityKeys[taskIdentityKey(for: status)], expiry > now {
            return true
        }
        return false
    }

    private func pruneRecentlyDeletedMarkers() {
        let now = Date()
        recentlyDeletedGIDs = recentlyDeletedGIDs.filter { $0.value > now }
        recentlyDeletedIdentityKeys = recentlyDeletedIdentityKeys.filter { $0.value > now }
    }

    private func recoveredTask(from status: Aria2Status) -> DownloadTask? {
        let source = resolvedSource(from: status)
        let kind: TaskKind
        if let source, source.hasPrefix("magnet:") {
            kind = .magnet
        } else if status.bittorrent != nil {
            kind = .torrent
        } else if let source, source.lowercased().hasSuffix(".meta4") || source.lowercased().hasSuffix(".metalink") {
            kind = .metalink
        } else {
            kind = .direct
        }

        let resolvedFilename = resolvedFilename(from: status).nilIfBlank ?? status.gid
        let resolvedSavePath = status.dir?.nilIfBlank ?? settingsStore.settings.defaultDownloadPath
        let resolvedURL = source?.nilIfBlank ?? status.gid
        guard !resolvedFilename.isEmpty else { return nil }

        var task = DownloadTask(
            url: resolvedURL,
            filename: resolvedFilename,
            kind: kind,
            status: .waiting,
            savePath: resolvedSavePath,
            gid: status.gid
        )
        task = merge(task: task, with: status)
        return task
    }

    func task(with id: UUID) -> DownloadTask? {
        tasks.first { $0.id == id }
    }

    func pauseAllActiveTasks() async {
        for task in tasks where task.status == .downloading || task.status == .waiting {
            await pauseTask(task)
        }
    }

    func resumeAllPausedTasks() async {
        for task in tasks where task.status == .paused || task.status == .error {
            await resumeTask(task)
        }
    }

    func clearCompletedTasks() async {
        let completed = tasks.filter { $0.status == .completed }
        for task in completed {
            await deleteTask(task)
        }
    }

    func syncTaskSnapshotsBeforeTermination() async {
        await syncRPCPort()

        for task in tasks {
            guard let gid = task.gid else { continue }
            guard let status = try? await aria2Service.getStatus(gid: gid) else { continue }
            let updated = merge(task: self.task(with: task.id) ?? task, with: status)
            update(updated)
        }

        _ = try? await aria2Service.forceSaveSession()
    }

    func resetSession() async {
        await syncRPCPort()
        let existingTasks = tasks
        for task in existingTasks {
            if let gid = task.gid {
                _ = try? await aria2Service.removeDownload(gid: gid)
                _ = try? await aria2Service.removeDownloadResult(gid: gid)
            }
        }
        _ = try? await aria2Service.purgeDownloadResult()
        _ = try? await aria2Service.forceSaveSession()
        try? await Aria2ProcessManager.shared.clearSessionFile()
        tasks = []
        persist()
    }

    func openInFinder(_ task: DownloadTask) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: task.fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([task.fileURL])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: task.savePath)
        }
    }

    func openFile(_ task: DownloadTask) {
        guard FileManager.default.fileExists(atPath: task.fileURL.path) else { return }
        NSWorkspace.shared.open(task.fileURL)
    }

    func copySourceLink(_ task: DownloadTask) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(task.url, forType: .string)
    }

    private func deleteTaskArtifacts(_ task: DownloadTask) {
        let fileManager = FileManager.default
        let artifactURLs = [
            task.fileURL,
            task.fileURL.appendingPathExtension("aria2"),
        ]

        for url in artifactURLs where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func syncRPCPort() async {
        let currentPort = await Aria2ProcessManager.shared.getCurrentPort()
        let rpcPort = await aria2Service.getCurrentPort()
        guard rpcPort != currentPort else { return }
        await aria2Service.updatePort(currentPort)
    }

    private func ensureRPCReady() async throws {
        await syncRPCPort()
        for attempt in 0..<15 {
            do {
                _ = try await aria2Service.getVersion()
                await MatrixDebugLogger.shared.log(
                    event: "task.ensureRPCReady.success",
                    metadata: [
                        "attempt": String(attempt)
                    ],
                    level: .debug
                )
                return
            } catch {
                await MatrixDebugLogger.shared.log(
                    event: "task.ensureRPCReady.retry",
                    metadata: [
                        "attempt": String(attempt),
                        "error": error.localizedDescription
                    ],
                    level: .debug
                )
                if attempt == 14 { throw error }
                try await Task.sleep(for: .milliseconds(200))
            }
        }
    }
}

enum TaskFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case downloading = "下载中"
    case waiting = "等待中"
    case completed = "已完成"
    case stopped = "已停止"

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .all:
            return L10n.text("all", language: language)
        case .downloading:
            return L10n.text("downloading", language: language)
        case .waiting:
            return L10n.text("waiting", language: language)
        case .completed:
            return L10n.text("completed", language: language)
        case .stopped:
            return L10n.text("stopped", language: language)
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.stack.3d.up"
        case .downloading: return "arrow.down.circle"
        case .waiting: return "clock"
        case .completed: return "checkmark.circle"
        case .stopped: return "pause.circle"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
