import Foundation

enum TaskStatus: String, Codable, CaseIterable {
    case waiting = "waiting"
    case downloading = "downloading"
    case paused = "paused"
    case completed = "completed"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .waiting:
            return "等待中"
        case .downloading:
            return "下载中"
        case .paused:
            return "已暂停"
        case .completed:
            return "已完成"
        case .error:
            return "错误"
        }
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .waiting:
            return L10n.text("waiting", language: language)
        case .downloading:
            return L10n.text("downloading", language: language)
        case .paused:
            return L10n.text("stopped", language: language)
        case .completed:
            return L10n.text("completed", language: language)
        case .error:
            return L10n.text("error_generic", language: language)
        }
    }
    
    var iconName: String {
        switch self {
        case .waiting:
            return "clock"
        case .downloading:
            return "arrow.down.circle"
        case .paused:
            return "pause.circle"
        case .completed:
            return "checkmark.circle"
        case .error:
            return "exclamationmark.circle"
        }
    }
}
