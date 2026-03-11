import Foundation
import AppKit
import Combine

class NewTaskViewModel: ObservableObject {
    @Published var urlInput: String = ""
    @Published var savePath: String = ""
    @Published var threadCount: Int = 4
    @Published var filename: String = ""
    @Published var errorMessage: String?
    @Published var isValid: Bool = false

    private var cancellables = Set<AnyCancellable>()

    var urls: [String] {
        urlInput
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var hasMultipleUrls: Bool {
        return urls.count > 1
    }

    var taskCount: Int {
        return urls.count
    }

    init(defaultSavePath: String = "", defaultThreadCount: Int = 4) {
        self.savePath = defaultSavePath
        self.threadCount = defaultThreadCount
    }

    func validate() -> Bool {
        errorMessage = nil

        guard !urlInput.isEmpty else {
            errorMessage = L10n.text("new_task_error_input_link", language: .system)
            isValid = false
            return false
        }

        let validUrls = urls.filter { isValidUrl($0) }
        guard !validUrls.isEmpty else {
            errorMessage = L10n.text("new_task_error_invalid_link", language: .system)
            isValid = false
            return false
        }

        guard !savePath.isEmpty else {
            errorMessage = L10n.text("new_task_error_choose_path", language: .system)
            isValid = false
            return false
        }

        guard threadCount >= 1 && threadCount <= 64 else {
            errorMessage = L10n.text("new_task_error_threads_range", language: .system)
            isValid = false
            return false
        }

        isValid = true
        return true
    }

    func createTasks() -> [(url: String, savePath: String, filename: String?, threadCount: Int)] {
        guard validate() else { return [] }

        return urls.map { url in
            let finalFilename = filename.isEmpty ? nil : filename
            return (url: url, savePath: savePath, filename: finalFilename, threadCount: threadCount)
        }
    }

    func createTasksWithAutoNaming() -> [(url: String, savePath: String, filename: String?, threadCount: Int)] {
        guard validate() else { return [] }

        return urls.enumerated().map { index, url in
            var finalFilename: String? = nil
            if !filename.isEmpty {
                if urls.count > 1 {
                    let ext = (filename as NSString).pathExtension
                    let baseName = (filename as NSString).deletingPathExtension
                    finalFilename = "\(baseName)_\(index + 1).\(ext)"
                } else {
                    finalFilename = filename
                }
            }
            return (url: url, savePath: savePath, filename: finalFilename, threadCount: threadCount)
        }
    }

    func reset(defaultSavePath: String = "", defaultThreadCount: Int = 4) {
        urlInput = ""
        savePath = defaultSavePath
        threadCount = defaultThreadCount
        filename = ""
        errorMessage = nil
        isValid = false
    }

    func selectSavePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = L10n.text("new_task_choose_save_location", language: .system)

        if panel.runModal() == .OK {
            savePath = panel.url?.path ?? savePath
        }
    }

    func autoDetectFilename() {
        guard let firstUrl = urls.first,
              let url = URL(string: firstUrl),
              filename.isEmpty else { return }

        let suggestedFilename = url.lastPathComponent
        if !suggestedFilename.isEmpty && suggestedFilename != "/" {
            filename = suggestedFilename
        }
    }

    private func isValidUrl(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme?.hasPrefix("http") == true || url.scheme == "ftp" || url.scheme == "sftp" || url.scheme == "magnet"
    }
}
