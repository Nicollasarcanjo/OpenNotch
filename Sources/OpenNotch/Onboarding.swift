import AppKit
import EventKit
import SwiftUI

/// Tela de boas-vindas: explica as permissões e deixa pedir cada uma na hora.
final class OnboardingWindowController {
    private var window: NSWindow?
    private let services: Services

    init(services: Services) {
        self.services = services
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 640),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = L("Bem-vindo ao OpenNotch")
            w.isReleasedWhenClosed = false
            let view = OnboardingView { [weak self] in
                Prefs.shared.set(true, for: .onboardingDone)
                self?.window?.close()
            }
            .environmentObject(services.music)
            .environmentObject(services.calendar)
            .environmentObject(services.capture)
            w.contentView = NSHostingView(rootView: view)
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct OnboardingView: View {
    let done: () -> Void
    @EnvironmentObject var music: MusicManager
    @EnvironmentObject var calendar: CalendarManager
    @EnvironmentObject var capture: CaptureManager
    @State private var screenAllowed = CGPreflightScreenCaptureAccess()
    @State private var musicAllowed: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bem-vindo ao OpenNotch").font(.title2.weight(.semibold))
                    Text("Passe o mouse sobre o notch, no topo da tela, para abrir o painel.")
                        .foregroundStyle(.secondary)
                }
            }

            Text("Alguns recursos precisam da sua permissão. Você pode liberar agora ou depois; cada um é pedido de novo na primeira vez que for usado.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                row(icon: "music.note", title: "Controlar o Spotify e o Apple Music",
                    why: "Para tocar, pausar, pular faixa e mostrar a capa. O player precisa estar aberto.",
                    granted: musicAllowed, action: { music.requestAutomation { musicAllowed = $0 } })
                row(icon: "camera.viewfinder", title: "Gravação de Tela",
                    why: "Para tirar prints e gravar a tela. Depois de liberar, é preciso abrir o app de novo.",
                    granted: screenAllowed ? true : nil, action: {
                        if !CGRequestScreenCaptureAccess() { capture.openPermissionSettings() }
                    })
                row(icon: "calendar", title: "Calendário",
                    why: "Para mostrar os eventos de hoje na tela inicial.",
                    granted: calendar.status == .fullAccess ? true : (calendar.status == .notDetermined ? nil : false),
                    action: calendar.requestAccess)
                row(icon: "folder", title: "Pastas Mesa e Downloads",
                    why: "Para mostrar os prints feitos pelos atalhos do macOS e o progresso dos downloads. O macOS pergunta sozinho quando for preciso.",
                    granted: nil, action: nil)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Dicas").font(.headline)
                Text("• ⌃⌥N abre e fecha o notch pelo teclado.")
                Text("• A engrenagem dentro do notch abre as configurações, onde tudo pode ser ligado ou desligado.")
                Text("• Solte arquivos no notch para guardar na bandeja; solte um app para criar um atalho.")
            }
            .font(.callout).foregroundStyle(.secondary)

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Começar a usar", action: done).keyboardShortcut(.defaultAction).controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 580, height: 640)
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            screenAllowed = CGPreflightScreenCaptureAccess()
        }
    }

    private func row(icon: String, title: LocalizedStringKey, why: LocalizedStringKey, granted: Bool?,
                     action: (() -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).frame(width: 28).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(why).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if granted == true {
                Label("Liberado", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
            } else if let action {
                Button(granted == false ? "Negado · tentar de novo" : "Permitir", action: action)
                    .fixedSize()
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
