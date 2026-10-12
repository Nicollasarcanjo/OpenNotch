import AppKit

/// Modo de demonstração (OPENNOTCH_DEMO=1): troca os dados reais por exemplos fictícios,
/// para gerar as imagens do README sem expor músicas, projetos, textos ou capturas de ninguém.
/// Nada é lido do Mac nem gravado em disco nesse modo.
enum Demo {
    static let enabled = ProcessInfo.processInfo.environment["OPENNOTCH_DEMO"] != nil

    private static let folder: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("OpenNotchDemo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Imagem em degradê com um símbolo no meio, usada como capa e como "print" de exemplo.
    static func image(_ symbol: String, from: NSColor, to: NSColor, size: CGSize = CGSize(width: 600, height: 600)) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSGradient(starting: from, ending: to)?.draw(in: rect, angle: -45)
            let config = NSImage.SymbolConfiguration(pointSize: min(size.width, size.height) * 0.3, weight: .semibold)
                .applying(.init(paletteColors: [NSColor.white.withAlphaComponent(0.92)]))
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                glyph.draw(in: NSRect(x: rect.midX - glyph.size.width / 2, y: rect.midY - glyph.size.height / 2,
                                      width: glyph.size.width, height: glyph.size.height))
            }
            return true
        }
    }

    static var artwork: NSImage { image("music.note", from: .systemPink, to: .systemIndigo) }

    private static func file(_ name: String, contents: Data = Data()) -> URL {
        let url = folder.appendingPathComponent(name)
        try? contents.write(to: url)
        return url
    }

    private static func png(_ image: NSImage) -> Data {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return Data() }
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    static var trayFiles: [URL] {
        ["Relatório.pdf", "Slides.key", "Planilha.xlsx"].map { file($0) }
    }

    static var captures: [URL] {
        let wide = CGSize(width: 900, height: 576)
        return [
            file("Captura 1.png", contents: png(image("macwindow", from: .systemTeal, to: .systemBlue, size: wide))),
            file("Captura 2.png", contents: png(image("chart.bar.fill", from: .systemOrange, to: .systemPink, size: wide))),
            file("Captura 3.png", contents: png(image("map.fill", from: .systemGreen, to: .systemTeal, size: wide))),
        ]
    }

    static var notes: [Note] {
        [Note(text: "Ideias para o projeto\n- revisar o layout"), Note(text: "Lista de compras"),
         Note(text: "Reunião de quinta: levar o protótipo")]
    }

    static var copied: [ClipItem] {
        ["git commit -m \"ajusta o layout\"", "https://exemplo.com/documentacao", "Rua das Flores, 123",
         "Obrigado pelo retorno!"].enumerated().map {
            ClipItem(text: $1, date: Date().addingTimeInterval(Double(-$0) * 540))
        }
    }

    static var providers: [AgentProvider] {
        var claude = AgentProvider(id: "claude", name: "Claude Code", icon: "sparkle")
        claude.sessions = [
            AgentSession(id: "1", title: "Refatorar o checkout", project: "loja-online", working: true,
                         usage: 0.42, usageLabel: L("contexto")),
            AgentSession(id: "2", title: "Corrigir testes da API", project: "backend", working: false,
                         usage: 0.71, usageLabel: L("contexto")),
        ]
        var codex = AgentProvider(id: "codex", name: "Codex", icon: "chevron.left.forwardslash.chevron.right")
        codex.limits = [AgentLimit(label: "5 h", percent: 38), AgentLimit(label: L("semana"), percent: 12)]
        codex.sessions = [
            AgentSession(id: "3", title: "Tela de cadastro", project: "app-mobile", working: true,
                         usage: 0.27, usageLabel: L("contexto")),
        ]
        return [claude, codex]
    }

    static var apps: [AppRow] {
        func row(_ name: String, _ path: String, _ cpu: Double, _ gpu: Double, _ gigabytes: Double, _ count: Int) -> AppRow {
            let bytes = UInt64(gigabytes * 1_073_741_824)
            let processes = (0..<count).map {
                ProcessRow(id: pid_t(1000 + $0), name: name, cpu: cpu / Double(count), gpu: 0, memory: bytes / UInt64(count))
            }
            return AppRow(id: name, name: name, icon: NSWorkspace.shared.icon(forFile: path), instances: [1000],
                          cpu: cpu, gpu: gpu, memory: bytes, processes: processes)
        }
        return [
            row("Safari", "/Applications/Safari.app", 12.4, 3.1, 2.3, 14),
            row("Xcode", "/Applications/Xcode.app", 8.7, 1.2, 4.1, 9),
            row("Música", "/System/Applications/Music.app", 2.1, 0, 0.6, 3),
            row("Mail", "/System/Applications/Mail.app", 0.8, 0, 0.9, 5),
            row("Notas", "/System/Applications/Notes.app", 0.3, 0, 0.4, 2),
        ]
    }

    static var downloads: [DownloadItem] {
        [DownloadItem(id: UUID(), name: "instalador.dmg", url: nil, fraction: 0.64, bytesDone: 0,
                      bytesTotal: 512_000_000),
         DownloadItem(id: UUID(), name: "fotos-da-viagem.zip", url: nil, fraction: 1, bytesDone: 0,
                      bytesTotal: 0, finished: true)]
    }

    static let homeApps = ["/Applications/Safari.app", "/System/Applications/Mail.app", "/System/Applications/Notes.app",
                           "/System/Applications/Calendar.app", "/System/Applications/Maps.app",
                           "/System/Applications/Photos.app"]
}
