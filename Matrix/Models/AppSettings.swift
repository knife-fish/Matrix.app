import Foundation
import Combine
import SwiftUI

enum AppearanceMode: String, Codable, CaseIterable {
    case system
    case light
    case dark

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .system: return L10n.text("appearance_system", language: language)
        case .light: return L10n.text("appearance_light", language: language)
        case .dark: return L10n.text("appearance_dark", language: language)
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum Aria2LogLevel: String, Codable, CaseIterable {
    case debug
    case info
    case notice
    case warn
    case error

    var displayName: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .notice: return "Notice"
        case .warn: return "Warn"
        case .error: return "Error"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var appLanguage: AppLanguage = .system
    var defaultDownloadPath: String = defaultDownloadPathValue()
    var maxConcurrentTasks: Int = 10
    var defaultThreadCount: Int = 16
    var rpcListenPort: Int = 16800
    var downloadSpeedLimitKB: Int = 0
    var uploadSpeedLimitKB: Int = 0
    var logLevel: Aria2LogLevel = .notice
    var enableNotifications: Bool = true
    var userAgent: String = "MotrixSwift/1.0"
    var deleteFilesWhenRemoving: Bool = false
    var autoStartDownloads: Bool = true
    var autoUpdateTrackerList: Bool = true
    var trackerSourceURL: String = "https://cdn.jsdelivr.net/gh/ngosang/trackerslist@master/trackers_best.txt"
    var trackerListText: String = ""
    var trackerListLastUpdatedAt: Date?
    var enableDHT: Bool = true
    var enablePeerExchange: Bool = true
    var enableLocalPeerDiscovery: Bool = false
    var enablePortMapping: Bool = true
    var saveMagnetAsTorrent: Bool = true
    var keepSeeding: Bool = false
    var seedRatio: Double = 1.0
    var seedTimeMinutes: Int = 0
    var btListenPort: Int = 6881
    var dhtListenPort: Int = 26701
    var btMaxPeers: Int = 55
    var proxyEnabled: Bool = false
    var proxyHost: String = ""
    var proxyPort: String = ""
    var rpcListenAll: Bool = true
    var appearanceMode: AppearanceMode = .system
    var showDockIcon: Bool = true
    var showMenuBarExtra: Bool = true
    var showMenuBarSpeed: Bool = true
    var updatedAt: Date = .now
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings

    private let defaults = UserDefaults.standard
    private let key = "matrix.app-settings"

    init() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
            save()
        }
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var draft = settings
        mutate(&draft)
        setSettings(draft)
    }

    func reset() {
        setSettings(AppSettings())
    }

    func exportSettings(to url: URL) throws {
        let data = try JSONEncoder().encode(settings)
        try data.write(to: url, options: .atomic)
    }

    func importSettings(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        setSettings(decoded)
    }

    private func setSettings(_ newSettings: AppSettings) {
        var timestamped = newSettings
        timestamped.updatedAt = .now
        settings = timestamped
        save(timestamped)
    }

    private func save(_ value: AppSettings? = nil) {
        let current = value ?? settings
        guard let data = try? JSONEncoder().encode(current) else { return }
        defaults.set(data, forKey: key)
    }
}

private func defaultDownloadPathValue() -> String {
    let fileManager = FileManager.default

    if let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first {
        return downloadsURL.path
    }

    if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
        return documentsURL.path
    }

    return fileManager.currentDirectoryPath
}
