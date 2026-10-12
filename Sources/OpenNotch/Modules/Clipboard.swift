import AppKit
import Combine
import SwiftUI

struct ClipItem: Identifiable, Equatable, Codable {
    var id = UUID()
    let text: String
    let date: Date
}

/// Histórico de textos copiados. Ignora itens marcados como confidenciais (senhas copiadas
/// de gerenciadores) e, se a opção estiver ligada, é guardado em disco entre uma abertura e outra.
final class ClipboardManager: ObservableObject {
    @Published private(set) var items: [ClipItem] = [] { didSet { save() } }
    private var changeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var prefsObserver: AnyCancellable?

    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("clipboard.json")
    }()

    init() {
        if Prefs.shared.bool(.clipPersist), let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([ClipItem].self, from: data) {
            items = saved
        }
        // Ligar ou desligar "manter o histórico" grava ou apaga o arquivo na hora.
        var persisted = Prefs.shared.bool(.clipPersist)
        prefsObserver = Prefs.shared.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            let now = Prefs.shared.bool(.clipPersist)
            if now != persisted {
                persisted = now
                self?.save()
            }
        }
        let t = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != changeCount else { return }
        changeCount = pb.changeCount
        let prefs = Prefs.shared
        guard prefs.bool(.modClipboard) else { return }
        let types = pb.types ?? []
        let secret = types.contains(Self.concealed) || types.contains(Self.transient)
        guard !(secret && prefs.bool(.clipSkipConcealed)),
              let text = pb.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.removeAll { $0.text == text }
        items.insert(ClipItem(text: text, date: Date()), at: 0)
        let limit = max(prefs.int(.clipLimit), 1)
        if items.count > limit { items.removeLast(items.count - limit) }
    }

    /// Grava o histórico em disco (só o dono lê o arquivo) ou apaga o arquivo se a opção for desligada.
    func save() {
        guard Prefs.shared.bool(.clipPersist) else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func copy(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
    }

    func remove(_ item: ClipItem) { items.removeAll { $0.id == item.id } }
    func clear() { items.removeAll() }
}
