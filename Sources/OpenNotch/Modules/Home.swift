import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Blocos que podem compor a tela inicial. Cada tipo aparece no máximo uma vez.
enum HomeBlock: String, Codable, CaseIterable, Identifiable {
    case music, calendar, apps, gif, slideshow, clock, system, timer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: return L("Música")
        case .calendar: return L("Calendário")
        case .apps: return L("Atalhos de apps")
        case .gif: return L("GIF")
        case .slideshow: return L("Sequência de imagens")
        case .clock: return L("Relógio")
        case .system: return L("Sistema (resumo)")
        case .timer: return L("Timer (resumo)")
        }
    }

    var icon: String {
        switch self {
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .apps: return "square.grid.2x2"
        case .gif: return "photo.on.rectangle"
        case .slideshow: return "photo.stack"
        case .clock: return "clock"
        case .system: return "cpu"
        case .timer: return "timer"
        }
    }

    /// Módulo que precisa estar ligado para o bloco funcionar.
    var module: Prefs.Key? {
        switch self {
        case .music: return .modMusic
        case .calendar: return .modCalendar
        case .system: return .modSystem
        case .timer: return .modTimers
        default: return nil
        }
    }
}

extension Prefs {
    var homeBlocks: [HomeBlock] {
        get { decoded(.homeBlocks) ?? [.music, .calendar] }
        set { encode(newValue, for: .homeBlocks) }
    }

    /// Caminhos dos apps com atalho na tela inicial.
    var homeApps: [String] {
        get { decoded(.homeApps) ?? [] }
        set { encode(newValue, for: .homeApps) }
    }

    var homeSlides: [String] {
        get { decoded(.homeSlides) ?? [] }
        set { encode(newValue, for: .homeSlides) }
    }

    /// Adiciona um atalho de app e garante que o bloco de atalhos esteja na tela inicial.
    func addHomeApp(_ path: String) {
        if !homeApps.contains(path) { homeApps.append(path) }
        if !homeBlocks.contains(.apps) { homeBlocks.append(.apps) }
    }

    private func decoded<T: Decodable>(_ key: Key) -> T? {
        guard let data = string(key).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T, for key: Key) {
        guard let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8) else { return }
        set(json, for: key)
    }
}

/// Tela inicial: uma fileira de blocos escolhidos pelo usuário nas configurações.
struct HomeView: View {
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var model: NotchModel

    private var blocks: [HomeBlock] {
        prefs.homeBlocks.filter { block in block.module.map { prefs.bool($0) } ?? true }
    }

    var body: some View {
        if blocks.isEmpty {
            VStack(spacing: 6) {
                Text("A tela inicial está vazia").font(.headline)
                Button("Personalizar") { model.onOpenSettings?(.home) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geo in
                // Com poucos blocos eles ocupam a largura toda; com muitos, a fileira rola.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(blocks.enumerated()), id: \.element) { index, block in
                            if index > 0, !isMedia(block), !isMedia(blocks[index - 1]) {
                                Divider().opacity(0.4)
                            }
                            view(for: block)
                        }
                    }
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, maxHeight: geo.size.height)
                }
            }
            .contextMenu {
                Button("Personalizar tela inicial…") { model.onOpenSettings?(.home) }
            }
        }
    }

    private func isMedia(_ block: HomeBlock) -> Bool { block == .gif || block == .slideshow }

    @ViewBuilder private func view(for block: HomeBlock) -> some View {
        let mediaWidth = CGFloat(prefs.double(.homeMediaWidth))
        switch block {
        case .music: MusicView().frame(minWidth: 290, maxWidth: .infinity, alignment: .leading)
        case .calendar: CalendarView().frame(width: 200)
        case .apps: AppShortcutsBlock().frame(minWidth: 108, maxWidth: .infinity)
        case .gif: GIFBlock().frame(width: mediaWidth)
        case .slideshow: SlideshowBlock().frame(width: mediaWidth)
        case .clock: ClockBlock().frame(width: 132)
        case .system: SystemMiniBlock().frame(width: 190)
        case .timer: TimerMiniBlock().frame(width: 124)
        }
    }
}

// MARK: - Atalhos de apps

