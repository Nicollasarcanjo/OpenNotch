import AppKit
import Combine
import SwiftUI

/// Letra sincronizada da música que está tocando, mostrada verso a verso no notch fechado.
///
/// A letra vem do LRCLIB (lrclib.net), um banco aberto de letras com marcação de tempo.
/// Para buscar, o app envia a esse serviço o título, o artista e o álbum da faixa.
/// Nada é guardado em disco, e sem letra sincronizada para a faixa nada aparece.
final class LyricsManager: ObservableObject {
    /// Verso atual; vazio quando não há letra, a música está parada ou o recurso está desligado.
    @Published private(set) var line = ""

    private weak var music: MusicManager?
    private var lines: [(time: Double, text: String)] = []
    private var trackKey = ""
    private var base: (position: Double, at: Date)?
    private var lastSync = Date.distantPast
    private var timer: Timer?
    private var observers = Set<AnyCancellable>()
    private var task: URLSessionDataTask?

    init(music: MusicManager) {
        self.music = music
        guard !Demo.enabled else {
            line = "Um verso de exemplo aparece aqui"
            return
        }
        music.$title.combineLatest(music.$artist, music.$album)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] title, artist, album in self?.trackChanged(title: title, artist: artist, album: album) }
            .store(in: &observers)
        music.$isPlaying.sink { [weak self] _ in self?.base = nil }.store(in: &observers)
        let t = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var isEnabled: Bool {
        Prefs.shared.bool(.modMusic) && Prefs.shared.bool(.lyricsEnabled)
    }

    private func trackChanged(title: String, artist: String, album: String) {
        let key = "\(title)|\(artist)|\(album)"
        guard key != trackKey else { return }
        trackKey = key
        lines = []
        line = ""
        base = nil
        task?.cancel()
        guard isEnabled, !title.isEmpty else { return }
        fetch(title: title, artist: artist, album: album, key: key)
    }

    // MARK: Busca

    private func request(_ path: String, _ items: [String: String]) -> URLRequest? {
        var components = URLComponents(string: "https://lrclib.net/api/" + path)
        components?.queryItems = items.filter { !$0.value.isEmpty }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("OpenNotch (https://github.com/Nicollasarcanjo/OpenNotch)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func fetch(title: String, artist: String, album: String, key: String) {
        // Primeiro a faixa exata; se não houver, a busca aberta por título e artista.
        guard let exact = request("get", ["track_name": title, "artist_name": artist, "album_name": album]) else { return }
        task = URLSession.shared.dataTask(with: exact) { [weak self] data, _, _ in
            let found = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                .flatMap { $0["syncedLyrics"] as? String }
            if let found, !found.isEmpty {
                self?.apply(found, key: key)
                return
            }
            guard let self, let search = self.request("search", ["track_name": title, "artist_name": artist]) else { return }
            URLSession.shared.dataTask(with: search) { [weak self] data, _, _ in
                let results = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
                let synced = results.compactMap { $0["syncedLyrics"] as? String }.first { !$0.isEmpty }
                if let synced { self?.apply(synced, key: key) }
            }.resume()
        }
        task?.resume()
    }

    private func apply(_ lrc: String, key: String) {
        let parsed = Self.parse(lrc)
        DispatchQueue.main.async {
            guard self.trackKey == key else { return }   // a faixa já mudou
            self.lines = parsed
            self.base = nil
        }
    }

    /// Formato LRC: "[mm:ss.xx] verso", com uma ou mais marcações de tempo por linha.
    static func parse(_ lrc: String) -> [(time: Double, text: String)] {
        var result: [(Double, String)] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let stamp = rest[rest.index(after: rest.startIndex)..<close].split(separator: ":")
                if stamp.count == 2, let minutes = Double(stamp[0]), let seconds = Double(stamp[1]) {
                    times.append(minutes * 60 + seconds)
                }
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for time in times { result.append((time, text)) }
        }
        return result.sorted { $0.0 < $1.0 }
    }

    // MARK: Sincronia

    private func tick() {
        guard isEnabled, let music, music.isPlaying, !lines.isEmpty else {
            if !line.isEmpty { line = "" }
            return
        }
        // Entre uma consulta e outra ao player, a posição é estimada pelo relógio.
        if base == nil || Date().timeIntervalSince(lastSync) > 4 {
            lastSync = Date()
            music.fetchPosition { [weak self] position in
                guard let position else { return }
                self?.base = (position, Date())
            }
        }
        guard let base else { return }
        let position = base.position + Date().timeIntervalSince(base.at) + 0.15
        let current = lines.last { $0.time <= position }?.text ?? ""
        if current != line { line = current }
    }
}

/// Aparência do verso, escolhida em Configurações › Música.
struct LyricStyle: Equatable {
    var font: String
    var size: Double
    var bold: Bool
    var color: String
    var outline: Bool
    var outlineColor: String
    var outlineWidth: Double

    static var current: LyricStyle {
        let prefs = Prefs.shared
        return LyricStyle(font: prefs.string(.lyricsFont), size: prefs.double(.lyricsSize), bold: prefs.bool(.lyricsBold),
                          color: prefs.string(.lyricsColor), outline: prefs.bool(.lyricsOutline),
                          outlineColor: prefs.string(.lyricsOutlineColor), outlineWidth: prefs.double(.lyricsOutlineWidth))
    }

    static let palette = ["#FFFFFF", "#FFD60A", "#FF9F0A", "#FF453A", "#FF375F", "#BF5AF2", "#0A84FF", "#64D2FF", "#30D158", "#000000"]

    var design: Font.Design {
        switch font {
        case "rounded": return .rounded
        case "serif": return .serif
        case "mono": return .monospaced
        default: return .default
        }
    }

    var swiftUIFont: Font { .system(size: size, weight: bold ? .semibold : .regular, design: design) }

    /// Fonte do AppKit equivalente, usada só para medir a largura do verso.
    var nsFont: NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        let design: NSFontDescriptor.SystemDesign = font == "rounded" ? .rounded : font == "serif" ? .serif
            : font == "mono" ? .monospaced : .default
        return base.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }

    func width(of text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: nsFont]).width)
    }

    static func color(_ hex: String) -> Color {
        var value: UInt64 = 0
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, Scanner(string: digits).scanHexInt64(&value) else { return .white }
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}

/// O verso, com a fonte, a cor e a borda escolhidas.
struct LyricText: View {
    let text: String
    let style: LyricStyle
    var alignment: TextAlignment = .center

    var body: some View {
        // Verso longo quebra em duas linhas; se ainda assim não couber na altura do notch, a letra diminui.
        let label = Text(text).font(style.swiftUIFont).lineLimit(2).multilineTextAlignment(alignment)
            .lineSpacing(-1).minimumScaleFactor(0.6)
        ZStack {
            if style.outline, style.outlineWidth > 0 {
                // Borda: o mesmo texto desenhado em volta, na cor da borda.
                let w = style.outlineWidth
                ForEach(Array([(-w, 0.0), (w, 0.0), (0.0, -w), (0.0, w), (-w, -w), (w, w), (-w, w), (w, -w)].enumerated()),
                        id: \.offset) { _, offset in
                    label.foregroundStyle(LyricStyle.color(style.outlineColor)).offset(x: offset.0, y: offset.1)
                }
            }
            label.foregroundStyle(LyricStyle.color(style.color))
        }
    }
}
