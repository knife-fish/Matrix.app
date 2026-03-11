import SwiftUI
import UniformTypeIdentifiers

struct TaskListView: View {
    @ObservedObject var viewModel: TaskListViewModel
    let selectedFilter: TaskFilter
    @Binding var selectedTasks: Set<UUID>
    @Binding var showingNewTaskSheet: Bool
    var onTaskSelected: (DownloadTask) -> Void
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var searchText = ""
    @State private var pendingDeleteTask: DownloadTask?
    @State private var deleteFiles = false

    private var language: AppLanguage {
        settingsStore.settings.appLanguage
    }

    private var totalDownloadSpeed: String {
        ByteCountFormatter.string(fromByteCount: viewModel.globalDownloadSpeed, countStyle: .binary) + "/s"
    }

    private var totalUploadSpeed: String {
        ByteCountFormatter.string(fromByteCount: viewModel.globalUploadSpeed, countStyle: .binary) + "/s"
    }

    private var completedCount: Int {
        viewModel.tasks.filter { $0.status == .completed }.count
    }

    private var activeCount: Int {
        viewModel.tasks.filter { $0.status == .downloading || $0.status == .waiting }.count
    }

    var filteredTasks: [DownloadTask] {
        let baseTasks: [DownloadTask]
        switch selectedFilter {
        case .all:
            baseTasks = viewModel.tasks
        case .downloading:
            baseTasks = viewModel.tasks.filter { $0.status == .downloading }
        case .waiting:
            baseTasks = viewModel.tasks.filter { $0.status == .waiting }
        case .completed:
            baseTasks = viewModel.tasks.filter { $0.status == .completed }
        case .stopped:
            baseTasks = viewModel.tasks.filter { $0.status == .paused || $0.status == .error }
        }

        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return baseTasks }
        return baseTasks.filter {
            $0.filename.localizedCaseInsensitiveContains(keyword) ||
            $0.url.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if filteredTasks.isEmpty {
                EmptyStateView(filter: selectedFilter, language: language) {
                    showingNewTaskSheet = true
                }
            } else {
                List(filteredTasks, selection: $selectedTasks) { task in
                    TaskItemView(
                        task: task,
                        isSelected: selectedTasks.contains(task.id),
                        onSelect: {
                            onTaskSelected(task)
                        },
                        onPauseResume: {
                            Task {
                                if task.status == .downloading {
                                    await viewModel.pauseTask(task)
                                } else if task.status == .paused || task.status == .error {
                                    await viewModel.resumeTask(task)
                                }
                            }
                        },
                        onDeleteRequest: {
                            prepareDelete(task)
                        }
                    )
                    .tag(task.id)
                    .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .contextMenu {
                        if task.status == .completed {
                            Button(L10n.text("open_file", language: language)) {
                                viewModel.openFile(task)
                            }
                        }

                        Button(L10n.text("show_in_finder", language: language)) {
                            viewModel.openInFinder(task)
                        }

                        Button(L10n.text("copy_source_link", language: language)) {
                            viewModel.copySourceLink(task)
                        }

                        Divider()

                        if task.status == .downloading || task.status == .waiting {
                            Button(L10n.text("pause", language: language)) {
                                Task { await viewModel.pauseTask(task) }
                            }
                        } else if task.status == .paused || task.status == .error {
                            Button(L10n.text("resume", language: language)) {
                                Task { await viewModel.resumeTask(task) }
                            }
                        }

                        Button(L10n.text("delete", language: language), role: .destructive) {
                            prepareDelete(task)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 92)
            }

            Divider()

            StatusBarView(viewModel: viewModel, language: language)
        }
        .navigationTitle(selectedFilter.displayName(language: language))
        .onDrop(of: [.fileURL, .url, .plainText], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .sheet(item: $pendingDeleteTask) { task in
            DeleteTaskConfirmationSheet(
                task: task,
                language: language,
                deleteFiles: $deleteFiles,
                onCancel: {
                    pendingDeleteTask = nil
                },
                onConfirm: {
                    settingsStore.update { $0.deleteFilesWhenRemoving = deleteFiles }
                    let taskToDelete = task
                    pendingDeleteTask = nil
                    Task {
                        await viewModel.deleteTask(taskToDelete, deleteFiles: deleteFiles)
                    }
                }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedFilter.displayName(language: language))
                        .font(.system(size: 28, weight: .semibold))

                    Text(headerSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingNewTaskSheet = true
                } label: {
                    Label(L10n.text("new_task", language: language), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            HStack(spacing: 12) {
                DashboardMetricCard(
                    title: L10n.text("downloading", language: language),
                    value: totalDownloadSpeed,
                    detail: "\(activeCount)",
                    tint: .blue,
                    icon: "arrow.down.circle.fill"
                )
                DashboardMetricCard(
                    title: L10n.text("completed", language: language),
                    value: "\(completedCount)",
                    detail: "\(viewModel.tasks.count)",
                    tint: .green,
                    icon: "checkmark.circle.fill"
                )
                DashboardMetricCard(
                    title: L10n.text("upload", language: language),
                    value: totalUploadSpeed,
                    detail: "\(filteredTasks.count)",
                    tint: .orange,
                    icon: "arrow.up.circle.fill"
                )
            }

            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(L10n.text("search_tasks", language: language), text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.24), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var headerSubtitle: String {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.format("count_items", language: language, filteredTasks.count)
        }
        return L10n.format("count_results", language: language, filteredTasks.count)
    }

    private func prepareDelete(_ task: DownloadTask) {
        deleteFiles = settingsStore.settings.deleteFilesWhenRemoving
        pendingDeleteTask = task
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task {
                        if url.pathExtension.lowercased() == "torrent" {
                            await viewModel.addTorrentFile(fileURL: url, savePath: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "")
                        } else {
                            await viewModel.addMetalinkFile(fileURL: url, savePath: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "")
                        }
                    }
                }
                handled = true
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        Task {
                            await viewModel.addURLTasks(
                                urls: [url.absoluteString],
                                savePath: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "",
                                filename: nil,
                                threadCount: 16
                            )
                        }
                    }
                }
                handled = true
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    if let text = item as? String {
                        Task {
                            await viewModel.addURLTasks(
                                urls: text.components(separatedBy: .newlines).filter { !$0.isEmpty },
                                savePath: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "",
                                filename: nil,
                                threadCount: 16
                            )
                        }
                    }
                }
                handled = true
            }
        }

