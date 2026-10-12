import AppKit
import Foundation

/// Confere no GitHub se há uma versão mais nova. Só avisa e abre a página de download;
/// não baixa nem instala nada sozinho.
final class Updater: ObservableObject {
    struct Release: Equatable {
        let version: String
        let page: URL
    }

    enum State: Equatable {
        case idle, checking, upToDate, available(Release), failed
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastCheck: Date?

    static let repository = "Nicollasarcanjo/OpenNotch"
    private var timer: Timer?

    var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var available: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    init() {
        // Uma checagem logo depois de abrir e depois uma por dia, se a opção estiver ligada.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.automaticCheck() }
        let t = Timer(timeInterval: 24 * 3600, repeats: true) { [weak self] _ in self?.automaticCheck() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func automaticCheck() {
        if Prefs.shared.bool(.updateAutoCheck) { check() }
    }

    func check() {
        guard state != .checking,
              let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else { return }
        state = .checking
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            var result: State = .failed
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                result = .upToDate   // o repositório ainda não tem nenhuma versão publicada
            } else if let data,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let tag = json["tag_name"] as? String,
                      let link = json["html_url"] as? String, let page = URL(string: link) {
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let newer = version.compare(self?.current ?? "0", options: .numeric) == .orderedDescending
                result = newer ? .available(Release(version: version, page: page)) : .upToDate
            }
            DispatchQueue.main.async {
                self?.state = result
                self?.lastCheck = Date()
            }
        }.resume()
    }

    func openDownloadPage() {
        if let page = available?.page { NSWorkspace.shared.open(page) }
    }
}
