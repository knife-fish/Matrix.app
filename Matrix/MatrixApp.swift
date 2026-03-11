import SwiftUI
import Combine
import AppKit

extension Notification.Name {
    static let matrixOpenNewTask = Notification.Name("matrix.open-new-task")
    static let matrixWillTerminate = Notification.Name("matrix.will-terminate")
}

@main
struct MatrixApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var aria2Manager: Aria2Manager
    @StateObject private var taskListViewModel: TaskListViewModel
    @StateObject private var openCoordinator: AppOpenCoordinator
    @State private var menuBarInserted: Bool

    init() {
        let openCoordinator = AppOpenCoordinator()
        let settingsStore = SettingsStore()
        let aria2Manager = Aria2Manager(settingsStore: settingsStore)
        let taskListViewModel = TaskListViewModel(settingsStore: settingsStore)
        AppDelegate.sharedOpenCoordinator = openCoordinator

        _openCoordinator = StateObject(wrappedValue: openCoordinator)
        _settingsStore = StateObject(wrappedValue: settingsStore)
        _aria2Manager = StateObject(wrappedValue: aria2Manager)
        _taskListViewModel = StateObject(wrappedValue: taskListViewModel)
        _menuBarInserted = State(initialValue: settingsStore.settings.showMenuBarExtra)
    }

    var body: some Scene {
        mainWindowScene
        menuBarScene
        settingsScene
    }

    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(settingsStore.settings.showDockIcon ? .regular : .accessory)
    }

    private var language: AppLanguage {
        settingsStore.settings.appLanguage
    }

    private var mainWindowScene: some Scene {
        Window("Matrix", id: "main") {
            MainView()
                .environmentObject(openCoordinator)
                .environmentObject(settingsStore)
                .environmentObject(aria2Manager)
                .environmentObject(taskListViewModel)
                .task {
                    await NotificationManager.requestAuthorizationIfNeeded()
                    await aria2Manager.startAria2()
                    applyActivationPolicy()
                }
                .onChange(of: settingsStore.settings.showDockIcon) { _, _ in
                    applyActivationPolicy()
                }
                .onChange(of: settingsStore.settings.showMenuBarExtra) { _, newValue in
                    if menuBarInserted != newValue {
                        menuBarInserted = newValue
                    }
                }
                .onChange(of: menuBarInserted) { _, newValue in
                    if settingsStore.settings.showMenuBarExtra != newValue {
                        settingsStore.update { $0.showMenuBarExtra = newValue }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .matrixWillTerminate)) { _ in
                    Task { await taskListViewModel.syncTaskSnapshotsBeforeTermination() }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.text("new_task", language: language)) {
                    AppDelegate.shared?.showMainWindow()
                    NSApp.activate(ignoringOtherApps: true)
                    NotificationCenter.default.post(name: .matrixOpenNewTask, object: nil)
                }
                .keyboardShortcut("n")
            }

            CommandMenu(L10n.text("download", language: language)) {
                Button(L10n.text("pause_all", language: language)) {
                    Task { await taskListViewModel.pauseAllActiveTasks() }
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])

                Button(L10n.text("resume_all", language: language)) {
                    Task { await taskListViewModel.resumeAllPausedTasks() }
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])

                Button(L10n.text("clear_completed", language: language)) {
                    Task { await taskListViewModel.clearCompletedTasks() }
                }

                Divider()

                Button(L10n.text("reset_session", language: language)) {
                    Task { await taskListViewModel.resetSession() }
                }
            }
        }
    }

    private var menuBarScene: some Scene {
        MenuBarExtra(isInserted: $menuBarInserted) {
            MenuBarDownloadsView()
                .environmentObject(settingsStore)
                .environmentObject(aria2Manager)
                .environmentObject(taskListViewModel)
        } label: {
            MenuBarExtraLabel()
                .environmentObject(settingsStore)
                .environmentObject(taskListViewModel)
        }
        .menuBarExtraStyle(.window)
    }

    private var settingsScene: some Scene {
        Settings {
            SettingsView(isPresented: .constant(true))
                .environmentObject(openCoordinator)
                .environmentObject(settingsStore)
                .environmentObject(aria2Manager)
                .environmentObject(taskListViewModel)
                .frame(width: 860, height: 620)
        }
    }
}

@MainActor
final class Aria2Manager: ObservableObject {
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var rpcPort = 16800

