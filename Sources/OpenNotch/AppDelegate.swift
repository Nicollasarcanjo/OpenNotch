import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController!
    private var statusItem: NSStatusItem?
    private var prefsObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = NotchController()
        updateStatusItem()
        prefsObserver = Prefs.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateStatusItem() }

        // Para desenvolvimento: OPENNOTCH_TAB=system abre direto numa aba e mantém aberto.
        let env = ProcessInfo.processInfo.environment
        if let raw = env["OPENNOTCH_TAB"], let tab = NotchTab(rawValue: raw) {
            controller.model.open(tab: tab)
            controller.model.keepOpen = true
        }
        if env["OPENNOTCH_SIMULATE_FINISH"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.controller.simulateFinish() }
        }
        if let path = env["OPENNOTCH_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
                self?.controller.snapshot(to: path)
                NSApplication.shared.terminate(nil)
            }
        }
        if let path = env["OPENNOTCH_SETTINGS_SNAPSHOT"] {
            SettingsWindowController.snapshotAll(to: path)
            NSApplication.shared.terminate(nil)
        }
    }

    /// Reabrir o app (ex.: pelo Finder) mostra as configurações, já que ele não tem Dock.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.showSettings()
        return false
    }

    private func updateStatusItem() {
        let wanted = Prefs.shared.bool(.showMenuBarIcon)
        if wanted, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                         accessibilityDescription: "OpenNotch")
            let menu = NSMenu()
            menu.addItem(withTitle: "Abrir OpenNotch", action: #selector(openNotch), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Configurações…", action: #selector(openSettings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = menu
            statusItem = item
        } else if !wanted, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func openNotch() { controller.model.open() }
    @objc private func openSettings() { controller.showSettings() }
}
