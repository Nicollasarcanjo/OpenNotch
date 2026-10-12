import AppKit
import SwiftUI

/// Bandeja de arquivos: solte arquivos no notch para guardar e arraste para fora depois.
final class TrayStore: ObservableObject {
    @Published private(set) var items: [URL] = []
    private let key = "trayPaths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async { self?.add(url) }
            }
        }
    }

    func add(_ url: URL) {
        guard !items.contains(url) else { return }
        items.append(url)
        persist()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    private func persist() { UserDefaults.standard.set(items.map(\.path), forKey: key) }
}

struct TrayView: View {
    @EnvironmentObject var tray: TrayStore

    var body: some View {
        if tray.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 30)).foregroundStyle(.secondary)
                Text("Solte arquivos aqui").font(.headline)
                Text("Eles ficam guardados para você arrastar para outro lugar depois.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .trailing, spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(tray.items, id: \.self) { TrayItemView(url: $0) }
                    }
                }
                Button("Limpar bandeja", action: tray.clear)
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct TrayItemView: View {
    let url: URL
    @EnvironmentObject var tray: TrayStore

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 56, height: 56)
            Text(url.lastPathComponent)
                .font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(width: 84, height: 104)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .onDrag { NSItemProvider(object: url as NSURL) }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Abrir") { NSWorkspace.shared.open(url) }
            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Remover da bandeja") { tray.remove(url) }
        }
        .help(url.path)
    }
}
