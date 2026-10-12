import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case home, agents, apps, capture, texts, tray, timers, system

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .agents: return "sparkles"
        case .apps: return "square.stack.3d.up.fill"
        case .capture: return "camera.viewfinder"
        case .tray: return "tray.full.fill"
        case .timers: return "timer"
        case .texts: return "text.quote"
        case .system: return "cpu.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return "Início"
        case .agents: return "Agentes de IA"
        case .apps: return "Apps abertos"
        case .capture: return "Captura de tela"
        case .tray: return "Bandeja"
        case .timers: return "Timers"
        case .texts: return "Textos"
        case .system: return "Sistema"
        }
    }

    var isEnabled: Bool {
        let prefs = Prefs.shared
        switch self {
        case .home: return true
        case .agents: return prefs.bool(.modAgents)
        case .apps: return prefs.bool(.modApps)
        case .capture: return prefs.bool(.modCapture)
        case .tray: return prefs.bool(.modTray)
        case .timers: return prefs.bool(.modTimers)
        case .texts: return prefs.bool(.modClipboard) || prefs.bool(.modNotes)
        case .system: return prefs.bool(.modSystem)
        }
    }

    static var enabled: [NotchTab] { allCases.filter(\.isEnabled) }
}

/// Estado compartilhado do notch: aberto/fechado, aba ativa e geometria.
final class NotchModel: ObservableObject {
    static let openSize = CGSize(width: 640, height: 224)
    static let earWidth: CGFloat = 52
    static let closedTopRadius: CGFloat = 6

    @Published var isOpen = false
    @Published var tab: NotchTab = .home
    @Published var notchSize = CGSize(width: 190, height: 32)
    /// Mantém aberto mesmo com o mouse fora (ex.: digitando uma nota).
    @Published var keepOpen = false
    /// Aviso mostrado na aba de agentes quando uma tarefa termina.
    @Published var banner: String?

    var onOpenChange: ((Bool) -> Void)?
    var onOpenSettings: ((SettingsPane?) -> Void)?
    private var pending: DispatchWorkItem?
    private var isHovering = false

    /// Aba a mostrar: a escolhida, ou a primeira ativa se ela foi desativada.
    var visibleTab: NotchTab? {
        tab.isEnabled ? tab : NotchTab.enabled.first
    }

    func hover(_ inside: Bool) {
        isHovering = inside
        pending?.cancel()
        let prefs = Prefs.shared
        if inside {
            guard !isOpen, prefs.bool(.hoverOpens) else { return }
            schedule(after: prefs.double(.hoverDelay)) { self.open() }
        } else {
            guard isOpen, !keepOpen else { return }
            schedule(after: prefs.double(.closeDelay)) { self.close() }
        }
    }

    func open(tab: NotchTab? = nil) {
        pending?.cancel()
        if let tab, tab.isEnabled { self.tab = tab }
        guard !isOpen else { return }
        onOpenChange?(true)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { isOpen = true }
    }

    func close() {
        pending?.cancel()
        guard isOpen else { return }
        keepOpen = false
        banner = nil
        withAnimation(.spring(response: 0.32, dampingFraction: 0.92)) { isOpen = false }
        onOpenChange?(false)
    }

    /// Abre sozinho por alguns segundos (ex.: um agente terminou) e fecha se ninguém interagir.
    func flash(tab: NotchTab, seconds: TimeInterval) {
        let wasOpen = isOpen
        open(tab: tab)
        guard !wasOpen else { return }   // já estava em uso: não fecha na cara do usuário
        schedule(after: seconds) {
            if !self.isHovering, !self.keepOpen { self.close() }
        }
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        let item = DispatchWorkItem(block: action)
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
