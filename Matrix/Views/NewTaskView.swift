import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum NewTaskSource: String, CaseIterable, Identifiable {
    case link
    case torrent
    case metalink

    var id: String { String(describing: self) }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .link:
            return L10n.text("new_task_source_link", language: language)
        case .torrent:
            return L10n.text("new_task_source_torrent", language: language)
        case .metalink:
            return L10n.text("new_task_source_metalink", language: language)
        }
    }

    var icon: String {
        switch self {
        case .link:
            return "link"
        case .torrent:
            return "wave.3.right.circle.fill"
        case .metalink:
            return "tray.and.arrow.down.fill"
        }
    }
}

struct NewTaskView: View {
    @EnvironmentObject private var viewModel: TaskListViewModel
    @EnvironmentObject private var settingsStore: SettingsStore
    @Binding var isPresented: Bool

    @State private var source: NewTaskSource = .link
    @State private var downloadURL = ""
    @State private var selectedFileURL: URL?
    @State private var savePath = ""
    @State private var fileName = ""
    @State private var showingAdvancedOptions = false
    @State private var threadCount = 16
    @State private var torrentPreview: TorrentPreview?
    @State private var selectedTorrentFiles = Set<Int>()
    @State private var isLoadingTorrentPreview = false
    @State private var torrentPreviewError: String?

    private var language: AppLanguage {
        settingsStore.settings.appLanguage
    }

    private var accentTint: Color {
        Color(red: 0.16, green: 0.47, blue: 0.94)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .frame(width: 700, height: dialogHeight)
        .background(
            LinearGradient(
                colors: [accentTint.opacity(0.12), Color(NSColor.windowBackgroundColor), Color(NSColor.controlBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            savePath = settingsStore.settings.defaultDownloadPath
            threadCount = settingsStore.settings.defaultThreadCount
        }
        .onChange(of: source) { _, newValue in
            if let selectedFileURL, !isSourceFileAllowed(selectedFileURL, for: newValue) {
                self.selectedFileURL = nil
            }
            if newValue != .torrent {
                torrentPreview = nil
                selectedTorrentFiles = []
                torrentPreviewError = nil
                isLoadingTorrentPreview = false
            } else if let selectedFileURL {
                Task { await loadTorrentPreview(from: selectedFileURL) }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("new_task", language: language))
                    .font(.system(size: 26, weight: .semibold))
                Text(sourceTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $source) {
                ForEach(NewTaskSource.allCases) { item in
                    Label(item.displayName(language: language), systemImage: item.icon)
                        .tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 340)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                contentCard(title: sourceTitle) {
                    sourceSection
                }

                contentCard(title: L10n.text("save_location", language: language)) {
                    savePathSection
                }

                if showingAdvancedOptions {
                    contentCard(title: L10n.text("advanced_options", language: language)) {
                        advancedOptionsSection
                    }
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        switch source {
        case .link:
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $downloadURL)
                    .font(.system(size: 13))
                    .frame(height: 170)
                    .padding(10)
                    .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(L10n.text("source_hint_links", language: language))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .torrent:
            VStack(alignment: .leading, spacing: 10) {
                filePickerHeader

                Text(L10n.text("source_hint_torrent", language: language))
                    .font(.caption)
                    .foregroundColor(.secondary)

                torrentPreviewSection
            }
        case .metalink:
            VStack(alignment: .leading, spacing: 10) {
                filePickerHeader

                Text(L10n.text("source_hint_metalink", language: language))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var filePickerHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: source.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accentTint)
                .frame(width: 42, height: 42)
                .background(accentTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(selectedFileURL?.lastPathComponent ?? L10n.text("no_file_selected", language: language))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(selectedFileURL?.path ?? (source == .torrent ? L10n.text("source_file_torrent", language: language) : L10n.text("source_file_metalink", language: language)))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(L10n.text("choose_file", language: language)) {
                pickSourceFile()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }

    @ViewBuilder
    private var torrentPreviewSection: some View {
        if isLoadingTorrentPreview {
            ProgressView(L10n.text("loading_torrent_contents", language: language))
                .controlSize(.regular)
                .padding(.vertical, 8)
        } else if let torrentPreview {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(torrentPreview.name)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(
                            L10n.format(
                                "torrent_preview_summary",
                                language: language,
                                torrentPreview.files.count,
                                ByteCountFormatter.string(
                                    fromByteCount: torrentPreview.files.reduce(0) { $0 + $1.length },
                                    countStyle: .file
                                ),
                                torrentPreview.trackers.count
                            )
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button(L10n.text("select_all", language: language)) {
                            selectedTorrentFiles = Set(torrentPreview.files.map(\.index))
                        }
                        .buttonStyle(.bordered)

                        Button(L10n.text("deselect_all", language: language)) {
                            selectedTorrentFiles = []
                        }
                        .buttonStyle(.bordered)
                    }
                }

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(torrentPreview.files) { file in
                            Toggle(isOn: Binding(
                                get: { selectedTorrentFiles.contains(file.index) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedTorrentFiles.insert(file.index)
                                    } else {
                                        selectedTorrentFiles.remove(file.index)
                                    }
                                }
                            )) {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.fill")
                                        .foregroundStyle(accentTint)
                                        .frame(width: 30, height: 30)
                                        .background(accentTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(file.path)
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(2)
                                            .truncationMode(.middle)
                                        Text(ByteCountFormatter.string(fromByteCount: file.length, countStyle: .file))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(10)
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        } else if let torrentPreviewError {
            Text(torrentPreviewError)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.vertical, 8)
        }
    }

    private var savePathSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField(L10n.text("choose_save_path", language: language), text: $savePath)
                    .textFieldStyle(.roundedBorder)

                Button {
                    pickSavePath()
                } label: {
                    Label(L10n.text("choose", language: language), systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            if source == .link {
                TextField(L10n.text("custom_filename", language: language), text: $fileName)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var advancedOptionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.text("threads", language: language))
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(threadCount)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accentTint.opacity(0.10), in: Capsule())
            }

            Slider(
                value: Binding(
                    get: { Double(threadCount) },
                    set: { threadCount = Int($0) }
                ),
                in: 1...64,
                step: 1
            )
            .tint(accentTint)
        }
    }

    private var footer: some View {
        HStack {
            Button(showingAdvancedOptions ? L10n.text("collapse_advanced", language: language) : L10n.text("advanced_options", language: language)) {
                showingAdvancedOptions.toggle()
            }
            .buttonStyle(.borderless)

            Spacer()

            Button(L10n.text("cancel", language: language)) {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button(L10n.text("confirm", language: language)) {
                submit()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial)
    }

    private var canSubmit: Bool {
        switch source {
        case .link:
            return !downloadURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !savePath.isEmpty
        case .torrent:
            let hasSelection = torrentPreview == nil || !selectedTorrentFiles.isEmpty
            return selectedFileURL.map { isSourceFileAllowed($0, for: .torrent) } == true && !savePath.isEmpty && hasSelection
        case .metalink:
            return selectedFileURL.map { isSourceFileAllowed($0, for: .metalink) } == true && !savePath.isEmpty
        }
    }

    private var sourceTitle: String {
        switch source {
        case .link:
            return L10n.text("download_links", language: language)
        case .torrent:
            return L10n.text("source_file_torrent", language: language)
        case .metalink:
            return L10n.text("source_file_metalink", language: language)
        }
    }

    @ViewBuilder
    private func contentCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))

            content()
        }
        .padding(20)
        .background(Color.white.opacity(0.30), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.60), lineWidth: 1)
        )
    }

    private func submit() {
        Task {
            switch source {
            case .link:
                let urls = downloadURL
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                await viewModel.addURLTasks(
                    urls: urls,
                    savePath: savePath,
                    filename: fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : fileName,
                    threadCount: threadCount
                )
            case .torrent:
                if let selectedFileURL {
                    let selection: Set<Int>?
                    if let torrentPreview, selectedTorrentFiles.count < torrentPreview.files.count {
                        selection = selectedTorrentFiles
                    } else {
                        selection = nil
                    }
                    await viewModel.addTorrentFile(fileURL: selectedFileURL, savePath: savePath, selectedFileIndexes: selection)
                }
            case .metalink:
                if let selectedFileURL {
                    await viewModel.addMetalinkFile(fileURL: selectedFileURL, savePath: savePath)
                }
            }

            settingsStore.update {
                $0.defaultDownloadPath = savePath
                $0.defaultThreadCount = threadCount
            }

            await MainActor.run {
                isPresented = false
            }
        }
    }

    private func pickSavePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            savePath = panel.url?.path ?? savePath
        }
    }

