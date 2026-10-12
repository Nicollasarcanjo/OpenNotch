import AppKit
import SwiftUI

enum Player: String {
    case spotify = "Spotify"
    case music = "Music"
    /// Aba de música no navegador, informada pela extensão do OpenNotch.
    case browser = "Navegador"   // nome interno; o que aparece na tela vem de displayName

    var displayName: String { self == .music ? "Apple Music" : self == .browser ? L("Navegador") : rawValue }

    /// Players que são apps e respondem a AppleScript.
    static let native: [Player] = [.spotify, .music]

    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }

    var notification: Notification.Name {
        .init(self == .spotify ? "com.spotify.client.PlaybackStateChanged" : "com.apple.Music.playerInfo")
    }

    var isEnabled: Bool {
        let prefs = Prefs.shared
        guard prefs.bool(.modMusic) else { return false }
        switch self {
        case .spotify: return prefs.bool(.musicSpotify)
        case .music: return prefs.bool(.musicAppleMusic)
        case .browser: return prefs.bool(.musicBrowser)
        }
    }

    var isRunning: Bool {
        guard self != .browser else { return true }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

/// Lê a faixa atual pelas notificações distribuídas do Spotify / Apple Music
/// e controla a reprodução por AppleScript.
final class MusicManager: ObservableObject {
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var isPlaying = false
    @Published var artwork: NSImage?
    @Published var player: Player?
    /// Player que o macOS não deixou controlar (falta a permissão de Automação).
    @Published private(set) var blocked: Player?

    private var spotifyTrackID = ""
    private var permissionTimer: Timer?
    private let queue = DispatchQueue(label: "opennotch.applescript")
    private var artworkKey = ""
    private let bridge = BrowserBridge()
    private var browserArtwork = ""
    private var lastBrowserBeat = Date.distantPast
    private var browserTimer: Timer?

    init() {
        bridge.onState = { [weak self] state in self?.handleBrowser(state) }
        bridge.start()
        // Se a aba fechar ou a extensão parar de responder, o player do navegador some.
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, self.player == .browser, self.isPlaying,
                  Date().timeIntervalSince(self.lastBrowserBeat) > 6 else { return }
            self.isPlaying = false
        }
        RunLoop.main.add(t, forMode: .common)
        browserTimer = t

        for p in Player.native {
            DistributedNotificationCenter.default().addObserver(forName: p.notification, object: nil,
                                                                queue: .main) { [weak self] note in
                self?.handle(note, from: p)
            }
        }
        refresh()
    }

    private func handle(_ note: Notification, from p: Player) {
        guard p.isEnabled else { return }
        let info = note.userInfo ?? [:]
        let state = info["Player State"] as? String ?? ""
        if state == "Stopped" {
            if player == p { isPlaying = false }
            return
        }
        // Outro player pausando não deve tomar o lugar do que está tocando.
        if state != "Playing", player != p, isPlaying { return }
        if p == .spotify { spotifyTrackID = info["Track ID"] as? String ?? "" }
        apply(player: p, playing: state == "Playing",
              title: info["Name"] as? String ?? "",
              artist: info["Artist"] as? String ?? "",
              album: info["Album"] as? String ?? "")
    }

    private func handleBrowser(_ state: BrowserState) {
        guard Player.browser.isEnabled else { return }
        // Um app tocando tem prioridade; e aba pausada não toma o lugar de outro player.
        if player != .browser, isPlaying || !state.playing { return }
        lastBrowserBeat = Date()
        browserArtwork = state.artwork
        apply(player: .browser, playing: state.playing, title: state.title,
              artist: state.artist, album: state.album.isEmpty ? state.site : state.album)
    }

    private func apply(player p: Player, playing: Bool, title: String, artist: String, album: String) {
        player = p
        isPlaying = playing
        self.title = title
        self.artist = artist
        self.album = album
        let key = "\(p.rawValue)|\(title)|\(artist)|\(album)"
        if key != artworkKey {
            artworkKey = key
            loadArtwork(for: p, key: key, retry: true)
        }
    }

    /// Estado inicial: pergunta aos players que já estão abertos (nunca abre um player fechado).
    func refresh() {
        let running = Player.native.filter { $0.isEnabled && $0.isRunning }
        queue.async { [weak self] in
            guard let self else { return }
            var found: (Player, Bool, String, String, String)?
            for p in running {
                let script = """
                tell application "\(p.rawValue)" to return {player state as string, name of current track, \
                artist of current track, album of current track}
                """
                guard let r = self.run(script), r.numberOfItems == 4 else { continue }
                let playing = r.atIndex(1)?.stringValue == "playing"
                let entry = (p, playing, r.atIndex(2)?.stringValue ?? "", r.atIndex(3)?.stringValue ?? "",
                             r.atIndex(4)?.stringValue ?? "")
                if found == nil || playing { found = entry }
                if playing { break }
            }
            guard let found else { return }
            DispatchQueue.main.async {
                self.apply(player: found.0, playing: found.1, title: found.2, artist: found.3, album: found.4)
            }
        }
    }

    func playPause() {
        isPlaying.toggle()
        send("playpause")
    }

    /// Pede ao macOS a permissão de controlar os players abertos (usado na tela de boas-vindas).
    /// `completion` recebe true se pelo menos um foi liberado, false se negado, nil se nenhum está aberto.
    func requestAutomation(completion: @escaping (Bool?) -> Void) {
        let running = Player.native.filter(\.isRunning)
        queue.async { [weak self] in
            guard let self else { return }
            var result: Bool?
            for player in running {
                let allowed = self.canControl(player)
                result = (result ?? false) || allowed
            }
            DispatchQueue.main.async {
                completion(result)
                if result == true { self.refresh() }
            }
        }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Confere com o macOS se o OpenNotch pode controlar o player. Na primeira vez isso
    /// faz o sistema mostrar o pedido de permissão. Roda fora da thread principal.
    private func canControl(_ p: Player, askUser: Bool = true) -> Bool {
        guard p != .browser else { return true }
        let target = NSAppleEventDescriptor(bundleIdentifier: p.bundleID)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, askUser)
        // procNotFound = o player fechou no meio do caminho; não é falta de permissão.
        let allowed = status == noErr
        let denied = status == OSStatus(errAEEventNotPermitted)
        DispatchQueue.main.async {
            if denied {
                self.blocked = p
                self.watchPermission()
            } else if allowed, self.blocked == p {
                self.blocked = nil
                self.refresh()   // agora dá para ler estado e capa direto do player
            }
        }
        return allowed
    }

    /// Enquanto o controle estiver bloqueado, confere a cada 2 s se a permissão foi liberada
    /// nos Ajustes, para o aviso sumir sozinho.
    private func watchPermission() {
        guard permissionTimer == nil else { return }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, let blocked = self.blocked else {
                timer.invalidate()
                self?.permissionTimer = nil
                return
            }
            self.queue.async { _ = self.canControl(blocked, askUser: false) }
        }
        RunLoop.main.add(t, forMode: .common)
        permissionTimer = t
    }

    func next() { send("next track") }
    func previous() { send("previous track") }

    func openPlayer() {
        guard let player, player != .browser,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func send(_ command: String) {
        guard let player, player.isRunning else { return }
        if player == .browser {
            // A extensão busca o comando na próxima vez que falar com o app (até 1 s).
            bridge.pendingCommand = ["playpause": "playpause", "next track": "next", "previous track": "previous"][command]
            return
        }
        let wasPlaying = isPlaying
        queue.async { [weak self] in
            guard let self else { return }
            let done = self.canControl(player)
                && self.run("tell application \"\(player.rawValue)\" to \(command)", expectsResult: false)
            // O comando não chegou ao player: desfaz a troca otimista do botão.
            if !done, command == "playpause" {
                DispatchQueue.main.async { self.isPlaying = !wasPlaying }
            }
        }
    }

    private func loadArtwork(for p: Player, key: String, retry: Bool) {
        queue.async { [weak self] in
            guard let self, p.isRunning else { return }
            var image: NSImage?
            switch p {
            case .spotify:
                if let s = self.run("tell application \"Spotify\" to return artwork url of current track")?.stringValue,
                   let url = URL(string: s), let data = try? Data(contentsOf: url) {
                    image = NSImage(data: data)
                }
                // Sem permissão de Automação a capa vem do serviço público do Spotify, pelo id da faixa.
                if image == nil { image = Self.spotifyCover(trackID: self.spotifyTrackID) }
            case .music:
                if let data = self.run("tell application \"Music\" to return data of artwork 1 of current track")?.data {
                    image = NSImage(data: data)
                }
                // Idem para o Apple Music: busca pública do iTunes por título e artista.
                if image == nil { image = Self.iTunesCover(for: key) }
            case .browser:
                if let url = URL(string: self.browserArtwork), url.scheme == "https",
                   let data = try? Data(contentsOf: url) {
                    image = NSImage(data: data)
                }
            }
            DispatchQueue.main.async {
                guard self.artworkKey == key else { return }
                self.artwork = image
                // A capa de faixas em streaming pode demorar a ficar disponível.
                if image == nil, retry {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if self.artworkKey == key { self.loadArtwork(for: p, key: key, retry: false) }
                    }
                }
            }
        }
    }

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    private func run(_ source: String, expectsResult: Bool) -> Bool {
        var error: NSDictionary?
        _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }

    private static func json(from url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func spotifyCover(trackID: String) -> NSImage? {
        guard trackID.hasPrefix("spotify:track:"),
              let id = trackID.split(separator: ":").last,
              let lookup = URL(string: "https://open.spotify.com/oembed?url=https://open.spotify.com/track/\(id)"),
              let link = json(from: lookup)?["thumbnail_url"] as? String,
              let url = URL(string: link), let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }

    /// `key` é "Player|título|artista|álbum", o mesmo usado para saber se a capa mudou.
    private static func iTunesCover(for key: String) -> NSImage? {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, !parts[1].isEmpty else { return nil }
        var lookup = URLComponents(string: "https://itunes.apple.com/search")!
        lookup.queryItems = [URLQueryItem(name: "term", value: "\(parts[1]) \(parts[2])"),
                             URLQueryItem(name: "entity", value: "song"), URLQueryItem(name: "limit", value: "1")]
        guard let lookupURL = lookup.url,
              let first = (json(from: lookupURL)?["results"] as? [[String: Any]])?.first,
              let small = first["artworkUrl100"] as? String,
              let url = URL(string: small.replacingOccurrences(of: "100x100", with: "600x600")),
              let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

/// Barrinhas animadas mostradas ao lado do notch enquanto toca música.
struct AudioBarsView: View {
    let playing: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in
                        let phase = sin(t * (5.5 + Double(i) * 1.7) + Double(i) * 1.3)
                        let level = playing ? 0.35 + 0.65 * abs(phase) : 0.25
                        Capsule()
                            .fill(Color.white.opacity(0.85))
                            .frame(height: geo.size.height * level)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct MusicView: View {
    @EnvironmentObject var music: MusicManager

    var body: some View {
        if music.player == nil {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary)
                Text("Nada tocando").font(.headline)
                Text("Dê play no Spotify ou no Apple Music.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 14) {
                ArtworkView(image: music.artwork, size: 104, radius: 12)
                    .onTapGesture { music.openPlayer() }
                    .help(music.player == .browser ? "Tocando no navegador" : "Abrir \(music.player?.displayName ?? "player")")
                VStack(alignment: .leading, spacing: 3) {
                    Text(music.title.isEmpty ? L("Sem título") : music.title)
                        .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(music.artist).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    Text(music.album).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                    Spacer(minLength: 2)
                    HStack(spacing: 18) {
                        control("backward.fill", size: 15, action: music.previous)
                        control(music.isPlaying ? "pause.fill" : "play.fill", size: 22, action: music.playPause)
                        control("forward.fill", size: 15, action: music.next)
                        Spacer(minLength: 0)
                        if let player = music.player {
                            Text(player.displayName).font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.white.opacity(0.1), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let blocked = music.blocked, blocked == music.player {
                        // Sem a permissão de Automação o macOS descarta os comandos em silêncio.
                        Button(action: music.openAutomationSettings) {
                            Text("Controle do \(blocked.displayName) bloqueado · Abrir Ajustes")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(.orange).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 104)
            }
        }
    }

    private func control(_ icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
