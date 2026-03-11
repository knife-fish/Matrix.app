import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var taskListViewModel: TaskListViewModel
    @EnvironmentObject private var aria2Manager: Aria2Manager
    @Binding var isPresented: Bool

    @State private var draft = AppSettings()
    @State private var selectedTab: SettingsTab = .general
    @State private var connectionStatus: String?
    @State private var trackerRefreshInFlight = false
    @State private var configFileContent = ""

    private var language: AppLanguage {
        draft.appLanguage
    }

    private var accentTint: Color {
        Color(red: 0.15, green: 0.45, blue: 0.88)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    accentTint.opacity(0.08),
                    Color(NSColor.windowBackgroundColor),
                    Color(NSColor.controlBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 0) {
                sidebar
                Divider()
                VStack(spacing: 0) {
                    content
                    footer
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
            .padding(20)
        }
        .frame(width: 920, height: 680)
        .preferredColorScheme(settingsStore.settings.appearanceMode.colorScheme)
        .onAppear {
            draft = settingsStore.settings
        }
        .task {
            await loadConfigFile()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.down.right.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accentTint)
                        .frame(width: 38, height: 38)
                        .background(accentTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text("settings_title", language: language))
                            .font(.system(size: 18, weight: .semibold))
                        Text(selectedTab.displayName(language: language))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("sections", language: language))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(selectedTab == tab ? .white : .secondary)
                                .frame(width: 30, height: 30)
                                .background(
                                    selectedTab == tab
                                        ? AnyShapeStyle(accentTint.opacity(0.75))
                                        : AnyShapeStyle(Color.secondary.opacity(0.10)),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(tab.displayName(language: language))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(selectedTab == tab ? .primary : .primary)
                            }

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            selectedTab == tab
                                ? Color.accentColor.opacity(0.10)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                SettingsInlineMetric(
                    icon: aria2Manager.isRunning ? "bolt.fill" : "bolt.slash.fill",
                    value: aria2Manager.isRunning ? L10n.text("connected", language: language) : L10n.text("disconnected", language: language),
                    tint: aria2Manager.isRunning ? .green : .orange,
                    helpText: L10n.text("connection_status", language: language)
                )
                SettingsInlineMetric(
                    icon: "wave.3.right.circle.fill",
                    value: "\(draft.trackerListText.split(separator: "\n").count)",
                    tint: accentTint,
                    helpText: L10n.text("tracker_count", language: language)
                )
            }
        }
        .padding(24)
        .frame(width: 280, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.56), Color.white.opacity(0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch selectedTab {
                case .general:
                    settingsSection(title: L10n.text("basic", language: language), subtitle: L10n.text("settings_general_subtitle", language: language)) {
                        pathPickerRow
                        Stepper(L10n.format("default_threads", language: language, draft.defaultThreadCount), value: $draft.defaultThreadCount, in: 1...64)
                        Stepper(L10n.format("max_concurrent_tasks", language: language, draft.maxConcurrentTasks), value: $draft.maxConcurrentTasks, in: 1...10)
                        Toggle(L10n.text("auto_start_downloads", language: language), isOn: $draft.autoStartDownloads)
                        Toggle(L10n.text("notify_on_complete", language: language), isOn: $draft.enableNotifications)
                        Toggle(L10n.text("delete_files_on_remove", language: language), isOn: $draft.deleteFilesWhenRemoving)
                    }

                    settingsSection(title: L10n.text("interface", language: language), subtitle: L10n.text("settings_interface_subtitle", language: language)) {
                        Toggle(L10n.text("show_in_dock", language: language), isOn: $draft.showDockIcon)
                        Toggle(L10n.text("enable_menu_bar", language: language), isOn: $draft.showMenuBarExtra)
                        Toggle(L10n.text("show_menu_speed", language: language), isOn: $draft.showMenuBarSpeed)
                        Picker(L10n.text("appearance", language: language), selection: $draft.appearanceMode) {
                            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                                Text(mode.displayName(language: language)).tag(mode)
                            }
                        }
                        Picker(L10n.text("language", language: language), selection: $draft.appLanguage) {
                            ForEach(AppLanguage.allCases, id: \.self) { appLanguage in
                                Text(appLanguage.displayName).tag(appLanguage)
                            }
                        }
                    }

                case .download:
                    settingsSection(title: L10n.text("speed_limit", language: language), subtitle: L10n.text("settings_download_subtitle", language: language)) {
                        Stepper(L10n.format("download_limit", language: language, speedLabel(draft.downloadSpeedLimitKB)), value: $draft.downloadSpeedLimitKB, in: 0...1024_000, step: 256)
                        Stepper(L10n.format("upload_limit", language: language, speedLabel(draft.uploadSpeedLimitKB)), value: $draft.uploadSpeedLimitKB, in: 0...512_000, step: 128)
                    }

                case .bittorrent:
                    settingsSection(title: L10n.text("tracker", language: language), subtitle: L10n.text("settings_tracker_subtitle", language: language)) {
                        Toggle(L10n.text("auto_update_trackers", language: language), isOn: $draft.autoUpdateTrackerList)
                        TextField(L10n.text("tracker_source", language: language), text: $draft.trackerSourceURL)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text("tracker_list", language: language))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextEditor(text: $draft.trackerListText)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(minHeight: 180)
                                .padding(10)
                                .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        HStack {
                            Button(trackerRefreshInFlight ? L10n.text("refreshing", language: language) : L10n.text("refresh_trackers", language: language)) {
                                refreshTrackers()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(trackerRefreshInFlight)

                            if let updatedAt = draft.trackerListLastUpdatedAt {
                                Text(L10n.format("last_updated", language: language, formattedDate(updatedAt)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    settingsSection(title: L10n.text("bt_settings", language: language), subtitle: L10n.text("settings_bt_subtitle", language: language)) {
                        Toggle(L10n.text("keep_seeding", language: language), isOn: $draft.keepSeeding)
                        if draft.keepSeeding {
                            Stepper(L10n.format("seed_ratio", language: language, String(format: "%.1f", draft.seedRatio)), value: $draft.seedRatio, in: 0.1...10.0, step: 0.1)
                            Stepper(L10n.format("seed_time", language: language, seedTimeLabel), value: $draft.seedTimeMinutes, in: 0...1440, step: 10)
                        }
                        Toggle(L10n.text("save_magnet", language: language), isOn: $draft.saveMagnetAsTorrent)
                        Toggle(L10n.text("enable_dht", language: language), isOn: $draft.enableDHT)
                        Toggle(L10n.text("enable_pex", language: language), isOn: $draft.enablePeerExchange)
                        Toggle(L10n.text("enable_lpd", language: language), isOn: $draft.enableLocalPeerDiscovery)
                        Toggle(L10n.text("enable_upnp", language: language), isOn: $draft.enablePortMapping)
                        Stepper(L10n.format("bt_listen_port", language: language, draft.btListenPort), value: $draft.btListenPort, in: 1024...65535)
                        Stepper(L10n.format("dht_listen_port", language: language, draft.dhtListenPort), value: $draft.dhtListenPort, in: 1024...65535)
                        Stepper(L10n.format("bt_max_peers", language: language, draft.btMaxPeers), value: $draft.btMaxPeers, in: 10...500, step: 5)
                    }

                case .network:
                    settingsSection(title: L10n.text("network_settings", language: language), subtitle: L10n.text("settings_network_subtitle", language: language)) {
                        TextField(L10n.text("user_agent", language: language), text: $draft.userAgent)
                        Toggle(L10n.text("enable_proxy", language: language), isOn: $draft.proxyEnabled)
                        if draft.proxyEnabled {
                            TextField(L10n.text("proxy_host", language: language), text: $draft.proxyHost)
                            TextField(L10n.text("proxy_port", language: language), text: $draft.proxyPort)
                        }
                    }

                case .advanced:
                    settingsSection(title: L10n.text("runtime_status", language: language), subtitle: L10n.text("settings_runtime_subtitle", language: language)) {
                        LabeledContent(L10n.text("aria2_port", language: language), value: "\(aria2Manager.rpcPort)")
                        LabeledContent(L10n.text("connection_status", language: language), value: aria2Manager.isRunning ? L10n.text("connected", language: language) : L10n.text("disconnected", language: language))
                        LabeledContent(L10n.text("tracker_count", language: language), value: "\(draft.trackerListText.split(separator: "\n").count)")
                    }

                    settingsSection(title: L10n.text("engine", language: language), subtitle: L10n.text("settings_engine_subtitle", language: language)) {
                        HStack(alignment: .center, spacing: 12) {
                            Text(L10n.text("rpc_port_label", language: language))
                            Spacer()
                            TextField(
                                "",
                                text: Binding(
                                    get: { "\(draft.rpcListenPort)" },
                                    set: { newValue in
                                        let digits = newValue.filter(\.isNumber)
                                        guard !digits.isEmpty else { return }
                                        guard let parsed = Int(digits) else { return }
                                        draft.rpcListenPort = min(max(parsed, 1024), 65535)
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        }
                        Toggle(L10n.text("rpc_listen_all", language: language), isOn: $draft.rpcListenAll)
                        Picker(L10n.text("log_level", language: language), selection: $draft.logLevel) {
                            ForEach(Aria2LogLevel.allCases, id: \.self) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                        LabeledContent(L10n.text("config_path", language: language), value: awaitableConfigPathPlaceholder)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text("config_file", language: language))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextEditor(text: $configFileContent)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(minHeight: 220)
                                .padding(10)
                                .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    settingsSection(title: L10n.text("session_and_config", language: language), subtitle: L10n.text("settings_session_subtitle", language: language)) {
                        Button(L10n.text("export_settings", language: language)) {
                            exportSettings()
                        }
                        Button(L10n.text("import_settings", language: language)) {
                            importSettings()
                        }
                        Button(L10n.text("reset_session", language: language), role: .destructive) {
                            resetSession()
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 24)
            .frame(maxWidth: 620, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var footer: some View {
        HStack {
            Button(L10n.text("restore_defaults", language: language)) {
                draft = AppSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()

            Button(L10n.text("cancel", language: language)) {
                closeWindow()
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button(L10n.text("save_and_apply", language: language)) {
                saveAndApply()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.28))
    }

    private var pathPickerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(L10n.text("default_save_path", language: language))
                .frame(width: 140, alignment: .leading)
            TextField("", text: $draft.defaultDownloadPath)
            Button(L10n.text("choose", language: language)) {
                pickPath()
            }
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Color.white.opacity(0.30), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.60), lineWidth: 1)
        )
    }

    private func saveAndApply() {
        settingsStore.update { $0 = draft }

        Task {
            do {
                try await Aria2ProcessManager.shared.updateConfigFile(content: configFileContent)
                try await aria2Manager.restartAria2()
                await MainActor.run {
                    connectionStatus = L10n.text("applied_and_restarted", language: language)
                    closeWindow()
                }
            } catch {
                await MainActor.run {
                    connectionStatus = L10n.format("apply_failed", language: language, error.localizedDescription)
                }
            }
        }
    }

    private func pickPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            draft.defaultDownloadPath = panel.url?.path ?? draft.defaultDownloadPath
        }
    }

    private func speedLabel(_ value: Int) -> String {
        value == 0 ? L10n.text("unlimited", language: language) : "\(value) KB/s"
    }

    private func refreshTrackers() {
        trackerRefreshInFlight = true

        settingsStore.update { $0 = draft }

        Task {
            do {
                try await aria2Manager.refreshTrackersIfNeeded(force: true)
                await MainActor.run {
                    draft = settingsStore.settings
                    connectionStatus = L10n.text("trackers_updated", language: language)
                    trackerRefreshInFlight = false
                }
            } catch {
                await MainActor.run {
                    connectionStatus = L10n.format("trackers_update_failed", language: language, error.localizedDescription)
                    trackerRefreshInFlight = false
                }
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = appLocale(for: language)
        return formatter.string(from: date)
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "matrix-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try settingsStore.exportSettings(to: url)
            connectionStatus = L10n.text("settings_exported", language: language)
        } catch {
            connectionStatus = L10n.format("settings_export_failed", language: language, error.localizedDescription)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try settingsStore.importSettings(from: url)
            draft = settingsStore.settings
            connectionStatus = L10n.text("settings_imported", language: language)
        } catch {
            connectionStatus = L10n.format("settings_import_failed", language: language, error.localizedDescription)
        }
    }

    private func resetSession() {
        Task {
            await taskListViewModel.resetSession()
            await MainActor.run {
                connectionStatus = L10n.text("session_reset", language: language)
            }
        }
    }

    private func loadConfigFile() async {
        do {
            let isConfigured = await Aria2ProcessManager.shared.getConfigPath() != nil
            if !isConfigured {
                try await Aria2ProcessManager.shared.setupConfiguration()
            }
            let config = try await Aria2ProcessManager.shared.readConfigFile()
            await MainActor.run {
                configFileContent = config
            }
        } catch {
            await MainActor.run {
                connectionStatus = L10n.format("config_read_failed", language: language, error.localizedDescription)
            }
        }
    }

    private var seedTimeLabel: String {
        draft.seedTimeMinutes == 0
            ? L10n.text("seed_time_unlimited", language: language)
            : L10n.format("seed_time_minutes", language: language, draft.seedTimeMinutes)
    }

    private var awaitableConfigPathPlaceholder: String {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Matrix", isDirectory: true)
            .appendingPathComponent("aria2.conf").path) ?? "-"
    }

    private func closeWindow() {
        isPresented = false
        dismiss()
    }
}

private struct SettingsInlineMetric: View {
    let icon: String
    let value: String
    let tint: Color
    let helpText: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(tint)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.08), in: Capsule())
        .help(helpText)
    }
}

enum SettingsTab: String, CaseIterable {
    case general = "通用"
    case download = "下载"
    case bittorrent = "BitTorrent"
    case network = "网络"
    case advanced = "高级"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .download: return "arrow.down.circle"
        case .bittorrent: return "wave.3.right.circle"
        case .network: return "network"
        case .advanced: return "wrench.and.screwdriver"
        }
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .general:
            return L10n.text("general", language: language)
        case .download:
            return L10n.text("download_tab", language: language)
        case .bittorrent:
            return L10n.text("bittorrent", language: language)
        case .network:
            return L10n.text("network", language: language)
        case .advanced:
            return L10n.text("advanced", language: language)
        }
    }
}
