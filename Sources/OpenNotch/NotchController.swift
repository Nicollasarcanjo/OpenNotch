import AppKit
import Combine
import SwiftUI

/// Painel sem borda que fica acima da barra de menus, sobre o notch.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Tudo que os notches de todas as telas compartilham.
final class Services {
    let music = MusicManager()
    let timers = TimerManager()
    let tray = TrayStore()
    let clipboard = ClipboardManager()
    let notes = NotesStore()
    let calendar = CalendarManager()
    let system = SystemMonitor()
    let agents = AgentMonitor()
    let apps = AppMonitor()
    let capture = CaptureManager()
    let hud = HUDMonitor()
    let downloads = DownloadsMonitor()
    let updater = Updater()
}

/// O notch de uma tela: a janela e o estado aberto/fechado dela.
final class ScreenNotch {
    let model = NotchModel()
    let panel: NotchPanel
    private(set) var screen: NSScreen

    init(screen: NSScreen, services: Services) {
        self.screen = screen
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
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
            .environmentObject(services.music)
            .environmentObject(services.timers)
            .environmentObject(services.tray)
            .environmentObject(services.clipboard)
            .environmentObject(services.notes)
            .environmentObject(services.calendar)
            .environmentObject(services.system)
            .environmentObject(services.agents)
            .environmentObject(services.apps)
            .environmentObject(services.capture)
            .environmentObject(services.hud)
            .environmentObject(services.downloads)
            .environmentObject(services.updater)
            .environmentObject(Prefs.shared)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host

        model.onOpenChange = { [weak self] open in self?.openChanged(open) }
        layout()
        panel.orderFrontRegardless()
    }

    func update(screen: NSScreen) {
        self.screen = screen
        layout()
    }

    func close() {
        panel.orderOut(nil)
    }

    private func layout() {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0 {
            model.notchSize = CGSize(width: screen.frame.width - left.width - right.width,
                                     height: screen.safeAreaInsets.top)
        } else {
            // Tela sem notch físico: um notch "virtual" do tamanho da barra de menus.
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            model.notchSize = CGSize(width: 190, height: max(menuBar, 24))
        }
        panel.setFrame(frame(open: model.isOpen), display: true)
    }

    private func frame(open: Bool) -> NSRect {
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

final class NotchController {
    let services = Services()
    private var notches: [ScreenNotch] = []
    private let hotKeys = HotKeys()
    private var prefsObserver: AnyCancellable?
    private var showOnAllScreens = Prefs.shared.bool(.displayAllScreens)
    private var clickMonitor: Any?
    private lazy var settings = SettingsWindowController(services: services)
    private lazy var onboarding = OnboardingWindowController(services: services)

    /// Notch da tela onde o mouse está; se não houver um lá, o primeiro.
    private var active: ScreenNotch? {
        let mouse = NSEvent.mouseLocation
        return notches.first { $0.screen.frame.contains(mouse) } ?? notches.first
    }

    var model: NotchModel { active?.model ?? NotchModel() }

    init() {
        services.capture.beforeCapture = { [weak self] in self?.closeAll() }
        services.capture.onCaptured = { [weak self] _ in
            guard Prefs.shared.bool(.captureShowAfter) else { return }
            self?.active?.model.flash(tab: .capture, seconds: 4)
        }
        services.capture.onAnnotate = { url in AnnotateWindowController.open(url) }
        services.agents.onFinish = { [weak self] finish in self?.agentFinished(finish) }
        services.downloads.onFinished = { [weak self] _ in
            guard Prefs.shared.bool(.modDownloads), Prefs.shared.bool(.downloadsNotify) else { return }
            self?.active?.model.flash(tab: .tray, seconds: 4)
        }

        hotKeys.onShortcut = { [weak self] shortcut in self?.handle(shortcut) }
        hotKeys.setEnabled(Prefs.shared.bool(.hotkeysEnabled))
        prefsObserver = Prefs.shared.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            guard let self else { return }
            self.hotKeys.setEnabled(Prefs.shared.bool(.hotkeysEnabled))
            let all = Prefs.shared.bool(.displayAllScreens)
            if all != self.showOnAllScreens {
                self.showOnAllScreens = all
                self.rebuild()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.rebuild() }
        // Clique em qualquer outro app fecha o notch.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeAll()
        }
        rebuild()

        if !Prefs.shared.bool(.onboardingDone) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.onboarding.show() }
        }
    }

    /// Recria os notches conforme as telas conectadas: um por tela, ou só o da tela com
    /// notch físico (a principal, se nenhuma tiver) quando a opção "todas as telas" está desligada.
    private func rebuild() {
        let screens: [NSScreen]
        if showOnAllScreens {
            screens = NSScreen.screens
        } else {
            screens = [NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main].compactMap { $0 }
        }
        // Reaproveita os que já existem, na ordem, para não perder o estado ao só mudar a resolução.
        for (index, screen) in screens.enumerated() {
            if index < notches.count {
                notches[index].update(screen: screen)
            } else {
                let notch = ScreenNotch(screen: screen, services: services)
                notch.model.onOpenSettings = { [weak self] pane in self?.showSettings(pane) }
                notches.append(notch)
            }
        }
        while notches.count > screens.count {
            notches.removeLast().close()
        }
    }

    private func closeAll() {
        notches.forEach { $0.model.close() }
    }

    private func handle(_ shortcut: Shortcut) {
        switch shortcut {
        case .toggleNotch:
            if let open = notches.first(where: { $0.model.isOpen }) { open.model.close() } else { openFromKeyboard(nil) }
        case .texts:
            openFromKeyboard(.texts)
        case .capture:
            openFromKeyboard(.capture)
        case .recordRegion:
            guard Prefs.shared.bool(.modCapture) else { return }
            services.capture.toggleRecording(region: true)
        }
    }

    /// Aberto pelo teclado, o notch fica aberto até um clique fora ou o atalho de novo,
    /// e já recebe o foco para dar para digitar.
    private func openFromKeyboard(_ tab: NotchTab?) {
        guard let active else { return }
        active.model.open(tab: tab)
        active.panel.makeKeyAndOrderFront(nil)
    }

    func showSettings(_ pane: SettingsPane? = nil) {
        closeAll()
        settings.show(pane: pane)
    }

    func showOnboarding() {
        closeAll()
        onboarding.show()
    }

    /// Um agente de IA terminou a tarefa: avisa e abre o notch por alguns segundos.
    private func agentFinished(_ finish: AgentFinish) {
        let prefs = Prefs.shared
        guard prefs.bool(.modAgents), prefs.bool(.agentsNotify), let model = active?.model else { return }
        let detail = finish.project.isEmpty || finish.project == finish.title
            ? finish.title : "\(finish.title) · \(finish.project)"
        model.banner = L("%@ terminou: %@", finish.provider, detail)
        if prefs.bool(.agentsSound) { NSSound(named: "Hero")?.play() }
        model.flash(tab: .agents, seconds: max(prefs.double(.agentsNotifySeconds), 2))
    }

    /// Para desenvolvimento: salva um PNG do conteúdo atual da janela.
    func snapshot(to path: String) {
        guard let view = notches.first?.panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Para desenvolvimento: simula o aviso de "agente terminou".
    func simulateFinish() {
        agentFinished(AgentFinish(provider: "Codex", title: "Tarefa de exemplo", project: "meu-projeto"))
    }
}