        return handled
    }
}

private struct DeleteTaskConfirmationSheet: View {
    let task: DownloadTask
    let language: AppLanguage
    @Binding var deleteFiles: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("delete_task", language: language))
                .font(.headline)

            Text(L10n.format("confirm_delete_task", language: language, task.filename))
                .font(.body)

            Toggle(L10n.text("delete_with_files", language: language), isOn: $deleteFiles)
                .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button(L10n.text("cancel", language: language)) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.text("delete", language: language), role: .destructive) {
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

struct EmptyStateView: View {
    let filter: TaskFilter
    let language: AppLanguage
    let onAddTask: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: filter == .all ? "arrow.down.circle" : filter.icon)
                .font(.system(size: 48))
                .foregroundColor(.accentColor.opacity(0.85))
                .padding(20)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            Text(emptyStateTitle)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            Text(emptyStateMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if filter == .all {
                Button(action: onAddTask) {
                    Label(L10n.text("new_task", language: language), systemImage: "plus")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.08), Color(NSColor.controlBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var emptyStateTitle: String {
        switch filter {
        case .all:
            return L10n.text("empty_title_all", language: language)
        case .downloading:
            return L10n.text("empty_title_downloading", language: language)
        case .waiting:
            return L10n.text("empty_title_waiting", language: language)
        case .completed:
            return L10n.text("empty_title_completed", language: language)
        case .stopped:
            return L10n.text("empty_title_stopped", language: language)
        }
    }

    private var emptyStateMessage: String {
        switch filter {
        case .all:
            return L10n.text("empty_msg_all", language: language)
        case .downloading:
            return L10n.text("empty_msg_downloading", language: language)
        case .waiting:
            return L10n.text("empty_msg_waiting", language: language)
        case .completed:
            return L10n.text("empty_msg_completed", language: language)
        case .stopped:
            return L10n.text("empty_msg_stopped", language: language)
        }
    }
}

private struct DashboardMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.30), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.60), lineWidth: 1)
        )
    }
}
