import Foundation

@MainActor
class TaskViewModel {
    let task: DownloadTask

    init(task: DownloadTask) {
        self.task = task
    }

    var progressText: String {
        return task.progressPercentage
    }

    var speedText: String {
        return task.formattedSpeed
    }

    var sizeText: String {
        if task.totalSize > 0 {
            return "\(task.formattedDownloadedSize) / \(task.formattedTotalSize)"
        } else {
            return task.formattedDownloadedSize
        }
    }

    var remainingTimeText: String {
        guard let remaining = task.remainingTime(language: .system) else {
            return L10n.text("remaining_calculating", language: .system)
        }
        return L10n.format("remaining_time_prefix", language: .system, remaining)
    }

    var statusText: String {
        return task.status.displayName
    }

    var statusIcon: String {
        return task.status.iconName
    }

    var isActive: Bool {
        return task.status == .downloading
    }

    var canPause: Bool {
        return task.status == .downloading
    }

    var canResume: Bool {
        return task.status == .paused || task.status == .error
    }

    var canDelete: Bool {
        return true
    }

    var progressValue: Double {
        return task.progress
    }

    var filename: String {
        return task.filename
    }

    var url: String {
        return task.url
    }

    var createdAtText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        return formatter.localizedString(for: task.createdAt, relativeTo: Date())
    }

    var completedAtText: String? {
        guard let completedAt = task.completedAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: completedAt)
    }

    var savePath: String {
        return task.savePath
    }
}
