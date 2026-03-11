import SwiftUI

struct MainView: View {
    @EnvironmentObject private var openCoordinator: AppOpenCoordinator
    @EnvironmentObject private var aria2Manager: Aria2Manager
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var viewModel: TaskListViewModel
    @Environment(\.openSettings) private var openSettings

    @State private var selectedFilter: TaskFilter = .all
    @State private var selectedTasks = Set<UUID>()
    @State private var showingNewTaskSheet = false
    @State private var selectedTask: DownloadTask?

    private var language: AppLanguage {
        settingsStore.settings.appLanguage
    }

    private var accentTint: Color {
        Color(red: 0.16, green: 0.47, blue: 0.94)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedFilter: $selectedFilter,
                language: language,
                tasks: viewModel.tasks,
                onOpenSettings: { openSettings() }
            )
            .frame(minWidth: 220, idealWidth: 240)
        } detail: {
            TaskListView(
                viewModel: viewModel,
                selectedFilter: selectedFilter,
                selectedTasks: $selectedTasks,
                showingNewTaskSheet: $showingNewTaskSheet,
                onTaskSelected: { task in
                    selectedTask = task
                }
            )
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(settingsStore.settings.appearanceMode.colorScheme)
        .tint(accentTint)
        .background(
            LinearGradient(
                colors: [
                    accentTint.opacity(0.14),
                    Color(NSColor.windowBackgroundColor),
                    Color(NSColor.controlBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .background(MainWindowTouchBarBridge(viewModel: viewModel, language: language).frame(width: 0, height: 0))
        .sheet(isPresented: $showingNewTaskSheet) {
            NewTaskView(isPresented: $showingNewTaskSheet)
                .environmentObject(settingsStore)
                .environmentObject(viewModel)
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task)
                .environmentObject(settingsStore)
                .environmentObject(viewModel)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button(L10n.text("pause_all", language: language)) {
                        Task { await viewModel.pauseAllActiveTasks() }
                    }
                    Button(L10n.text("resume_all", language: language)) {
                        Task { await viewModel.resumeAllPausedTasks() }
                    }
                    Button(L10n.text("clear_completed", language: language)) {
                        Task { await viewModel.clearCompletedTasks() }
                    }
                } label: {
                    toolbarLabel(title: L10n.text("batch_actions", language: language), symbol: "ellipsis.circle")
                }
                .help(L10n.text("batch_actions", language: language))

                Button(action: { showingNewTaskSheet = true }) {
                    toolbarLabel(title: L10n.text("new_task", language: language), symbol: "plus")
                }
                .help(L10n.text("new_task", language: language))

                if aria2Manager.isRunning {
                    Button(action: { }) {
                        toolbarLabel(title: L10n.text("aria2_online", language: language), symbol: "bolt.horizontal.circle.fill", tint: .green)
                    }
                    .help(L10n.text("aria2_online", language: language))
                } else {
                    Button {
                        Task { await aria2Manager.startAria2() }
                    }
                    label: {
                        toolbarLabel(title: L10n.text("reconnect_aria2", language: language), symbol: "arrow.clockwise.circle")
                    }
                    .help(L10n.text("reconnect_aria2", language: language))
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let errorMessage = aria2Manager.errorMessage ?? viewModel.lastErrorMessage {
                InlineMessageBar(text: errorMessage)
                    .padding()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .matrixOpenNewTask)) { _ in
            showingNewTaskSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .matrixImportURLs)) { notification in
            guard let urls = notification.object as? [URL] else { return }
            handleImportedURLs(urls)
        }
    }

    private func handleImportedURLs(_ urls: [URL]) {
        let savePath = settingsStore.settings.defaultDownloadPath
        for url in urls {
            if url.isFileURL {
                let ext = url.pathExtension.lowercased()
                Task {
                    if ext == "torrent" {
                        await viewModel.addTorrentFile(fileURL: url, savePath: savePath)
                    } else if ext == "metalink" || ext == "meta4" {
                        await viewModel.addMetalinkFile(fileURL: url, savePath: savePath)
                    }
                }
            } else {
                Task {
                    await viewModel.addURLTasks(
                        urls: [url.absoluteString],
                        savePath: savePath,
                        filename: nil,
                        threadCount: settingsStore.settings.defaultThreadCount
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func toolbarLabel(title: String, symbol: String, tint: Color? = nil) -> some View {
        Label(title, systemImage: symbol)
            .foregroundStyle(tint ?? .primary)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
    }
}

struct InlineMessageBar: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: 520)
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}

struct StatusBarView: View {
    @ObservedObject var viewModel: TaskListViewModel
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.blue)
                Text(formatSpeed(viewModel.globalDownloadSpeed))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.08), in: Capsule())

            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle")
                    .foregroundColor(.green)
                Text(formatSpeed(viewModel.globalUploadSpeed))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.08), in: Capsule())

            Spacer()

            Text(L10n.format("tasks_count", language: language, viewModel.filteredTasks.count, viewModel.tasks.count))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial)
    }

    private func formatSpeed(_ bytesPerSecond: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytesPerSecond, countStyle: .binary) + "/s"
    }
}
