import SwiftUI
import Combine

struct TaskDetailView: View {
    private static let maxRenderedPieces = 4096

    let task: DownloadTask
    @EnvironmentObject private var viewModel: TaskListViewModel
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var remoteFiles: [Aria2File] = []
    @State private var remoteStatus: Aria2Status?
    @State private var remotePeers: [Aria2Peer] = []
    @State private var remoteTrackers: [String] = []
    @State private var selectedIndexes = Set<String>()
    @State private var isApplyingSelection = false
    @State private var fileError: String?
    @State private var remoteRefreshTask: Task<Void, Never>?

    private var liveTask: DownloadTask {
        viewModel.task(with: task.id) ?? task
    }

    private var language: AppLanguage {
        settingsStore.settings.appLanguage
    }

    private var accentTint: Color {
        Color(red: 0.16, green: 0.47, blue: 0.94)
    }

    private var isBTTask: Bool {
        liveTask.kind.isBitTorrent
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard
                    detailCard(title: L10n.text("info_basic", language: language)) {
                        infoSection
                    }
                    detailCard(title: L10n.text("task_metrics", language: language)) {
                        metricsSection
                    }
                    if liveTask.kind.supportsFileSelection && !remoteFiles.isEmpty {
                        detailCard(title: L10n.text("file_selection", language: language)) {
                            fileSection
                        }
                    }
                    if isBTTask {
                        detailCard(title: L10n.text("bt_runtime", language: language)) {
                            btRuntimeSection
                        }
                        if !remotePeers.isEmpty {
                            detailCard(title: L10n.text("peer_list", language: language)) {
                                peerSection
                            }
                        }
                        if !remoteTrackers.isEmpty {
                            detailCard(title: L10n.text("tracker_list", language: language)) {
                                trackerSection
                            }
                        }
                        if totalPieceCount > 0 {
                            detailCard(title: L10n.text("piece_completion", language: language)) {
                                pieceSection
                            }
                        }
                        detailCard(title: L10n.text("torrent_info", language: language)) {
                            torrentInfoSection
                        }
                    }
                    if let errorMessage = liveTask.errorMessage, !errorMessage.isEmpty {
                        detailCard(title: L10n.text("error_info", language: language)) {
                            errorSection(errorMessage)
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 720, height: 620)
        .background(
            LinearGradient(
                colors: [accentTint.opacity(0.10), Color(NSColor.windowBackgroundColor), Color(NSColor.controlBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            startRemoteRefreshLoop()
        }
        .onDisappear {
            stopRemoteRefreshLoop()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(liveTask.filename)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    DetailBadge(text: liveTask.kind.displayName(language: language), tint: accentTint)
                    DetailBadge(text: liveTask.status.displayName(language: language), tint: statusColor)
                }
            }

            Spacer()

            Button(L10n.text("close", language: language)) {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    private var summaryCard: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            SummaryTile(title: L10n.text("progress", language: language), value: liveTask.progressPercentage, icon: "chart.pie.fill", tint: accentTint)
            SummaryTile(title: L10n.text("download_speed", language: language), value: liveTask.formattedSpeed, icon: "arrow.down.circle.fill", tint: .blue)
            SummaryTile(title: L10n.text("upload_speed", language: language), value: liveTask.formattedUploadSpeed, icon: "arrow.up.circle.fill", tint: .green)
            SummaryTile(title: isBTTask ? L10n.text("seeding_nodes", language: language) : L10n.text("connections", language: language), value: isBTTask ? "\(liveTask.seeders)" : "\(liveTask.connections)", icon: isBTTask ? "person.2.fill" : "cable.connector", tint: .orange)
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            InfoRow(label: L10n.text("task_status", language: language), value: liveTask.status.displayName(language: language))
            InfoRow(label: L10n.text("task_source", language: language), value: liveTask.url)
            InfoRow(label: L10n.text("task_directory", language: language), value: liveTask.savePath)
            InfoRow(label: "GID", value: liveTask.gid ?? "-")
            if isBTTask, let torrentName = remoteStatus?.bittorrent?.info?.name, !torrentName.isEmpty {
                InfoRow(label: L10n.text("torrent_name", language: language), value: torrentName)
            }
            InfoRow(label: L10n.text("created_at", language: language), value: formatDate(liveTask.createdAt))
            if let completedAt = liveTask.completedAt {
                InfoRow(label: L10n.text("completed_at", language: language), value: formatDate(completedAt))
            }
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProgressView(value: liveTask.progress)
                .progressViewStyle(.linear)
                .tint(statusColor)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatPanel(icon: "internaldrive", label: L10n.text("downloaded_size", language: language), value: liveTask.formattedDownloadedSize)
                StatPanel(icon: "archivebox", label: L10n.text("total_size", language: language), value: liveTask.formattedTotalSize)
                StatPanel(icon: "cable.connector", label: L10n.text("connections", language: language), value: "\(liveTask.connections)")
                StatPanel(icon: "person.2.fill", label: isBTTask ? L10n.text("seeding_nodes", language: language) : L10n.text("task_status", language: language), value: isBTTask ? "\(liveTask.seeders)" : liveTask.status.displayName(language: language))
                StatPanel(icon: "waveform.path.ecg", label: isBTTask ? L10n.text("seeding_status", language: language) : L10n.text("download_speed", language: language), value: isBTTask ? (liveTask.isSeeding ? L10n.text("seeding_active", language: language) : L10n.text("seeding_idle", language: language)) : liveTask.formattedSpeed)
                StatPanel(icon: "clock.fill", label: L10n.text("estimated_remaining", language: language), value: liveTask.remainingTime(language: language) ?? "-")
                StatPanel(icon: "link", label: liveTask.kind.displayName(language: language), value: liveTask.status.displayName(language: language))
            }
        }
    }

    private var btRuntimeSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatPanel(icon: "person.3.fill", label: L10n.text("peer_count", language: language), value: "\(remotePeers.count)")
            StatPanel(icon: "point.3.connected.trianglepath.dotted", label: L10n.text("tracker_count", language: language), value: "\(remoteTrackers.count)")
            StatPanel(icon: "doc.on.doc.fill", label: L10n.text("file_count", language: language), value: "\(remoteFiles.count)")
        }
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(L10n.text("select_all", language: language)) {
                    selectedIndexes = Set(remoteFiles.map(\.index))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer()

                Button(L10n.text("apply_selection", language: language)) {
                    Task { await applySelectedFiles() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isApplyingSelection || selectedIndexes.isEmpty)
            }

            ForEach(Array(remoteFiles.enumerated()), id: \.offset) { _, file in
                Toggle(isOn: Binding(
                    get: { selectedIndexes.contains(file.index) },
                    set: { isSelected in
                        if isSelected {
                            selectedIndexes.insert(file.index)
                        } else {
                            selectedIndexes.remove(file.index)
                        }
                    }
                )) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(accentTint)
                            .frame(width: 34, height: 34)
                            .background(accentTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(URL(fileURLWithPath: file.path).lastPathComponent)
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(ByteCountFormatter.string(fromByteCount: Int64(file.completedLength) ?? 0, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: Int64(file.length) ?? 0, countStyle: .file))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if let fileError {
                Text(fileError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func errorSection(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var peerSection: some View {
        VStack(spacing: 10) {
            ForEach(Array(remotePeers.enumerated()), id: \.offset) { _, peer in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(peer.ip):\(peer.port)")
                            .font(.system(size: 13, weight: .semibold))
                        Text(peer.seeder == "true" ? L10n.text("seeding_active", language: language) : L10n.text("peer_connected", language: language))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        Text("D \(speedLabel(peer.downloadSpeed))")
                        Text("U \(speedLabel(peer.uploadSpeed))")
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var trackerSection: some View {
        VStack(spacing: 10) {
            ForEach(Array(remoteTrackers.enumerated()), id: \.offset) { _, tracker in
                Text(tracker)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var pieceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let completedPieces = Int32(clamping: completedPieceCount)
            let totalPieces = Int32(clamping: totalPieceCount)
            HStack {
                Text(L10n.format("piece_progress_summary", language: language, completedPieces, totalPieces))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if let pieceLength = remoteStatus?.pieceLength,
                   let pieceLengthValue = Int64(pieceLength) {
                    Text(L10n.format("piece_length_value", language: language, ByteCountFormatter.string(fromByteCount: pieceLengthValue, countStyle: .file)))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            PieceGridView(completion: pieceCompletionFlags, accentTint: accentTint)
        }
    }

    private var torrentInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            InfoRow(label: L10n.text("torrent_name", language: language), value: remoteStatus?.bittorrent?.info?.name ?? liveTask.filename)
            InfoRow(label: L10n.text("torrent_mode", language: language), value: remoteStatus?.bittorrent?.mode ?? "-")
            InfoRow(label: L10n.text("comment", language: language), value: remoteStatus?.bittorrent?.comment.nilIfEmpty ?? "-")
            InfoRow(label: L10n.text("creation_date", language: language), value: formattedCreationDate)
        }
    }

    @MainActor
    private func loadRemoteData() async {
        guard let gid = liveTask.gid else {
            return
        }

        let currentPort = await Aria2ProcessManager.shared.getCurrentPort()
        let rpcPort = await Aria2RPCService.shared.getCurrentPort()
        if rpcPort != currentPort {
            await Aria2RPCService.shared.updatePort(currentPort)
        }

        do {
            async let status = Aria2RPCService.shared.getStatus(gid: gid)
            async let files: [Aria2File] = liveTask.kind.supportsFileSelection ? Aria2RPCService.shared.getFiles(gid: gid) : []
            async let peers: [Aria2Peer] = isBTTask ? Aria2RPCService.shared.getPeers(gid: gid) : []
            async let options: [String: String] = isBTTask ? Aria2RPCService.shared.getOption(gid: gid) : [:]

            let resolvedStatus = try await status
            let resolvedFiles = try await files
            let resolvedPeers = try await peers
            let resolvedOptions = try await options
            let trackers = mergeTrackers(status: resolvedStatus, options: resolvedOptions)

            remoteStatus = resolvedStatus
            remoteFiles = resolvedFiles
            remotePeers = resolvedPeers
            remoteTrackers = trackers
            selectedIndexes = Set(resolvedFiles.filter { $0.selected == "true" }.map(\.index))
            fileError = nil
        } catch {
            fileError = L10n.format("load_files_failed", language: language, error.localizedDescription)
        }
    }

    @MainActor
    private func startRemoteRefreshLoop() {
        stopRemoteRefreshLoop()
        remoteRefreshTask = Task {
            while !Task.isCancelled {
                await loadRemoteData()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    @MainActor
    private func stopRemoteRefreshLoop() {
        remoteRefreshTask?.cancel()
        remoteRefreshTask = nil
    }

    @MainActor
    private func applySelectedFiles() async {
        guard let gid = liveTask.gid else { return }
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        let currentPort = await Aria2ProcessManager.shared.getCurrentPort()
        let rpcPort = await Aria2RPCService.shared.getCurrentPort()
        if rpcPort != currentPort {
            await Aria2RPCService.shared.updatePort(currentPort)
        }

        do {
            try await Aria2RPCService.shared.changeOption(
                gid: gid,
                options: ["select-file": selectedIndexes.sorted().joined(separator: ",")]
            )
            await loadRemoteData()
        } catch {
            fileError = L10n.format("apply_selection_failed", language: language, error.localizedDescription)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLocale(for: language)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func detailCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
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

    private var statusColor: Color {
        switch liveTask.status {
        case .downloading:
            return .blue
        case .waiting:
            return .orange
        case .completed:
            return .green
        case .paused:
            return .yellow
        case .error:
            return .red
        }
    }

    private var totalPieceCount: Int {
        guard let totalLength = Int64(remoteStatus?.totalLength ?? ""),
              let pieceLength = Int64(remoteStatus?.pieceLength ?? ""),
              pieceLength > 0 else {
            return 0
        }
        return Int((totalLength + pieceLength - 1) / pieceLength)
    }

    private var renderedPieceCount: Int {
        min(totalPieceCount, Self.maxRenderedPieces)
    }

    private var pieceCompletionFlags: [Bool] {
        decodeBitfield(remoteStatus?.bitfield, pieceCount: renderedPieceCount)
    }

    private var completedPieceCount: Int {
        guard let completedLength = Int64(remoteStatus?.completedLength ?? ""),
              let pieceLength = Int64(remoteStatus?.pieceLength ?? ""),
              pieceLength > 0 else {
            return pieceCompletionFlags.filter { $0 }.count
        }
        let completed = Int((completedLength + pieceLength - 1) / pieceLength)
        return min(max(completed, 0), totalPieceCount)
    }

    private var formattedCreationDate: String {
        guard let creationDateString = remoteStatus?.bittorrent?.creationDate,
              let timestamp = TimeInterval(creationDateString) else {
            return "-"
        }
        return formatDate(Date(timeIntervalSince1970: timestamp))
    }

    private func mergeTrackers(status: Aria2Status, options: [String: String]) -> [String] {
        let announceTrackers = status.bittorrent?.announceList?.flatMap { $0 } ?? []
        let optionTrackers = options["bt-tracker"]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
        let merged = announceTrackers + optionTrackers
        return Array(NSOrderedSet(array: merged.filter { !$0.isEmpty }).compactMap { $0 as? String })
    }

    private func decodeBitfield(_ bitfield: String?, pieceCount: Int) -> [Bool] {
        guard pieceCount > 0 else { return [] }
        guard let bitfield, !bitfield.isEmpty else { return Array(repeating: false, count: pieceCount) }
        var bits = [Bool]()
        bits.reserveCapacity(pieceCount)

        for character in bitfield {
            guard let value = Int(String(character), radix: 16) else { continue }
            for shift in stride(from: 3, through: 0, by: -1) {
                bits.append(((value >> shift) & 1) == 1)
                if bits.count == pieceCount {
                    return bits
                }
            }
        }

        if bits.count < pieceCount {
            bits.append(contentsOf: Array(repeating: false, count: pieceCount - bits.count))
        }
        return bits
    }

    private func speedLabel(_ value: String?) -> String {
        let bytes = Int64(value ?? "0") ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + "/s"
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SummaryTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.30), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.60), lineWidth: 1)
        )
    }
}

private struct StatPanel: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DetailBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct PieceGridView: View {
    let completion: [Bool]
    let accentTint: Color

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 24)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(completion.enumerated()), id: \.offset) { entry in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(entry.element ? accentTint : Color.secondary.opacity(0.12))
                    .frame(height: 8)
            }
        }
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
