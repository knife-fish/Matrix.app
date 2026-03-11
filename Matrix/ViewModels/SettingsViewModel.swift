import Foundation
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var aria2RpcUrl: String = "http://localhost:6800/jsonrpc"
    @Published var aria2Secret: String = ""
    @Published var defaultSavePath: String = ""
    @Published var defaultThreadCount: Int = 4
    @Published var maxConcurrentDownloads: Int = 5
    @Published var showNotifications: Bool = true
    @Published var autoStartDownloads: Bool = false
    @Published var darkMode: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private let userDefaults = UserDefaults.standard

    private enum Keys {
        static let aria2RpcUrl = "aria2RpcUrl"
        static let aria2Secret = "aria2Secret"
        static let defaultSavePath = "defaultSavePath"
        static let defaultThreadCount = "defaultThreadCount"
        static let maxConcurrentDownloads = "maxConcurrentDownloads"
        static let showNotifications = "showNotifications"
        static let autoStartDownloads = "autoStartDownloads"
        static let darkMode = "darkMode"
    }

    init() {
        loadSettings()
        setupBindings()
    }

    private func setupBindings() {
        $aria2RpcUrl
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveSettings()
            }
            .store(in: &cancellables)

        $aria2Secret
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveSettings()
            }
            .store(in: &cancellables)

        $defaultSavePath
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveSettings()
            }
            .store(in: &cancellables)

        $defaultThreadCount
            .dropFirst()
            .sink { [weak self] _ in
                self?.saveSettings()
            }
            .store(in: &cancellables)

        $maxConcurrentDownloads
            .dropFirst()
            .sink { [weak self] _ in
                self?.saveSettings()
            }
            .store(in: &cancellables)

        $showNotifications
            .dropFirst()
            .sink { [weak self] _ in
                self?.saveSettings()
            }
            .store(in: &cancellables)

        $autoStartDownloads
            .dropFirst()
            .sink { [weak self] _ in
                self?.saveSettings()
            }
            .store(in: &cancellables)

        $darkMode
            .dropFirst()
            .sink { [weak self] _ in
                self?.saveSettings()
            }
            .store(in: &cancellables)
    }

    func loadSettings() {
        aria2RpcUrl = userDefaults.string(forKey: Keys.aria2RpcUrl) ?? "http://localhost:6800/jsonrpc"
        aria2Secret = userDefaults.string(forKey: Keys.aria2Secret) ?? ""
        defaultSavePath = userDefaults.string(forKey: Keys.defaultSavePath) ?? getDefaultDownloadsPath()
        defaultThreadCount = userDefaults.integer(forKey: Keys.defaultThreadCount)
        if defaultThreadCount == 0 { defaultThreadCount = 4 }
        maxConcurrentDownloads = userDefaults.integer(forKey: Keys.maxConcurrentDownloads)
        if maxConcurrentDownloads == 0 { maxConcurrentDownloads = 5 }
        showNotifications = userDefaults.bool(forKey: Keys.showNotifications)
        autoStartDownloads = userDefaults.bool(forKey: Keys.autoStartDownloads)
        darkMode = userDefaults.bool(forKey: Keys.darkMode)
    }

    func saveSettings() {
        userDefaults.set(aria2RpcUrl, forKey: Keys.aria2RpcUrl)
        userDefaults.set(aria2Secret, forKey: Keys.aria2Secret)
        userDefaults.set(defaultSavePath, forKey: Keys.defaultSavePath)
        userDefaults.set(defaultThreadCount, forKey: Keys.defaultThreadCount)
        userDefaults.set(maxConcurrentDownloads, forKey: Keys.maxConcurrentDownloads)
        userDefaults.set(showNotifications, forKey: Keys.showNotifications)
        userDefaults.set(autoStartDownloads, forKey: Keys.autoStartDownloads)
        userDefaults.set(darkMode, forKey: Keys.darkMode)
    }

    func resetToDefaults() {
        aria2RpcUrl = "http://localhost:6800/jsonrpc"
        aria2Secret = ""
        defaultSavePath = getDefaultDownloadsPath()
        defaultThreadCount = 4
        maxConcurrentDownloads = 5
        showNotifications = true
        autoStartDownloads = false
        darkMode = false
        saveSettings()
    }

    func testConnection() async -> Bool {
        do {
            let service = Aria2RPCService.shared
            _ = try await service.getVersion()
            return true
        } catch {
            return false
        }
    }

    private func getDefaultDownloadsPath() -> String {
        let fileManager = FileManager.default
        if let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            return downloadsURL.path
        }
        return fileManager.currentDirectoryPath
    }
}
