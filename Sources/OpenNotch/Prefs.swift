import SwiftUI

/// Todas as preferências do app, guardadas em UserDefaults.
/// As views observam `Prefs.shared`; os managers leem direto quando precisam.
final class Prefs: ObservableObject {
    static let shared = Prefs()

    enum Key: String, CaseIterable {
        // Tela inicial
        case homeBlocks, homeApps, homeGif, homeSlides, homeSlideInterval, homeMediaWidth
        // Geral
        case hoverOpens, hoverDelay, closeDelay, showMenuBarIcon, hotkeysEnabled, hudVolume, hudBrightness
        case displayAllScreens, onboardingDone, updateAutoCheck, language, launchAtLoginConfigured
        // Módulos (abas)
        case modMusic, modCalendar, modAgents, modApps, modMixer, modCapture, modTray, modDownloads, downloadsNotify, modClipboard, modTimers, modNotes, modSystem
        // Música
        case musicSpotify, musicAppleMusic, musicBrowser, musicEars
        // Letra da música
        case lyricsEnabled, lyricsFont, lyricsSize, lyricsBold, lyricsColor, lyricsOutline, lyricsOutlineColor, lyricsOutlineWidth
        // Agentes de IA
        case agentsClaude, agentsCodex, agentsAntigravity, agentsNotify, agentsNotifySeconds
        case agentsSound, agentsEar, agentsClaudeWindow, agentsCustom, agentsHideIdleHours
        // Gerenciador de apps
        case appsShowBackground, appsSort
        // Captura de tela
        case captureFolder, captureAutoCopy, captureSound, captureShowAfter, captureAudio, captureClicks
        case captureGalleryCount, captureWatchSystem, captureShowNotch
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
        .displayAllScreens: true, .onboardingDone: false, .updateAutoCheck: true, .language: "", .launchAtLoginConfigured: false,
        .modMusic: true, .modCalendar: true, .modAgents: true, .modApps: true, .modMixer: true, .modCapture: true, .modTray: true, .modDownloads: true, .downloadsNotify: true, .modClipboard: true,
        .modTimers: true, .modNotes: true, .modSystem: true,
        .musicSpotify: true, .musicAppleMusic: true, .musicBrowser: true,
        .lyricsEnabled: true, .lyricsFont: "system", .lyricsSize: 12.0, .lyricsBold: true, .lyricsColor: "#FFFFFF",
        .lyricsOutline: false, .lyricsOutlineColor: "#000000", .lyricsOutlineWidth: 1.0, .musicEars: true,
        .agentsClaude: true, .agentsCodex: true, .agentsAntigravity: true, .agentsNotify: true,
        .agentsNotifySeconds: 6.0, .agentsSound: true, .agentsEar: true, .agentsClaudeWindow: 200_000,
        .agentsCustom: "[]", .agentsHideIdleHours: 12,
        .appsShowBackground: false, .appsSort: "cpu",
        .captureFolder: "", .captureAutoCopy: true, .captureSound: true, .captureShowAfter: true,
        .captureAudio: false, .captureClicks: false, .captureGalleryCount: 12, .captureWatchSystem: true, .captureShowNotch: false,
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

    // MARK: Importar e exportar

    /// Preferências que não fazem sentido levar para outro Mac ou restaurar depois.
    private static let notExported: Set<Key> = [.onboardingDone, .launchAtLoginConfigured]

    /// As preferências alteradas pelo usuário, em JSON.
    func exportData() -> Data? {
        var values: [String: Any] = [:]
        for key in Key.allCases where !Self.notExported.contains(key) {
            if let value = store.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[key.rawValue] {
                values[key.rawValue] = value
            }
        }
        return try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
    }

    /// Aplica um arquivo exportado. Chaves desconhecidas ou de tipo errado são ignoradas.
    /// Devolve quantas preferências foram aplicadas, ou nil se o arquivo não for válido.
    func importData(_ data: Data) -> Int? {
        guard let values = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var applied = 0
        for key in Key.allCases where !Self.notExported.contains(key) {
            guard let value = values[key.rawValue], let expected = Self.defaults[key] else { continue }
            let sameKind = (expected is String) == (value is String)
            guard sameKind, value is String || value is NSNumber else { continue }
            store.set(value, forKey: key.rawValue)
            applied += 1
        }
        return applied
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
