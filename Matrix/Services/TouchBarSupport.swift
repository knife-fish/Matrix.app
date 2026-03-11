import SwiftUI
import AppKit

struct MainWindowTouchBarBridge: NSViewRepresentable {
    @ObservedObject var viewModel: TaskListViewModel
    let language: AppLanguage

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, language: language)
    }

    func makeNSView(context: Context) -> TouchBarHostingView {
        let view = TouchBarHostingView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: TouchBarHostingView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.language = language
        nsView.coordinator = context.coordinator
        DispatchQueue.main.async {
            nsView.window?.touchBar = context.coordinator.makeTouchBar()
        }
    }

    final class Coordinator: NSObject, NSTouchBarDelegate {
        static let newTaskItem = NSTouchBarItem.Identifier("app.matrix.touchbar.new")
        static let pauseAllItem = NSTouchBarItem.Identifier("app.matrix.touchbar.pauseAll")
        static let resumeAllItem = NSTouchBarItem.Identifier("app.matrix.touchbar.resumeAll")
        static let clearCompletedItem = NSTouchBarItem.Identifier("app.matrix.touchbar.clearCompleted")

        var viewModel: TaskListViewModel
        var language: AppLanguage

        init(viewModel: TaskListViewModel, language: AppLanguage) {
            self.viewModel = viewModel
            self.language = language
        }

        func makeTouchBar() -> NSTouchBar {
            let touchBar = NSTouchBar()
            touchBar.delegate = self
            touchBar.defaultItemIdentifiers = [
                Self.newTaskItem,
                .flexibleSpace,
                Self.pauseAllItem,
                Self.resumeAllItem,
                Self.clearCompletedItem
            ]
            return touchBar
        }

        func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
            switch identifier {
            case Self.newTaskItem:
                return buttonItem(identifier: identifier, title: L10n.text("new_task", language: language), action: #selector(openNewTask))
            case Self.pauseAllItem:
                return buttonItem(identifier: identifier, title: L10n.text("pause_all", language: language), action: #selector(pauseAll))
            case Self.resumeAllItem:
                return buttonItem(identifier: identifier, title: L10n.text("resume_all", language: language), action: #selector(resumeAll))
            case Self.clearCompletedItem:
                return buttonItem(identifier: identifier, title: L10n.text("clear_completed", language: language), action: #selector(clearCompleted))
            default:
                return nil
            }
        }

        private func buttonItem(identifier: NSTouchBarItem.Identifier, title: String, action: Selector) -> NSCustomTouchBarItem {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(title: title, target: self, action: action)
            button.bezelColor = .controlAccentColor
            item.view = button
            return item
        }

        @objc private func openNewTask() {
            NotificationCenter.default.post(name: .matrixOpenNewTask, object: nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        @objc private func pauseAll() {
            Task { await viewModel.pauseAllActiveTasks() }
        }

        @objc private func resumeAll() {
            Task { await viewModel.resumeAllPausedTasks() }
        }

        @objc private func clearCompleted() {
            Task { await viewModel.clearCompletedTasks() }
        }
    }
}

final class TouchBarHostingView: NSView {
    weak var coordinator: MainWindowTouchBarBridge.Coordinator?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.touchBar = coordinator?.makeTouchBar()
    }

    override func makeTouchBar() -> NSTouchBar? {
        coordinator?.makeTouchBar()
    }
}
