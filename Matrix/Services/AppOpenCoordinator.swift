import Foundation
import Combine

extension Notification.Name {
    static let matrixImportURLs = Notification.Name("matrix.import-urls")
}

@MainActor
final class AppOpenCoordinator: NSObject, ObservableObject {
    func handleIncoming(urls: [URL]) {
        NotificationCenter.default.post(name: .matrixImportURLs, object: urls)
    }
}

#if os(macOS)
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?
    static weak var sharedOpenCoordinator: AppOpenCoordinator?
    private var isHandlingTermination = false
    private weak var mainWindow: NSWindow?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            AppDelegate.sharedOpenCoordinator?.handleIncoming(urls: urls)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeMainNotification(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
    }

    @objc
    private func handleWindowDidBecomeMainNotification(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard isMainApplicationWindow(window) else { return }
        registerMainWindow(window)
    }

    private func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.delegate = self
    }

    private func isMainApplicationWindow(_ window: NSWindow) -> Bool {
        if window === mainWindow {
            return true
        }
        return window.title == "Matrix" || window.identifier?.rawValue == "main"
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isMainApplicationWindow(sender) else { return true }
        registerMainWindow(sender)
        sender.orderOut(nil)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return false }
        showMainWindow()
        return true
    }

    func showMainWindow() {
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if let candidate = NSApp.windows.first(where: isMainApplicationWindow) {
            registerMainWindow(candidate)
            candidate.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isHandlingTermination {
            return .terminateLater
        }

        isHandlingTermination = true

        Task {
            NotificationCenter.default.post(name: .matrixWillTerminate, object: nil)
            try? await Task.sleep(for: .milliseconds(250))
            await Aria2ProcessManager.shared.stopIfRunning()
            await MainActor.run {
                self.isHandlingTermination = false
                sender.reply(toApplicationShouldTerminate: true)
            }
        }

        return .terminateLater
    }
}
#endif
