import AppKit
import QuickLookThumbnailing
import SwiftUI

/// Prints e gravações de tela, usando a ferramenta `screencapture` do próprio macOS.
final class CaptureManager: ObservableObject {
    @Published private(set) var items: [URL] = []
    @Published private(set) var recordingSince: Date?
    @Published private(set) var hasPermission = CGPreflightScreenCaptureAccess()
    @Published private(set) var busy = false

    /// Chamado antes de capturar, para o notch sair da frente.
    var beforeCapture: (() -> Void)?
    var onCaptured: ((URL) -> Void)?
    /// Abre o editor de marcações para um print.
    var onAnnotate: ((URL) -> Void)?

    private var recorder: Process?
    private var recorderInput: Pipe?
    private var recordingURL: URL?
    private let selector = RegionSelector()
    // Prints e gravações feitos pelos atalhos do macOS (⇧⌘3, ⇧⌘4, ⇧⌘5), achados pelo Spotlight.
    private let query = NSMetadataQuery()
    private var systemItems: [URL] = []
    private var announced = Set<URL>()
    private static let tool = URL(fileURLWithPath: "/usr/sbin/screencapture")
    private static let extensions: Set<String> = ["png", "jpg", "mov", "mp4"]

    var isRecording: Bool { recordingSince != nil }

    var folder: URL {
        let custom = Prefs.shared.string(.captureFolder)
        if !custom.isEmpty { return URL(fileURLWithPath: custom, isDirectory: true) }
        return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenNotch", isDirectory: true)
    }

    init() {
        if Demo.enabled {
            items = Demo.captures
            hasPermission = true
            return
        }
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture = 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSCreationDateKey, ascending: false)]
        let center = NotificationCenter.default
        center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            self?.systemResultsChanged(announce: false)
        }
        center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] _ in
            self?.systemResultsChanged(announce: true)
        }
        query.start()
        reload()
        // O print anotado entra na galeria e já vai copiado.
        AnnotateWindowController.onSaved = { [weak self] url in
            self?.reload()
            self?.copy(url)
        }
    }

    private func systemResultsChanged(announce: Bool) {
        query.disableUpdates()
        defer { query.enableUpdates() }
        var found: [(URL, Date)] = []
        for case let item as NSMetadataItem in query.results.prefix(60) {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let created = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date ?? .distantPast
            found.append((URL(fileURLWithPath: path), created))
        }
        systemItems = found.map(\.0)
        reload()
        guard announce, Prefs.shared.bool(.modCapture), Prefs.shared.bool(.captureWatchSystem) else { return }
        // Avisa só do que acabou de ser criado e ainda não foi mostrado.
        for (url, created) in found where Date().timeIntervalSince(created) < 20 && !announced.contains(url) {
            guard !(isRecording && url == recordingURL) else { continue }
            finished(url)
        }
    }

    // MARK: Captura

    func screenshot(region: Bool) {
        guard !busy, !isRecording, ensurePermission() else { return }
        let prefs = Prefs.shared
        let url = newFile(prefix: L("Captura"), ext: "png")
        var args = ["-t", "png"]
        if !prefs.bool(.captureSound) { args.append("-x") }
        if region { args.append("-i") }   // seleção de área do próprio macOS; Esc cancela
        args.append(url.path)

        busy = true
        beforeCapture?()
        // Espera a animação de fechar do notch antes de capturar.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            let process = Process()
            process.executableURL = Self.tool
            process.arguments = args
            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.busy = false
                    self?.finished(url)
                }
            }
            do { try process.run() } catch { self.busy = false }
        }
    }

    func toggleRecording(region: Bool = false) {
        isRecording ? stopRecording() : startRecording(region: region)
    }

    private func startRecording(region: Bool) {
        guard !busy, ensurePermission() else { return }
        let prefs = Prefs.shared
        var args = ["-v"]
        if prefs.bool(.captureAudio) { args.append("-g") }
        if prefs.bool(.captureClicks) { args.append("-k") }

        busy = true
        beforeCapture?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard region else {
                self.launchRecorder(args)
                return
            }
            self.selector.select { rect in
                guard let rect else {
                    self.busy = false   // seleção cancelada
                    return
                }
                let area = [rect.minX, rect.minY, rect.width, rect.height].map { String(Int($0)) }.joined(separator: ",")
                self.launchRecorder(args + ["-R" + area])
            }
        }
    }

    private func launchRecorder(_ arguments: [String]) {
        let url = newFile(prefix: L("Gravação"), ext: "mov")
        let process = Process()
        let input = Pipe()
        process.executableURL = Self.tool
        process.arguments = arguments + [url.path]
        process.standardInput = input
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.recorder = nil
                self.recorderInput = nil
                self.recordingSince = nil
                self.finished(url)
            }
        }
        busy = false
        do {
            try process.run()
            recorder = process
            recorderInput = input
            recordingURL = url
            recordingSince = Date()
        } catch {
            recordingSince = nil
        }
    }

    private func stopRecording() {
        guard let recorder else { return }
        // O screencapture encerra a gravação ao receber qualquer tecla; o SIGINT é o plano B.
        try? recorderInput?.fileHandleForWriting.write(contentsOf: Data("q\n".utf8))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if recorder.isRunning { recorder.interrupt() }
        }
    }

    private func finished(_ url: URL) {
        hasPermission = CGPreflightScreenCaptureAccess()
        // Sem arquivo = o usuário cancelou a seleção (ou faltou permissão).
        guard FileManager.default.fileExists(atPath: url.path), announced.insert(url).inserted else { return }
        reload()
        if Prefs.shared.bool(.captureAutoCopy) { copy(url) }
        onCaptured?(url)
    }

    private func ensurePermission() -> Bool {
        hasPermission = CGPreflightScreenCaptureAccess()
        if !hasPermission { CGRequestScreenCaptureAccess() }
        return hasPermission
    }

    func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func newFile(prefix: String, ext: String) -> URL {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return folder.appendingPathComponent("\(prefix) \(formatter.string(from: Date())).\(ext)")
    }

    // MARK: Galeria

    func reload() {
        guard !Demo.enabled else { return }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        var candidates = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys),
                                                                       options: [.skipsHiddenFiles])) ?? []
        if Prefs.shared.bool(.captureWatchSystem) { candidates += systemItems }
        var seen = Set<String>()
        let dated = candidates
            // O arquivo da gravação em andamento ainda está incompleto.
            .filter { Self.extensions.contains($0.pathExtension.lowercased()) && !(isRecording && $0 == recordingURL) }
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
            .compactMap { url -> (URL, Date)? in
                guard let date = (try? url.resourceValues(forKeys: keys))?.contentModificationDate else { return nil }
                return (url, date)
            }
            .sorted { $0.1 > $1.1 }
        items = dated.prefix(max(Prefs.shared.int(.captureGalleryCount), 1)).map(\.0)
    }

    static func isVideo(_ url: URL) -> Bool {
        ["mov", "mp4"].contains(url.pathExtension.lowercased())
    }

    /// Copia para a área de transferência: a imagem em si (prints) e o arquivo (prints e vídeos).
    func copy(_ url: URL) {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if !Self.isVideo(url), let data = try? Data(contentsOf: url) {
            item.setData(data, forType: url.pathExtension.lowercased() == "png" ? .png : .tiff)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    func openFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}

struct CaptureView: View {
    @EnvironmentObject var capture: CaptureManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                actionButton("Tela toda", icon: "macwindow") { capture.screenshot(region: false) }
                    .disabled(capture.isRecording || capture.busy)
                actionButton("Área", icon: "crop") { capture.screenshot(region: true) }
                    .disabled(capture.isRecording || capture.busy)
                if let since = capture.recordingSince {
                    Button { capture.toggleRecording() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                            Text("Parar")
                            ElapsedText(since: since)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    actionButton("Gravar tela", icon: "record.circle.fill", tint: .red) { capture.toggleRecording() }
                        .disabled(capture.busy)
                    actionButton("Gravar área", icon: "rectangle.dashed", tint: .red) {
                        capture.toggleRecording(region: true)
                    }
                    .disabled(capture.busy)
                }
                Spacer(minLength: 0)
                Button(action: capture.openFolder) {
                    Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Abrir a pasta das capturas")
            }

            if !capture.hasPermission {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").foregroundStyle(.orange)
                    Text("Libere “Gravação de Tela e Áudio do Sistema” para o OpenNotch e abra o app de novo.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Abrir Ajustes", action: capture.openPermissionSettings).font(.caption)
                }
            }
            if capture.items.isEmpty {
                Text("Seus últimos prints e gravações aparecem aqui.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(capture.items, id: \.self) { CaptureThumb(url: $0, compact: !capture.hasPermission) }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .onAppear { capture.reload() }
    }

    private func actionButton(_ title: LocalizedStringKey, icon: String, tint: Color = .white,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).symbolRenderingMode(.monochrome).foregroundStyle(tint)
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 10).frame(height: 28)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Tempo decorrido desde `since`, atualizado a cada segundo.
struct ElapsedText: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let total = max(Int(context.date.timeIntervalSince(since)), 0)
            Text(String(format: "%02d:%02d", total / 60, total % 60)).monospacedDigit()
        }
    }
}

