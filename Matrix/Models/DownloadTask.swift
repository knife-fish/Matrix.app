import Foundation

enum TaskKind: String, Codable, CaseIterable {
    case direct
    case magnet
    case torrent
    case metalink

    var isBitTorrent: Bool {
        self == .magnet || self == .torrent
    }

    var supportsFileSelection: Bool {
        isBitTorrent || self == .metalink
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .direct:
            return L10n.text("task_kind_direct", language: language)
        case .magnet:
            return L10n.text("task_kind_magnet", language: language)
        case .torrent:
            return L10n.text("task_kind_torrent", language: language)
        case .metalink:
            return L10n.text("task_kind_metalink", language: language)
        }
    }
}

struct DownloadTask: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var url: String
    var filename: String
    var kind: TaskKind
    var status: TaskStatus = .waiting
    var progress: Double = 0
    var totalSize: Int64 = 0
    var downloadedSize: Int64 = 0
    var speed: Int64 = 0
    var uploadSpeed: Int64 = 0
    var connections: Int = 0
    var seeders: Int = 0
    var isSeeding = false
    var createdAt: Date = .now
    var completedAt: Date?
    var savePath: String
    var gid: String?
    var errorMessage: String?

    var progressPercentage: String {
        String(format: "%.1f%%", progress * 100)
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    var formattedDownloadedSize: String {
        ByteCountFormatter.string(fromByteCount: downloadedSize, countStyle: .file)
    }

    var formattedSpeed: String {
        guard speed > 0 else { return "0 B/s" }
        return ByteCountFormatter.string(fromByteCount: speed, countStyle: .file) + "/s"
    }

    var formattedUploadSpeed: String {
        guard uploadSpeed > 0 else { return "0 B/s" }
        return ByteCountFormatter.string(fromByteCount: uploadSpeed, countStyle: .file) + "/s"
    }

    func remainingTime(language: AppLanguage) -> String? {
        guard speed > 0, totalSize > 0 else { return nil }
        let remainingBytes = max(0, totalSize - downloadedSize)
        let remainingSeconds = Double(remainingBytes) / Double(speed)

        if remainingSeconds < 60 {
            return L10n.format("remaining_seconds", language: language, remainingSeconds)
        } else if remainingSeconds < 3600 {
            return L10n.format("remaining_minutes", language: language, remainingSeconds / 60)
        } else {
            return L10n.format("remaining_hours", language: language, remainingSeconds / 3600)
        }
    }

    var fileURL: URL {
        URL(fileURLWithPath: savePath).appendingPathComponent(filename)
    }
}