    private let settingsStore: SettingsStore
    private var isStarting = false
    private var cancellables = Set<AnyCancellable>()

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        setupStatusMonitor()
    }

    func startAria2() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        if isRunning {
            return
        }

        do {
            try await startAria2WithRecovery()
        } catch Aria2ProcessError.executableNotFound {
            isRunning = false
            errorMessage = L10n.text("aria2_executable_not_found", language: settingsStore.settings.appLanguage)
        } catch {
            isRunning = false
            errorMessage = L10n.format("aria2_start_failed", language: settingsStore.settings.appLanguage, error.localizedDescription)
        }
    }

    func stopAria2() async {
        do {
            try await Aria2ProcessManager.shared.stop()
            isRunning = false
        } catch {
            errorMessage = L10n.format("aria2_stop_failed", language: settingsStore.settings.appLanguage, error.localizedDescription)
        }
    }

    func restartAria2() async throws {
        let preferredPort = settingsStore.settings.rpcListenPort
        try await Aria2ProcessManager.shared.restart(
            preferredRPCPort: preferredPort,
            rpcListenAll: settingsStore.settings.rpcListenAll,
            additionalArgs: try await startupArguments()
        )
        rpcPort = await Aria2ProcessManager.shared.getCurrentPort()
        try await waitForRPCReady(on: rpcPort)
        isRunning = true
        try await applySettings()
        errorMessage = nil
    }

    func applySettings() async throws {
        let settings = settingsStore.settings

        var options: [String: Any] = [
            "max-concurrent-downloads": String(settings.maxConcurrentTasks),
            "split": String(settings.defaultThreadCount),
            "max-connection-per-server": String(settings.defaultThreadCount),
            "continue": "true",
            "user-agent": settings.userAgent,
            "log-level": settings.logLevel.rawValue
        ]

        options["listen-port"] = String(settings.btListenPort)
        options["dht-listen-port"] = String(settings.dhtListenPort)
        options["bt-max-peers"] = String(settings.btMaxPeers)
        options["enable-dht"] = settings.enableDHT ? "true" : "false"
        options["enable-dht6"] = settings.enableDHT ? "true" : "false"
        options["enable-peer-exchange"] = settings.enablePeerExchange ? "true" : "false"
        options["bt-enable-lpd"] = settings.enableLocalPeerDiscovery ? "true" : "false"
        options["bt-save-metadata"] = settings.saveMagnetAsTorrent ? "true" : "false"

        if settings.downloadSpeedLimitKB > 0 {
            options["max-overall-download-limit"] = "\(settings.downloadSpeedLimitKB)K"
        }
        if settings.uploadSpeedLimitKB > 0 {
            options["max-overall-upload-limit"] = "\(settings.uploadSpeedLimitKB)K"
        }
        let trackers = TrackerListService.shared.sanitizeTrackerList(settings.trackerListText)
        if !trackers.isEmpty {
            options["bt-tracker"] = trackers.joined(separator: ",")
        }
        if settings.keepSeeding {
            options["seed-ratio"] = String(settings.seedRatio)
            if settings.seedTimeMinutes > 0 {
                options["seed-time"] = String(settings.seedTimeMinutes)
            }
        } else {
            options["seed-ratio"] = "0.0"
            options["seed-time"] = "0"
        }
        if settings.proxyEnabled, !settings.proxyHost.isEmpty {
            options["all-proxy"] = settings.proxyHost
            if !settings.proxyPort.isEmpty {
                options["all-proxy-port"] = settings.proxyPort
            }
        }

        try await Aria2RPCService.shared.changeGlobalOption(options: options)
    }

    func refreshTrackersIfNeeded(force: Bool = false) async throws {
        let settings = settingsStore.settings
        guard settings.autoUpdateTrackerList || force else { return }

        if !force, let lastUpdated = settings.trackerListLastUpdatedAt,
           Date.now.timeIntervalSince(lastUpdated) < 24 * 60 * 60 {
            return
        }

        let listText = try await TrackerListService.shared.fetchTrackerList(from: settings.trackerSourceURL)
        settingsStore.update {
            $0.trackerListText = listText
            $0.trackerListLastUpdatedAt = .now
        }
    }

    private func waitForRPCReady(on port: Int) async throws {
        await Aria2RPCService.shared.updatePort(port)

        for attempt in 0..<20 {
            do {
                _ = try await Aria2RPCService.shared.getVersion()
                return
            } catch {
                if attempt == 19 { throw error }
                try await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func setupStatusMonitor() {
        Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.refreshConnectionStatus() }
            }
            .store(in: &cancellables)
    }

    private func refreshConnectionStatus() async {
        guard !isStarting else { return }
        let status = await Aria2ProcessManager.shared.checkStatus()
        if isRunning != status {
            isRunning = status
        }
        if !status {
            rpcPort = settingsStore.settings.rpcListenPort
        }
    }

    private func startAria2WithRecovery() async throws {
        do {
            try await startAria2Once()
        } catch {
            let hadResidualProcess = await Aria2ProcessManager.shared.checkStatus()
            if hadResidualProcess {
                await Aria2ProcessManager.shared.stopIfRunning()
                try await Task.sleep(for: .milliseconds(400))
                try await startAria2Once(forceFresh: true)
                return
            }
            throw error
        }
    }

    private func startAria2Once(forceFresh: Bool = false) async throws {
        let port = try await Aria2ProcessManager.shared.start(
            preferredRPCPort: settingsStore.settings.rpcListenPort,
            rpcListenAll: settingsStore.settings.rpcListenAll,
            additionalArgs: try await startupArguments(),
            forceFresh: forceFresh
        )
        rpcPort = port
        await Aria2RPCService.shared.updatePort(port)
        try await waitForRPCReady(on: port)
        isRunning = await Aria2ProcessManager.shared.checkStatus()
        try? await refreshTrackersIfNeeded()
        try await applySettings()
        errorMessage = nil
    }

    private func startupArguments() async throws -> [String] {
        let settings = settingsStore.settings
        let runtimePaths = try await Aria2ProcessManager.shared.getRuntimePaths()
        let trackers = TrackerListService.shared.sanitizeTrackerList(settings.trackerListText)

        var args: [String] = [
            "--save-session=\(runtimePaths.sessionURL.path)",
            "--input-file=\(runtimePaths.sessionURL.path)",
            "--allow-overwrite=false",
            "--auto-file-renaming=true",
            "--bt-force-encryption=false",
            "--bt-load-saved-metadata=true",
            "--bt-save-metadata=\(settings.saveMagnetAsTorrent ? "true" : "false")",
            "--continue=true",
            "--dht-file-path=\(runtimePaths.dhtURL.path)",
            "--dht-file-path6=\(runtimePaths.dht6URL.path)",
            "--dht-listen-port=\(settings.dhtListenPort)",
            "--dir=\(settings.defaultDownloadPath)",
            "--follow-metalink=true",
            "--follow-torrent=true",
            "--listen-port=\(settings.btListenPort)",
            "--max-concurrent-downloads=\(settings.maxConcurrentTasks)",
            "--max-connection-per-server=\(settings.defaultThreadCount)",
            "--max-download-limit=0",
            "--max-overall-download-limit=\(settings.downloadSpeedLimitKB > 0 ? "\(settings.downloadSpeedLimitKB)K" : "0")",
            "--max-overall-upload-limit=\(settings.uploadSpeedLimitKB > 0 ? "\(settings.uploadSpeedLimitKB)K" : "0")",
            "--pause-metadata=false",
            "--pause=\(settings.autoStartDownloads ? "false" : "true")",
            "--split=\(settings.defaultThreadCount)",
            "--user-agent=\(settings.userAgent)",
            "--enable-dht=\(settings.enableDHT ? "true" : "false")",
            "--enable-dht6=\(settings.enableDHT ? "true" : "false")",
            "--enable-peer-exchange=\(settings.enablePeerExchange ? "true" : "false")",
            "--bt-enable-lpd=\(settings.enableLocalPeerDiscovery ? "true" : "false")",
            "--bt-max-peers=\(settings.btMaxPeers)"
        ]

        if !trackers.isEmpty {
            args.append("--bt-tracker=\(trackers.joined(separator: ","))")
        }

        if settings.keepSeeding {
            args.append("--seed-ratio=\(settings.seedRatio)")
            if settings.seedTimeMinutes > 0 {
                args.append("--seed-time=\(settings.seedTimeMinutes)")
            } else {
                args.append("--seed-time=0")
            }
        } else {
            args.append("--seed-ratio=0.0")
            args.append("--seed-time=0")
        }

        return args
    }
}

