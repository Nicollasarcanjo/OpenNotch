import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    @EnvironmentObject var model: NotchModel
    @EnvironmentObject var music: MusicManager
    @EnvironmentObject var timers: TimerManager
    @EnvironmentObject var tray: TrayStore
    @EnvironmentObject var agents: AgentMonitor
    @EnvironmentObject var capture: CaptureManager
    @EnvironmentObject var hud: HUDMonitor
    @EnvironmentObject var prefs: Prefs
    @State private var dropTargeted = false

    private var ears: EarState {
        EarState(hud: hud.current,
                 recording: capture.isRecording,
                 music: music.isPlaying && prefs.bool(.modMusic) && prefs.bool(.musicEars),
                 timer: timers.isRunning && prefs.bool(.modTimers) && prefs.bool(.timersEar),
                 agents: prefs.bool(.modAgents) && prefs.bool(.agentsEar) ? agents.workingCount : 0)
    }

    private var size: CGSize {
        if model.isOpen { return NotchModel.openSize }
        let extra = ears.visible ? 2 * NotchModel.earWidth : 0
        return CGSize(width: model.notchSize.width + 2 * NotchModel.closedTopRadius + extra,
                      height: model.notchSize.height)
    }

    private var shape: NotchShape {
        NotchShape(topRadius: model.isOpen ? 10 : NotchModel.closedTopRadius,
                   bottomRadius: model.isOpen ? 24 : 10)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if model.isOpen {
                NotchOpenView()
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            } else {
                NotchClosedView(ears: ears)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color.black)
        .clipShape(shape)
        .contentShape(shape)
        .onHover { model.hover($0) }
        .onTapGesture { if !model.isOpen { model.open() } }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .onChange(of: dropTargeted) { _, targeted in
            if targeted { model.open(tab: prefs.bool(.modTray) ? .tray : .home) }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: ears)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }
}

extension NotchRootView {
    /// Apps soltos no notch viram atalhos na tela inicial; os outros arquivos vão para a bandeja.
    func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async {
                    if url.pathExtension == "app" {
                        prefs.addHomeApp(url.path)
                        model.tab = .home
                    } else if prefs.bool(.modTray) {
                        tray.add(url)
                    }
                }
            }
        }
    }
}

/// O que aparece ao lado do notch físico quando ele está fechado.
struct EarState: Equatable {
    var hud: HUDState?
    var recording: Bool
    var music: Bool
    var timer: Bool
    var agents: Int

    var visible: Bool { hud != nil || recording || music || timer || agents > 0 }
}

/// Estado fechado: só as "orelhas" ao lado do notch físico.
struct NotchClosedView: View {
    let ears: EarState
    @EnvironmentObject var model: NotchModel
    @EnvironmentObject var music: MusicManager
    @EnvironmentObject var timers: TimerManager
    @EnvironmentObject var capture: CaptureManager

    var body: some View {
        HStack(spacing: 0) {
            if ears.visible {
                leftEar.frame(width: NotchModel.earWidth)
            }
            Color.clear.frame(width: model.notchSize.width)
            if ears.visible {
                rightEar.frame(width: NotchModel.earWidth)
            }
        }
        .frame(height: model.notchSize.height)
    }

    // Esquerda: volume/brilho > gravando > capa da música > agentes > timer.
    @ViewBuilder private var leftEar: some View {
        if let hud = ears.hud {
            Image(systemName: hud.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
        } else if ears.recording {
            Image(systemName: "record.circle.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.red)
        } else if ears.music {
            ArtworkView(image: music.artwork, size: model.notchSize.height - 12, radius: 5)
        } else if ears.agents > 0 {
            Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
        } else {
            Image(systemName: "timer").font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
        }
    }

    // Direita: tempo de gravação > tempo do timer > agentes trabalhando > barrinhas de áudio.
    @ViewBuilder private var rightEar: some View {
        if let hud = ears.hud {
            HUDBar(state: hud).frame(width: 34)
        } else if let since = capture.recordingSince {
            ElapsedText(since: since)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
        } else if ears.timer {
            Text(timers.display)
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(timers.onBreak ? .green : .orange)
        } else if ears.agents > 0 {
            HStack(spacing: 4) {
                StatusDot(working: true)
                Text("\(ears.agents)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.orange)
            }
        } else {
            AudioBarsView(playing: music.isPlaying).frame(width: 18, height: 14)
        }
    }
}

/// Estado aberto: barra de abas na altura do notch físico e o conteúdo abaixo.
struct NotchOpenView: View {
    @EnvironmentObject var model: NotchModel
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        VStack(spacing: 0) {
            tabBar.frame(height: max(model.notchSize.height, 30))
            content
                .padding(.horizontal, 22)
                .padding(.top, 6)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: NotchModel.openSize.width, height: NotchModel.openSize.height)
    }

    // O centro da barra fica atrás do notch físico, então as abas se dividem entre
    // os dois lados, com as configurações na ponta direita.
    private var tabBar: some View {
        let tabs = NotchTab.enabled
        return HStack(spacing: 2) {
            ForEach(tabs.prefix(Self.leftTabs)) { tabButton($0) }
            Spacer(minLength: model.notchSize.width + 16)
            ForEach(tabs.dropFirst(Self.leftTabs)) { tabButton($0) }
            barButton(icon: "gearshape.fill", help: "Configurações", selected: false) { model.onOpenSettings?(nil) }
        }
        .padding(.horizontal, 16)
    }

    /// Quantas abas cabem à esquerda do notch físico; o resto vai para a direita.
    private static let leftTabs = 5

    private func tabButton(_ tab: NotchTab) -> some View {
        barButton(icon: tab.icon, help: tab.title, selected: model.visibleTab == tab) { model.tab = tab }
    }

    private func barButton(icon: String, help: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .opacity(selected ? 1 : 0.5)
                .frame(width: 26, height: 24)
                .background(selected ? Color.white.opacity(0.14) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder private var content: some View {
        switch model.visibleTab {
        case .home: HomeView()
        case .agents: AgentsView()
        case .apps: AppsView()
        case .capture: CaptureView()
        case .tray: TrayView()
        case .timers: TimersView()
        case .texts: TextsView()
        case .system: SystemView()
        case nil:
            VStack(spacing: 6) {
                Text("Todos os módulos estão desativados").font(.headline)
                Button("Abrir configurações") { model.onOpenSettings?(nil) }
            }
        }
    }
}