private struct CaptureThumb: View {
    let url: URL
    var compact = false
    @EnvironmentObject var capture: CaptureManager
    @State private var image: NSImage?
    @State private var copied = false

    var body: some View {
        ZStack {
            Color.white.opacity(0.07)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            }
            if CaptureManager.isVideo(url) {
                Image(systemName: "play.circle.fill").font(.system(size: 22))
                    .foregroundStyle(.white).shadow(radius: 3)
            }
            if copied {
                Color.black.opacity(0.6)
                Label("Copiado", systemImage: "checkmark").font(.system(size: 11, weight: .semibold))
            }
        }
        .frame(width: compact ? 104 : 150, height: compact ? 66 : 96)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.12)))
        .overlay(ClickCatcher(onClick: copy, onSecondaryClick: { capture.open(url) }))
        .overlay(alignment: .topTrailing) {
            if !CaptureManager.isVideo(url) {
                Button { capture.onAnnotate?(url) } label: {
                    Image(systemName: "pencil.circle.fill").font(.system(size: 17))
                        .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.65))
                        .padding(5).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Anotar: seta, retângulo, texto e borrar")
            }
        }
        .help("Clique: copiar · Clique com dois dedos: abrir\n\(url.lastPathComponent)")
        .task(id: url) { await loadThumbnail() }
    }

    private func copy() {
        capture.copy(url)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { copied = false }
    }

    private func loadThumbnail() async {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 300, height: 192),
                                                   scale: 2, representationTypes: .thumbnail)
        image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }
}

/// Distingue clique normal de clique secundário (dois dedos / botão direito),
/// que o SwiftUI não entrega como ação direta.
private struct ClickCatcher: NSViewRepresentable {
    let onClick: () -> Void
    let onSecondaryClick: () -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onClick = onClick
        view.onSecondaryClick = onSecondaryClick
    }

    final class CatcherView: NSView {
        var onClick: (() -> Void)?
        var onSecondaryClick: (() -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseUp(with event: NSEvent) {
            // Control + clique também conta como secundário no macOS.
            if event.modifierFlags.contains(.control) { onSecondaryClick?() } else { onClick?() }
        }

        override func rightMouseUp(with event: NSEvent) { onSecondaryClick?() }
    }
}