struct MenuBarExtraLabel: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var viewModel: TaskListViewModel

    var body: some View {
        Image(nsImage: statusBarImage)
            .renderingMode(.template)
    }

    private func compactSpeed(_ bytesPerSecond: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytesPerSecond, countStyle: .binary) + "/s"
    }

    private var statusBarImage: NSImage {
        let showsSpeed = settingsStore.settings.showMenuBarSpeed
        let downText = "↓\(compactSpeed(viewModel.globalDownloadSpeed))"
        let upText = "↑\(compactSpeed(viewModel.globalUploadSpeed))"
        let font = NSFont.monospacedSystemFont(ofSize: 8, weight: .medium)
        let textColor = NSColor.labelColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]

        let downSize = (downText as NSString).size(withAttributes: attributes)
        let upSize = (upText as NSString).size(withAttributes: attributes)
        let textWidth = ceil(max(downSize.width, upSize.width))
        let textHeight = ceil(max(downSize.height, upSize.height))
        let iconWidth: CGFloat = 12
        let spacing: CGFloat = showsSpeed ? 4 : 0
        let canvasWidth = showsSpeed ? iconWidth + spacing + textWidth : iconWidth
        let canvasHeight: CGFloat = 18
        let lineSpacing: CGFloat = -1
        let stackedTextHeight = textHeight * 2 + lineSpacing
        let textOriginY = floor((canvasHeight - stackedTextHeight) / 2)

        let image = NSImage(size: NSSize(width: canvasWidth, height: canvasHeight))
        image.isTemplate = true
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high

        drawStatusBarMonogram(
            in: CGRect(x: 0, y: (canvasHeight - iconWidth) / 2, width: iconWidth, height: iconWidth),
            color: textColor
        )

        if showsSpeed {
            let textX = iconWidth + spacing
            (upText as NSString).draw(
                at: CGPoint(x: textX, y: textOriginY + textHeight + lineSpacing),
                withAttributes: attributes
            )
            (downText as NSString).draw(
                at: CGPoint(x: textX, y: textOriginY),
                withAttributes: attributes
            )
        }

        return image
    }

    private func drawStatusBarMonogram(in rect: CGRect, color: NSColor) {
        let outer = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22)
        outer.lineWidth = max(1, rect.width * 0.1)
        color.setStroke()
        outer.stroke()

        let path = NSBezierPath()
        path.lineWidth = max(1.2, rect.width * 0.12)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.22))
        path.line(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.78))
        path.line(to: CGPoint(x: rect.minX + rect.width * 0.5, y: rect.minY + rect.height * 0.42))
        path.line(to: CGPoint(x: rect.minX + rect.width * 0.8, y: rect.minY + rect.height * 0.78))
        path.line(to: CGPoint(x: rect.minX + rect.width * 0.8, y: rect.minY + rect.height * 0.22))
        path.stroke()
    }
}