private struct AppShortcutsBlock: View {
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        let apps = prefs.homeApps.filter { FileManager.default.fileExists(atPath: $0) }
        if apps.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "square.grid.2x2").font(.title3).foregroundStyle(.secondary)
                Text("Arraste um app até o notch").font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 6)], spacing: 6) {
                    ForEach(apps, id: \.self) { path in
                        Button { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } label: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable().frame(width: 40, height: 40)
                                .padding(3).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(FileManager.default.displayName(atPath: path))
                        .contextMenu {
                            Button("Remover atalho") { prefs.homeApps.removeAll { $0 == path } }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

// MARK: - GIF e sequência de imagens

private struct MediaPlaceholder: View {
    let icon: String
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Mostra uma imagem preenchendo o bloco inteiro (corta o que sobra), com cantos arredondados.
private struct FilledImage<Content: View>: View {
    let imageSize: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let scale = max(geo.size.width / max(imageSize.width, 1), geo.size.height / max(imageSize.height, 1))
            content
                .frame(width: imageSize.width * scale, height: imageSize.height * scale)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// NSImageView, porque a `Image` do SwiftUI não anima GIFs.
private struct AnimatedImage: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleAxesIndependently   // o tamanho certo vem do FilledImage
        view.animates = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.image !== image { view.image = image }
    }
}

private struct GIFBlock: View {
    @EnvironmentObject var prefs: Prefs
    @State private var loaded: (path: String, image: NSImage)?

    var body: some View {
        let path = prefs.string(.homeGif)
        Group {
            if let loaded, loaded.path == path {
                FilledImage(imageSize: loaded.image.size) { AnimatedImage(image: loaded.image) }
            } else {
                MediaPlaceholder(icon: "photo.on.rectangle", text: "Escolha um GIF nas configurações")
            }
        }
        .task(id: path) {
            guard !path.isEmpty, let image = NSImage(contentsOfFile: path) else {
                loaded = nil
                return
            }
            loaded = (path, image)
        }
    }
}

private struct SlideshowBlock: View {
    @EnvironmentObject var prefs: Prefs
    @State private var index = 0
    @State private var current: NSImage?

    var body: some View {
        let slides = prefs.homeSlides
        let interval = max(prefs.double(.homeSlideInterval), 1)
        Group {
            if let current {
                FilledImage(imageSize: current.size) {
                    Image(nsImage: current).resizable()
                }
                .id(index)
                .transition(.opacity)
            } else {
                MediaPlaceholder(icon: "photo.stack", text: "Escolha as imagens nas configurações")
            }
        }
        // Reinicia a contagem quando a lista ou o intervalo mudam.
        .task(id: "\(slides.count)|\(slides.first ?? "")|\(interval)") {
            index = 0
            current = slides.first.flatMap { NSImage(contentsOfFile: $0) }
            guard slides.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                let next = (index + 1) % slides.count
                guard let image = NSImage(contentsOfFile: slides[next]) else { continue }
                withAnimation(.easeInOut(duration: 0.6)) {
                    index = next
                    current = image
                }
            }
        }
    }
}

// MARK: - Widgets pequenos

private struct ClockBlock: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 2) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 36, weight: .semibold, design: .rounded).monospacedDigit())
                Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SystemMiniBlock: View {
    @EnvironmentObject var system: SystemMonitor

    var body: some View {
        HStack(spacing: 12) {
            ring("CPU", system.cpu, .blue)
            ring("RAM", Double(system.memoryUsed) / Double(system.memoryTotal), .purple)
            if let battery = system.battery {
                ring("Bat.", Double(battery) / 100, .green)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ring(_ title: LocalizedStringKey, _ value: Double, _ color: Color) -> some View {
        let clamped = min(max(value, 0), 1)
        return VStack(spacing: 5) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 5)
                Circle().trim(from: 0, to: clamped)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((clamped * 100).rounded()))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            }
            .frame(width: 44, height: 44)
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

private struct TimerMiniBlock: View {
    @EnvironmentObject var timers: TimerManager

    var body: some View {
        VStack(spacing: 6) {
            Text(LocalizedStringKey(timers.mode.rawValue)).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(timers.display)
                .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
            Button(action: timers.toggle) {
                Image(systemName: timers.isRunning ? "pause.fill" : "play.fill")
                    .frame(width: 34, height: 22)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