    private func pickSourceFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = sourceAllowedContentTypes(for: source)
        if panel.runModal() == .OK {
            selectedFileURL = panel.url
            if source == .torrent, let selectedFileURL = panel.url {
                Task { await loadTorrentPreview(from: selectedFileURL) }
            }
        }
    }

    private func sourceAllowedContentTypes(for source: NewTaskSource) -> [UTType] {
        sourceAllowedFileExtensions(for: source).compactMap { UTType(filenameExtension: $0) }
    }

    private func sourceAllowedFileExtensions(for source: NewTaskSource) -> Set<String> {
        switch source {
        case .link:
            return []
        case .torrent:
            return ["torrent"]
        case .metalink:
            return ["metalink", "meta4"]
        }
    }

    private func isSourceFileAllowed(_ url: URL, for source: NewTaskSource) -> Bool {
        let ext = url.pathExtension.lowercased()
        let allowed = sourceAllowedFileExtensions(for: source)
        guard !allowed.isEmpty else { return true }
        return allowed.contains(ext)
    }

    private var dialogHeight: CGFloat {
        if source == .torrent, torrentPreview != nil {
            return showingAdvancedOptions ? 780 : 700
        }
        return showingAdvancedOptions ? 650 : 530
    }

    @MainActor
    private func loadTorrentPreview(from fileURL: URL) async {
        isLoadingTorrentPreview = true
        torrentPreviewError = nil
        defer { isLoadingTorrentPreview = false }

        do {
            let preview = try TorrentMetadataService.parse(fileURL: fileURL)
            torrentPreview = preview
            selectedTorrentFiles = Set(preview.files.map(\.index))
        } catch {
            torrentPreview = nil
            selectedTorrentFiles = []
            torrentPreviewError = L10n.format("preview_torrent_failed", language: language, error.localizedDescription)
        }
    }
}