struct MenuBarDownloadsView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var aria2Manager: Aria2Manager
    @EnvironmentObject private var viewModel: TaskListViewModel

    private var language: AppLanguage {
        settingsStore.settings.appLanguage
    }

    private var accentTint: Color {
        Color(red: 0.16, green: 0.47, blue: 0.94)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("app_name", language: language))
                        .font(.system(size: 20, weight: .semibold))
                    HStack(spacing: 8) {
                        Circle()
                            .fill(aria2Manager.isRunning ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(aria2Manager.isRunning ? L10n.text("connected", language: language) : L10n.text("disconnected", language: language))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(L10n.text("show_main_window", language: language)) {
                    AppDelegate.shared?.showMainWindow()
                    if NSApp.keyWindow == nil {
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            HStack(spacing: 10) {
                compactMetric(value: speedText(viewModel.globalDownloadSpeed), symbol: "arrow.down.circle.fill", tint: .blue)
                compactMetric(value: speedText(viewModel.globalUploadSpeed), symbol: "arrow.up.circle.fill", tint: .green)
                compactMetric(value: "\(viewModel.tasks.filter { $0.status == .downloading }.count)", symbol: "bolt.fill", tint: .orange)
                compactMetric(value: "\(viewModel.tasks.filter { $0.status == .waiting }.count)", symbol: "clock.fill", tint: .secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 8) {
                    quickAction(L10n.text("new_task", language: language), systemImage: "plus", tint: accentTint) {
                        AppDelegate.shared?.showMainWindow()
                        if NSApp.keyWindow == nil {
                            openWindow(id: "main")
                        }
                        NotificationCenter.default.post(name: .matrixOpenNewTask, object: nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    quickAction(L10n.text("pause_all", language: language), systemImage: "pause.fill", tint: .orange) {
                        Task { await viewModel.pauseAllActiveTasks() }
                    }
                    quickAction(L10n.text("resume_all", language: language), systemImage: "play.fill", tint: .green) {
                        Task { await viewModel.resumeAllPausedTasks() }
                    }
                    quickAction(L10n.text("clear_completed", language: language), systemImage: "trash", tint: .red) {
                        Task { await viewModel.clearCompletedTasks() }
                    }
                    quickAction(settingsStore.settings.showDockIcon ? L10n.text("hide_dock_icon", language: language) : L10n.text("show_dock_icon", language: language), systemImage: "dock.rectangle", tint: .secondary) {
                        settingsStore.update { $0.showDockIcon.toggle() }
                    }
                    quickAction(L10n.text("quit_app", language: language), systemImage: "power", tint: .red) {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(
            LinearGradient(
                colors: [accentTint.opacity(0.08), Color(NSColor.windowBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func compactMetric(value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint == .secondary ? .secondary : tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.26), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.58), lineWidth: 1)
        )
    }

    private func quickAction(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint == .secondary ? .secondary : tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(title)
                    .font(.system(size: 13, weight: .medium))

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.white.opacity(0.26), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.58), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func speedText(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary) + "/s"
    }
}
