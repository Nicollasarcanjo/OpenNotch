import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, shortcuts, home, modules, music, browserExtension, agents, apps, capture, clipboard, timers, system, calendar, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Geral"
        case .shortcuts: return "Atalhos"
        case .home: return "Tela inicial"
        case .modules: return "Módulos"
        case .music: return "Música"
        case .browserExtension: return "Extensão do navegador"
        case .agents: return "Agentes de IA"
        case .apps: return "Apps abertos"
        case .capture: return "Captura de tela"
        case .clipboard: return "Textos copiados"
        case .timers: return "Timers"
        case .system: return "Sistema"
        case .calendar: return "Calendário"
        case .about: return "Sobre"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .home: return "house"
        case .modules: return "square.grid.2x2"
        case .music: return "music.note"
        case .browserExtension: return "puzzlepiece.extension"
        case .agents: return "sparkles"
        case .apps: return "square.stack.3d.up"
        case .capture: return "camera.viewfinder"
        case .clipboard: return "doc.on.clipboard"
        case .timers: return "timer"
        case .system: return "cpu"
        case .calendar: return "calendar"
        case .about: return "info.circle"
        }
    }
}

final class SettingsWindowController {
    private var window: NSWindow?

    func show(pane: SettingsPane? = nil) {
        if let pane, let window {
            window.contentView = NSHostingView(rootView: SettingsRootView(pane: pane).environmentObject(Prefs.shared))
        }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Configurações do OpenNotch"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsRootView(pane: pane ?? .general).environmentObject(Prefs.shared))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Para desenvolvimento: salva um PNG de cada painel em `directory`.
    static func snapshotAll(to directory: String) {
        for pane in SettingsPane.allCases {
            let view = NSHostingView(rootView: SettingsRootView(pane: pane).environmentObject(Prefs.shared))
            let frame = NSRect(x: 0, y: 0, width: 720, height: 500)
            let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = URL(fileURLWithPath: directory).appendingPathComponent("settings-\(pane.rawValue).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}

struct SettingsRootView: View {
    @State var pane: SettingsPane = .general

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsPane.allCases) { item in
                    Button { pane = item } label: {
                        Label(item.title, systemImage: item.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(pane == item ? Color.accentColor.opacity(0.25) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(10)
            .frame(width: 180)
            .background(.quaternary.opacity(0.4))

            Divider()

            Form { detail }
                .formStyle(.grouped)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 500)
    }

    @ViewBuilder private var detail: some View {
        switch pane {
        case .general: GeneralPane()
        case .shortcuts: ShortcutsPane()
        case .home: HomePane()
        case .modules: ModulesPane()
        case .music: MusicPane()
        case .browserExtension: ExtensionPane()
        case .agents: AgentsPane()
        case .apps: AppsPane()
        case .capture: CapturePane()
        case .clipboard: ClipboardPane()
        case .timers: TimersPane()
        case .system: SystemPane()
        case .calendar: CalendarPane()
        case .about: AboutPane()
        }
    }
}

// MARK: - Painéis

private struct GeneralPane: View {
    @EnvironmentObject var prefs: Prefs
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Section("Abertura do notch") {
            Toggle("Abrir ao passar o mouse", isOn: prefs.boolBinding(.hoverOpens))
            if prefs.bool(.hoverOpens) {
                LabeledSlider("Espera antes de abrir", value: prefs.doubleBinding(.hoverDelay),
                              range: 0...1, step: 0.05, unit: "s")
            } else {
                Text("Clique no notch para abrir.").font(.caption).foregroundStyle(.secondary)
            }
            LabeledSlider("Espera antes de fechar", value: prefs.doubleBinding(.closeDelay),
                          range: 0.1...2, step: 0.05, unit: "s")
        }
        Section {
            Toggle("Mostrar o volume ao mudar", isOn: prefs.boolBinding(.hudVolume))
            Toggle("Mostrar o brilho ao mudar", isOn: prefs.boolBinding(.hudBrightness))
        } header: {
            Text("Volume e brilho no notch")
        } footer: {
            Text("O indicador aparece ao lado do notch. O aviso padrão do macOS continua aparecendo também.")
        }
        Section("Aplicativo") {
            Toggle("Abrir ao iniciar o Mac", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
            Toggle("Mostrar ícone na barra de menus", isOn: prefs.boolBinding(.showMenuBarIcon))
            if !prefs.bool(.showMenuBarIcon) {
                Text("Sem o ícone, abra as configurações pela engrenagem dentro do notch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Não foi possível alterar: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

enum BrowserExtension {
    /// Salva a extensão como .zip onde o usuário escolher (por padrão, em Downloads).
    static func download() -> URL? {
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension") else { return nil }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "OpenNotch-Extensao.zip"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let target = panel.url else { return nil }

        // O zip é montado a partir de uma cópia chamada "OpenNotch-Extensao", que vira a pasta ao descompactar.
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = staging.appendingPathComponent("OpenNotch-Extensao")
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: folder)
            try? FileManager.default.removeItem(at: target)
            let zip = Process()
            zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            zip.arguments = ["-c", "-k", "--keepParent", folder.path, target.path]
            try zip.run()
            zip.waitUntilExit()
            guard zip.terminationStatus == 0 else { return nil }
        } catch {
            return nil
        }
        NSWorkspace.shared.activateFileViewerSelecting([target])
        return target
    }
}

private struct ExtensionPane: View {
    @EnvironmentObject var prefs: Prefs
    @State private var message: String?

    private let steps = [
        "Clique em “Baixar extensão” e salve o arquivo OpenNotch-Extensao.zip.",
        "Dê dois cliques no .zip para descompactar. Vai aparecer a pasta OpenNotch-Extensao.",
        "No navegador, abra a página de extensões: brave://extensions, chrome://extensions ou edge://extensions.",
        "Ligue o “Modo do desenvolvedor”, no canto superior direito.",
        "Clique em “Carregar sem compactação” e escolha a pasta OpenNotch-Extensao.",
        "Recarregue a aba onde a música está tocando.",
    ]

    var body: some View {
        Section {
            Text("Com a extensão, a música que toca no navegador (YouTube, YouTube Music, Spotify Web, SoundCloud, "
                 + "Deezer, Tidal, Amazon Music e Apple Music) aparece no notch, com os botões de tocar, pausar e pular.")
            HStack {
                Button("Baixar extensão") {
                    message = BrowserExtension.download() == nil ? nil : "Extensão salva. Agora siga os passos abaixo."
                }
                .buttonStyle(.borderedProminent)
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            Toggle("Mostrar no notch a música do navegador", isOn: prefs.boolBinding(.musicBrowser))
        } header: {
            Text("Música do navegador")
        }

        Section("Como instalar") {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)").font(.system(.body, design: .rounded).weight(.semibold))
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor.opacity(0.25), in: Circle())
                    Text(step).fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        Section {
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                let last = BrowserBridge.lastContact
                let connected = last.map { Date().timeIntervalSince($0) < 8 } ?? false
                LabeledContent("Situação") {
                    Label(connected ? "Conectada, recebendo a música"
                                    : last == nil ? "Ainda sem contato com a extensão" : "Sem música tocando no navegador",
                          systemImage: connected ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(connected ? .green : .secondary)
                }
            }
        } footer: {
            Text("A extensão só conversa com o OpenNotch neste Mac e só envia dados enquanto há música tocando. "
                 + "Se o Spotify ou o Apple Music estiverem tocando, eles têm prioridade. Pular faixa funciona em "
                 + "YouTube, YouTube Music, Spotify Web e SoundCloud. Se você mover ou apagar a pasta, o navegador "
                 + "desativa a extensão. Safari e Firefox ainda não são suportados.")
        }
    }
}

private struct ShortcutsPane: View {
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        Section {
            Toggle("Ativar atalhos do OpenNotch", isOn: prefs.boolBinding(.hotkeysEnabled))
            ForEach(Shortcut.allCases) { shortcut in
                LabeledContent(shortcut.title) {
                    Text(shortcut.keys).font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(prefs.bool(.hotkeysEnabled) ? .primary : .secondary)
                }
            }
        } header: {
            Text("Atalhos do OpenNotch")
        } footer: {
            Text("Funcionam em qualquer app. Por enquanto as teclas são fixas.")
        }
        Section {
            Toggle("Mostrar no notch os prints feitos pelos atalhos do macOS",
                   isOn: prefs.boolBinding(.captureWatchSystem))
            LabeledContent("Tela toda", value: "⇧⌘3")
            LabeledContent("Área", value: "⇧⌘4")
            LabeledContent("Opções e gravação", value: "⇧⌘5")
        } header: {
            Text("Atalhos de captura do macOS")
        } footer: {
            Text("Você continua usando os atalhos normais do sistema; o que for capturado aparece na aba "
                 + "Captura de tela, e o notch abre mostrando.")
        }
    }
}

private struct HomePane: View {
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        let blocks = prefs.homeBlocks
        Section {
            ForEach(Array(blocks.enumerated()), id: \.element) { index, block in
                HStack {
                    Label(block.title, systemImage: block.icon)
                    if let module = block.module, !prefs.bool(module) {
                        Text("módulo desligado").font(.caption).foregroundStyle(.orange)
                    }
                    Spacer()
                    Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                        .disabled(index == 0).help("Mover para a esquerda")
                    Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(index == blocks.count - 1).help("Mover para a direita")
                    Button { prefs.homeBlocks.removeAll { $0 == block } } label: { Image(systemName: "minus.circle") }
                        .help("Tirar da tela inicial")
                }
                .buttonStyle(.borderless)
            }
            let available = HomeBlock.allCases.filter { !blocks.contains($0) }
            if !available.isEmpty {
                Menu("Adicionar bloco") {
                    ForEach(available) { block in
                        Button { prefs.homeBlocks.append(block) } label: { Label(block.title, systemImage: block.icon) }
                    }
                }
            }
        } header: {
            Text("Blocos, da esquerda para a direita")
        } footer: {
            Text("Se os blocos não couberem na largura do notch, a tela inicial rola para o lado.")
        }

        Section {
            ForEach(prefs.homeApps, id: \.self) { path in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 20, height: 20)
                    Text(FileManager.default.displayName(atPath: path))
                    Spacer()
                    Button { prefs.homeApps.removeAll { $0 == path } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            Button("Adicionar app…", action: chooseApps)
        } header: {
            Text("Atalhos de apps")
        } footer: {
            Text("Também dá para arrastar um app do Finder (pasta Aplicativos) e soltar em cima do notch.")
        }

        Section("GIF") {
            LabeledContent("Arquivo", value: fileLabel(prefs.string(.homeGif)))
            HStack {
                Button("Escolher GIF…", action: chooseGIF)
                if !prefs.string(.homeGif).isEmpty {
                    Button("Remover") { prefs.set("", for: .homeGif) }
                }
            }
        }

        Section("Sequência de imagens") {
            LabeledContent("Imagens", value: prefs.homeSlides.isEmpty ? "Nenhuma" : "\(prefs.homeSlides.count) selecionadas")
            HStack {
                Button("Escolher imagens ou pasta…", action: chooseSlides)
                if !prefs.homeSlides.isEmpty {
                    Button("Remover todas") { prefs.homeSlides = [] }
                }
            }
            LabeledSlider("Trocar a cada", value: prefs.doubleBinding(.homeSlideInterval),
                          range: 1...60, step: 1, unit: "s")
        }

        Section("Tamanho") {
            LabeledSlider("Largura do GIF e das imagens", value: prefs.doubleBinding(.homeMediaWidth),
                          range: 100...420, step: 10, unit: "pt")
        }
    }

    private func move(_ index: Int, by offset: Int) {
        var blocks = prefs.homeBlocks
        let target = index + offset
        guard blocks.indices.contains(index), blocks.indices.contains(target) else { return }
        blocks.swapAt(index, target)
        prefs.homeBlocks = blocks
    }

    private func fileLabel(_ path: String) -> String {
        path.isEmpty ? "Nenhum" : (path as NSString).lastPathComponent
    }

    private func panel(types: [UTType], multiple: Bool, folders: Bool) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = folders
        panel.prompt = "Escolher"
        return panel
    }

    private func chooseApps() {
        let panel = panel(types: [.application], multiple: true, folders: false)
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { prefs.addHomeApp($0.path) }
    }

    private func chooseGIF() {
        let panel = panel(types: [.gif], multiple: false, folders: false)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prefs.set(url.path, for: .homeGif)
        if !prefs.homeBlocks.contains(.gif) { prefs.homeBlocks.append(.gif) }
    }

    private func chooseSlides() {
        let panel = panel(types: [.image], multiple: true, folders: true)
        guard panel.runModal() == .OK else { return }
        var paths: [String] = []
        for url in panel.urls {
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
            if isFolder.boolValue {
                // Pasta: entra toda imagem que estiver direto nela, em ordem de nome.
                let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                paths += files.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
                    .map(\.path).sorted()
            } else {
                paths.append(url.path)
            }
        }
        guard !paths.isEmpty else { return }
        prefs.homeSlides = paths
        if !prefs.homeBlocks.contains(.slideshow) { prefs.homeBlocks.append(.slideshow) }
    }
}

private struct ModulesPane: View {
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        Section {
            Toggle("Música", isOn: prefs.boolBinding(.modMusic))
            Toggle("Calendário", isOn: prefs.boolBinding(.modCalendar))
            Toggle("Agentes de IA", isOn: prefs.boolBinding(.modAgents))
            Toggle("Gerenciador de apps abertos", isOn: prefs.boolBinding(.modApps))
            Toggle("Captura e gravação de tela", isOn: prefs.boolBinding(.modCapture))
            Toggle("Bandeja de arquivos", isOn: prefs.boolBinding(.modTray))
            Toggle("Histórico de textos copiados", isOn: prefs.boolBinding(.modClipboard))
            Toggle("Timers", isOn: prefs.boolBinding(.modTimers))
            Toggle("Anotações", isOn: prefs.boolBinding(.modNotes))
            Toggle("Monitor do sistema", isOn: prefs.boolBinding(.modSystem))
        } header: {
            Text("Funcionalidades ativas")
        } footer: {
            Text("Um módulo desativado some do notch e para de rodar em segundo plano.")
        }
    }
}

private struct MusicPane: View {
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        Section("Players") {
            Toggle("Spotify", isOn: prefs.boolBinding(.musicSpotify))
            Toggle("Apple Music", isOn: prefs.boolBinding(.musicAppleMusic))
            Toggle("Navegador (YouTube, Spotify Web e outros)", isOn: prefs.boolBinding(.musicBrowser))
        }
        Section {
            Text("Para YouTube, Spotify Web e outros sites, instale a extensão em Configurações › Extensão do navegador.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Notch fechado") {
            Toggle("Mostrar capa e barrinhas enquanto toca", isOn: prefs.boolBinding(.musicEars))
        }
        .disabled(!prefs.bool(.modMusic))
    }
}

private struct AgentsPane: View {
    @EnvironmentObject var prefs: Prefs
    @State private var custom = Prefs.shared.customAgents

    var body: some View {
        Section("Ferramentas acompanhadas") {
            Toggle("Claude Code", isOn: prefs.boolBinding(.agentsClaude))
            Toggle("Codex", isOn: prefs.boolBinding(.agentsCodex))
            Toggle("Antigravity (detecção aproximada)", isOn: prefs.boolBinding(.agentsAntigravity))
            Picker("Janela de contexto do Claude", selection: prefs.intBinding(.agentsClaudeWindow)) {
                Text("200 mil tokens").tag(200_000)
                Text("1 milhão de tokens").tag(1_000_000)
            }
            Picker("Esconder sessões ociosas há mais de", selection: prefs.intBinding(.agentsHideIdleHours)) {
                Text("1 hora").tag(1)
                Text("12 horas").tag(12)
                Text("24 horas").tag(24)
                Text("Nunca esconder").tag(0)
            }
        }
        Section("Quando uma tarefa terminar") {
            Toggle("Abrir o notch para avisar", isOn: prefs.boolBinding(.agentsNotify))
            LabeledSlider("Tempo aberto", value: prefs.doubleBinding(.agentsNotifySeconds),
                          range: 2...20, step: 1, unit: "s")
                .disabled(!prefs.bool(.agentsNotify))
            Toggle("Tocar som", isOn: prefs.boolBinding(.agentsSound))
                .disabled(!prefs.bool(.agentsNotify))
            Toggle("Mostrar agentes trabalhando no notch fechado", isOn: prefs.boolBinding(.agentsEar))
        }
        Section {
            ForEach($custom) { $agent in
                HStack {
                    TextField("Nome", text: $agent.name).frame(width: 140)
                    TextField("Trecho do nome do processo (ex.: cursor)", text: $agent.match)
                    Button { custom.removeAll { $0.id == agent.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain)
                }
                .labelsHidden()
            }
            Button("Adicionar ferramenta") { custom.append(CustomAgent(name: "", match: "")) }
        } header: {
            Text("Outras ferramentas")
        } footer: {
            Text("Para ferramentas sem suporte nativo, o OpenNotch acha os processos pelo nome, mostra a pasta "
                 + "em que rodam e usa o consumo de CPU para estimar quando estão trabalhando.")
        }
        .onChange(of: custom) { _, value in prefs.customAgents = value }
    }
}

private struct AppsPane: View {
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        Section {
            Picker("Ordenar por", selection: Binding(get: { prefs.string(.appsSort) },
                                                     set: { prefs.set($0, for: .appsSort) })) {
                Text("CPU").tag(AppSort.cpu.rawValue)
                Text("GPU").tag(AppSort.gpu.rawValue)
                Text("Memória").tag(AppSort.memory.rawValue)
                Text("Nome").tag(AppSort.name.rawValue)
            }
            Toggle("Incluir apps sem ícone no Dock", isOn: prefs.boolBinding(.appsShowBackground))
        } footer: {
            Text("A CPU é mostrada como parte de todos os núcleos, como no Gerenciador de Tarefas do Windows. "
                 + "O uso só é medido enquanto a aba está aberta.")
        }
    }
}

private struct CapturePane: View {
    @EnvironmentObject var prefs: Prefs

    private var folderLabel: String {
        let custom = prefs.string(.captureFolder)
        return custom.isEmpty ? "Imagens/OpenNotch" : (custom as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        Section("Onde salvar") {
            LabeledContent("Pasta", value: folderLabel)
            HStack {
                Button("Escolher pasta…", action: chooseFolder)
                if !prefs.string(.captureFolder).isEmpty {
                    Button("Usar a padrão") { prefs.set("", for: .captureFolder) }
                }
            }
        }
        Section("Depois de capturar") {
            Toggle("Copiar automaticamente", isOn: prefs.boolBinding(.captureAutoCopy))
            Toggle("Abrir o notch mostrando a captura", isOn: prefs.boolBinding(.captureShowAfter))
            Stepper("Mostrar as últimas \(prefs.int(.captureGalleryCount)) capturas",
                    value: prefs.intBinding(.captureGalleryCount), in: 3...40)
        }
        Section {
            Toggle("Som do obturador nos prints", isOn: prefs.boolBinding(.captureSound))
            Toggle("Gravar áudio do microfone no vídeo", isOn: prefs.boolBinding(.captureAudio))
            Toggle("Mostrar cliques do mouse no vídeo", isOn: prefs.boolBinding(.captureClicks))
        } header: {
            Text("Opções")
        } footer: {
            Text("Clique numa captura para copiar; clique com dois dedos para abrir no app padrão. "
                 + "O macOS pede a permissão de Gravação de Tela na primeira captura.")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Escolher"
        if panel.runModal() == .OK, let url = panel.url {
            prefs.set(url.path, for: .captureFolder)
        }
    }
}

private struct ClipboardPane: View {
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        Section {
            Stepper("Guardar os últimos \(prefs.int(.clipLimit)) itens", value: prefs.intBinding(.clipLimit),
                    in: 5...200, step: 5)
            Toggle("Ignorar senhas e itens confidenciais", isOn: prefs.boolBinding(.clipSkipConcealed))
            Toggle("Manter o histórico ao fechar o app", isOn: prefs.boolBinding(.clipPersist))
        } footer: {
            Text(prefs.bool(.clipPersist)
                 ? "O histórico de textos fica salvo neste Mac, num arquivo que só o seu usuário lê."
                 : "O histórico fica só na memória e some ao sair do app.")
        }
    }
}

private struct TimersPane: View {
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        Section {
            Toggle("Mostrar o tempo no notch fechado", isOn: prefs.boolBinding(.timersEar))
            Toggle("Tocar som ao terminar", isOn: prefs.boolBinding(.timersSound))
        } footer: {
            Text("As durações de foco, pausa e contagem são ajustadas na própria aba Timers.")
        }
    }
}

private struct SystemPane: View {
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        Section("Indicadores") {
            Toggle("CPU", isOn: prefs.boolBinding(.sysCPU))
            Toggle("Memória RAM", isOn: prefs.boolBinding(.sysRAM))
            Toggle("Disco", isOn: prefs.boolBinding(.sysDisk))
            Toggle("Bateria", isOn: prefs.boolBinding(.sysBattery))
            Toggle("Rede", isOn: prefs.boolBinding(.sysNetwork))
        }
        Section("Atualização") {
            LabeledSlider("Intervalo", value: prefs.doubleBinding(.sysInterval), range: 1...10, step: 1, unit: "s")
        }
    }
}

private struct CalendarPane: View {
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        Section {
            Stepper("Mostrar até \(prefs.int(.calMaxEvents)) eventos", value: prefs.intBinding(.calMaxEvents), in: 1...4)
        } footer: {
            Text("O acesso ao calendário é pedido na primeira vez, dentro do notch.")
        }
    }
}

private struct AboutPane: View {
    @EnvironmentObject var prefs: Prefs
    @State private var confirmReset = false

    var body: some View {
        Section {
            LabeledContent("OpenNotch", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
            Text("Gratuito, sem anúncios e sem recursos bloqueados.").foregroundStyle(.secondary)
        }
        Section {
            Button("Restaurar configurações padrão") { confirmReset = true }
                .confirmationDialog("Restaurar todas as configurações para o padrão?", isPresented: $confirmReset) {
                    Button("Restaurar", role: .destructive) { prefs.resetAll() }
                }
            Button("Sair do OpenNotch") { NSApplication.shared.terminate(nil) }
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step).frame(width: 180)
                Text(step >= 1 ? "\(Int(value)) \(unit)" : String(format: "%.2f %@", value, unit))
                    .monospacedDigit().frame(width: 54, alignment: .trailing)
            }
        }
    }
}
