import AppKit
import SwiftUI

@main
struct ScanDeskApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = ScanModel()

    var body: some Scene {
        Window("ScanDesk", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 960, minHeight: 620)
                .background(WindowCloseGuard(model: model))
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            ScanCommands()
            // Adds File ▸ Import from iPhone or iPad (Continuity Camera: scan documents or take photos).
            ImportFromDevicesCommands()
        }
    }
}

struct ScanCommands: Commands {
    @FocusedValue(\.scanActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Scan") { if let m = actions?.model { Task { await m.scan() } } }
                .keyboardShortcut("r")
                .disabled(actions == nil || actions!.model.isBusy || actions!.model.selectedScanner == nil)
            Button("Stop Scanning") { actions?.model.stop() }
                .keyboardShortcut(".")
                .disabled(!(actions?.model.isScanning ?? false))
            Divider()
            Button("Add Images or PDFs…") { actions?.addFiles() }
                .keyboardShortcut("o")
                .disabled(actions == nil || actions!.model.isBusy)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save PDF") { if let m = actions?.model { Task { await m.save() } } }
                .keyboardShortcut("s")
                .disabled(actions == nil || actions!.model.pages.isEmpty || actions!.model.isBusy)
            Button("Show Save Folder in Finder") { actions?.model.revealSaveFolder() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Open Last PDF") { actions?.model.openLastPDF() }
                .disabled(actions?.model.lastPDF == nil)
        }
        CommandMenu("Page") {
            Button("Rotate Left") { actions?.model.rotateSelection(clockwise: false) }
                .keyboardShortcut("[")
                .disabled(!(actions?.model.canEditSelection ?? false))
            Button("Rotate Right") { actions?.model.rotateSelection(clockwise: true) }
                .keyboardShortcut("]")
                .disabled(!(actions?.model.canEditSelection ?? false))
            Divider()
            Button("Move Earlier") { actions?.model.moveSelection(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(!(actions?.model.canMoveSelection ?? false))
            Button("Move Later") { actions?.model.moveSelection(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(!(actions?.model.canMoveSelection ?? false))
            Divider()
            Button("Select All Pages") { if let m = actions?.model { m.selection = Set(m.pages.map(\.id)) } }
                .keyboardShortcut("a")
                .disabled(actions?.model.pages.isEmpty ?? true)
            Button("Delete") { actions?.model.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!(actions?.model.canEditSelection ?? false))
            Divider()
            Button("Clear All Pages…") { actions?.clear() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(actions?.model.pages.isEmpty ?? true || actions!.model.isBusy)
        }
    }
}

// MARK: - Quitting and closing with unsaved pages

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: ScanModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, let window = NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) else { return .terminateNow }
        if model.closeConfirmed { return .terminateNow }
        return UnsavedWorkAlert.confirm(model: model, window: window) { ok in
            NSApp.reply(toApplicationShouldTerminate: ok)
        } ? .terminateNow : .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.cleanUp()
    }
}

enum UnsavedWorkAlert {
    /// Returns true if there's nothing to lose. Otherwise shows a sheet and calls `completion` with the answer.
    static func confirm(model: ScanModel, window: NSWindow, completion: @escaping (Bool) -> Void) -> Bool {
        guard model.isBusy || model.hasUnsavedPages else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        if model.isBusy {
            alert.messageText = "A scan or save is still in progress."
            alert.informativeText = "Quit anyway? Unsaved pages will be lost."
        } else {
            let n = model.pages.count
            alert.messageText = "You have \(n) unsaved page\(n == 1 ? "" : "s")."
            alert.informativeText = "Close ScanDesk without saving them?"
        }
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            let ok = response == .alertFirstButtonReturn
            if ok { model.closeConfirmed = true }
            completion(ok)
        }
        return false
    }
}

/// Asks before the window's close button throws away unsaved pages.
/// SwiftUI has no hook for this, so it wraps the window's delegate and forwards everything else.
private struct WindowCloseGuard: NSViewRepresentable {
    let model: ScanModel

    func makeNSView(context: Context) -> NSView { GuardView(model: model) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class GuardView: NSView {
        let model: ScanModel
        private var proxy: DelegateProxy?

        init(model: ScanModel) {
            self.model = model
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, proxy == nil || window.delegate !== proxy else { return }
            let p = DelegateProxy(original: window.delegate, model: model)
            proxy = p
            window.delegate = p
        }
    }

    final class DelegateProxy: NSObject, NSWindowDelegate {
        nonisolated(unsafe) weak var original: NSWindowDelegate?
        let model: ScanModel

        init(original: NSWindowDelegate?, model: ScanModel) {
            self.original = original
            self.model = model
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if model.closeConfirmed { return original?.windowShouldClose?(sender) ?? true }
            let nothingToLose = UnsavedWorkAlert.confirm(model: model, window: sender) { ok in
                if ok { sender.close() }
            }
            guard nothingToLose else { return false }
            return original?.windowShouldClose?(sender) ?? true
        }

        nonisolated override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }

        nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
            if original?.responds(to: selector) ?? false { return original }
            return super.forwardingTarget(for: selector)
        }
    }
}
