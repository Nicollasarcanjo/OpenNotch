import AppKit
import Combine
import SwiftUI

/// Painel sem borda que fica acima da barra de menus, sobre o notch.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class NotchController {
    let model = NotchModel()
    private let music = MusicManager()
    private let timers = TimerManager()
    private let tray = TrayStore()
    private let clipboard = ClipboardManager()
    private let notes = NotesStore()
    private let calendar = CalendarManager()
    private let system = SystemMonitor()
    private let agents = AgentMonitor()
    private let apps = AppMonitor()
    private let capture = CaptureManager()
    private let hud = HUDMonitor()
    private let hotKeys = HotKeys()
    private var prefsObserver: AnyCancellable?

    private let panel: NotchPanel
    private var clickMonitor: Any?
    private lazy var settings = SettingsWindowController()

    init() {
        panel = NotchPanel(contentRect: .zero,
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .mainMenu + 3
        // O notch não aparece nos prints nem nas gravações de tela.
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let root = NotchRootView()
            .environmentObject(model)
            .environmentObject(music)
            .environmentObject(timers)
            .environmentObject(tray)
            .environmentObject(clipboard)
            .environmentObject(notes)
            .environmentObject(calendar)
            .environmentObject(system)
            .environmentObject(agents)
            .environmentObject(apps)
            .environmentObject(capture)
            .environmentObject(hud)
            .environmentObject(Prefs.shared)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host

        model.onOpenChange = { [weak self] open in self?.openChanged(open) }
        model.onOpenSettings = { [weak self] pane in self?.showSettings(pane) }
        capture.beforeCapture = { [weak self] in self?.model.close() }
        capture.onCaptured = { [weak self] _ in
            guard Prefs.shared.bool(.captureShowAfter) else { return }
            self?.model.flash(tab: .capture, seconds: 4)
        }
        hotKeys.onShortcut = { [weak self] shortcut in self?.handle(shortcut) }
        hotKeys.setEnabled(Prefs.shared.bool(.hotkeysEnabled))
        prefsObserver = Prefs.shared.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            self?.hotKeys.setEnabled(Prefs.shared.bool(.hotkeysEnabled))
        }
        agents.onFinish = { [weak self] finish in self?.agentFinished(finish) }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.layout() }
        // Clique em qualquer outro app fecha o notch.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.model.close()
        }

        layout()
        panel.orderFrontRegardless()
    }

    private func handle(_ shortcut: Shortcut) {
        switch shortcut {
        case .toggleNotch:
            model.isOpen ? model.close() : openFromKeyboard(nil)
        case .texts:
            openFromKeyboard(.texts)
        case .capture:
            openFromKeyboard(.capture)
        case .recordRegion:
            guard Prefs.shared.bool(.modCapture) else { return }
            capture.toggleRecording(region: true)
        }
    }

    /// Aberto pelo teclado, o notch fica aberto até um clique fora ou o atalho de novo,
    /// e já recebe o foco para dar para digitar.
    private func openFromKeyboard(_ tab: NotchTab?) {
        model.open(tab: tab)
        panel.makeKeyAndOrderFront(nil)
    }

    func showSettings(_ pane: SettingsPane? = nil) {
        model.close()
        settings.show(pane: pane)
    }

    /// Um agente de IA terminou a tarefa: avisa e abre o notch por alguns segundos.
    private func agentFinished(_ finish: AgentFinish) {
        let prefs = Prefs.shared
        guard prefs.bool(.modAgents), prefs.bool(.agentsNotify) else { return }
        let detail = finish.project.isEmpty || finish.project == finish.title
            ? finish.title : "\(finish.title) · \(finish.project)"
        model.banner = "\(finish.provider) terminou: \(detail)"
        if prefs.bool(.agentsSound) { NSSound(named: "Hero")?.play() }
        model.flash(tab: .agents, seconds: max(prefs.double(.agentsNotifySeconds), 2))
    }

    /// Para desenvolvimento: salva um PNG do conteúdo atual da janela.
    func snapshot(to path: String) {
        guard let view = panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Para desenvolvimento: simula o aviso de "agente terminou".
    func simulateFinish() {
        agentFinished(AgentFinish(provider: "Codex", title: "Tarefa de exemplo", project: "meu-projeto"))
    }

    /// Tela com notch, se houver; senão a principal.
    private var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func layout() {
        guard let screen else { return }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0 {
            model.notchSize = CGSize(width: screen.frame.width - left.width - right.width,
                                     height: screen.safeAreaInsets.top)
        } else {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            model.notchSize = CGSize(width: 190, height: max(menuBar, 24))
        }
        panel.setFrame(frame(open: model.isOpen), display: true)
    }

    private func frame(open: Bool) -> NSRect {
        guard let screen else { return .zero }
        let size = open
            ? NotchModel.openSize
            : CGSize(width: model.notchSize.width + 2 * (NotchModel.earWidth + NotchModel.closedTopRadius),
                     height: model.notchSize.height)
        return NSRect(x: screen.frame.midX - size.width / 2,
                      y: screen.frame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    private func openChanged(_ open: Bool) {
        if open {
            panel.setFrame(frame(open: true), display: true)
        } else {
            panel.makeFirstResponder(nil)
            // Só encolhe a janela depois da animação de fechar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, !self.model.isOpen else { return }
                self.panel.setFrame(self.frame(open: false), display: true)
            }
        }
    }
}
