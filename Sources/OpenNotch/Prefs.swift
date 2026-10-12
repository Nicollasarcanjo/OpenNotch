import SwiftUI

/// Todas as preferências do app, guardadas em UserDefaults.
/// As views observam `Prefs.shared`; os managers leem direto quando precisam.
final class Prefs: ObservableObject {
    static let shared = Prefs()

    enum Key: String {
        // Tela inicial
        case homeBlocks, homeApps, homeGif, homeSlides, homeSlideInterval, homeMediaWidth
        // Geral
        case hoverOpens, hoverDelay, closeDelay, showMenuBarIcon, hotkeysEnabled, hudVolume, hudBrightness
        // Módulos (abas)
        case modMusic, modCalendar, modAgents, modApps, modCapture, modTray, modClipboard, modTimers, modNotes, modSystem
        // Música
        case musicSpotify, musicAppleMusic, musicBrowser, musicEars
        // Agentes de IA
        case agentsClaude, agentsCodex, agentsAntigravity, agentsNotify, agentsNotifySeconds
        case agentsSound, agentsEar, agentsClaudeWindow, agentsCustom, agentsHideIdleHours
        // Gerenciador de apps
        case appsShowBackground, appsSort
        // Captura de tela
        case captureFolder, captureAutoCopy, captureSound, captureShowAfter, captureAudio, captureClicks
        case captureGalleryCount, captureWatchSystem
        // Clipboard
        case clipLimit, clipSkipConcealed, clipPersist
        // Timers
        case timersEar, timersSound
        // Sistema
        case sysInterval, sysCPU, sysRAM, sysDisk, sysBattery, sysNetwork
        // Calendário
        case calMaxEvents
    }

    private static let defaults: [Key: Any] = [
        .hoverOpens: true, .hoverDelay: 0.12, .closeDelay: 0.35, .showMenuBarIcon: true, .hotkeysEnabled: true, .hudVolume: true, .hudBrightness: true,
        .modMusic: true, .modCalendar: true, .modAgents: true, .modApps: true, .modCapture: true, .modTray: true, .modClipboard: true,
        .modTimers: true, .modNotes: true, .modSystem: true,
        .musicSpotify: true, .musicAppleMusic: true, .musicBrowser: true, .musicEars: true,
        .agentsClaude: true, .agentsCodex: true, .agentsAntigravity: true, .agentsNotify: true,
        .agentsNotifySeconds: 6.0, .agentsSound: true, .agentsEar: true, .agentsClaudeWindow: 200_000,
        .agentsCustom: "[]", .agentsHideIdleHours: 12,
        .appsShowBackground: false, .appsSort: "cpu",
        .captureFolder: "", .captureAutoCopy: true, .captureSound: true, .captureShowAfter: true,
        .captureAudio: false, .captureClicks: false, .captureGalleryCount: 12, .captureWatchSystem: true,
        .clipLimit: 40, .clipSkipConcealed: true, .clipPersist: true,
        .timersEar: true, .timersSound: true,
        .sysInterval: 2.0, .sysCPU: true, .sysRAM: true, .sysDisk: true, .sysBattery: true, .sysNetwork: true,
        .calMaxEvents: 3,
        .homeBlocks: "[\"music\",\"calendar\"]", .homeApps: "[]", .homeGif: "", .homeSlides: "[]",
        .homeSlideInterval: 5.0, .homeMediaWidth: 190.0,
    ]

    private let store = UserDefaults.standard

    private init() {
        store.register(defaults: Dictionary(uniqueKeysWithValues: Self.defaults.map { ($0.key.rawValue, $0.value) }))
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: store,
                                               queue: .main) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func bool(_ key: Key) -> Bool { store.bool(forKey: key.rawValue) }
    func int(_ key: Key) -> Int { store.integer(forKey: key.rawValue) }
    func double(_ key: Key) -> Double { store.double(forKey: key.rawValue) }
    func string(_ key: Key) -> String { store.string(forKey: key.rawValue) ?? "" }
    func set(_ value: Any, for key: Key) { store.set(value, forKey: key.rawValue) }

    func boolBinding(_ key: Key) -> Binding<Bool> {
        Binding(get: { self.bool(key) }, set: { self.set($0, for: key) })
    }

    func intBinding(_ key: Key) -> Binding<Int> {
        Binding(get: { self.int(key) }, set: { self.set($0, for: key) })
    }

    func doubleBinding(_ key: Key) -> Binding<Double> {
        Binding(get: { self.double(key) }, set: { self.set($0, for: key) })
    }

    /// Volta tudo para o padrão.
    func resetAll() {
        for key in Self.defaults.keys { store.removeObject(forKey: key.rawValue) }
    }
}

/// Ferramenta de IA cadastrada pelo usuário, detectada pelo nome do processo.
struct CustomAgent: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var match: String
}

extension Prefs {
    var customAgents: [CustomAgent] {
        get {
            guard let data = string(.agentsCustom).data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([CustomAgent].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else { return }
            set(json, for: .agentsCustom)
        }
    }
}
