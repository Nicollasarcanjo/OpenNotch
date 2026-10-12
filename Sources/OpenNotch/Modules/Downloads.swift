import AppKit
import SwiftUI

struct DownloadItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    var url: URL?
    var fraction: Double        // 0...1
    var bytesDone: Int64
    var bytesTotal: Int64
    var finished = false
}

/// Acompanha os downloads em andamento na pasta Downloads. Usa o progresso que Safari,
/// Chrome, Brave e outros apps publicam para o sistema (o mesmo que o Finder mostra no arquivo).
final class DownloadsMonitor: ObservableObject {
    @Published private(set) var items: [DownloadItem] = []
    var onFinished: ((DownloadItem) -> Void)?

    private var live: [(id: UUID, progress: Progress)] = []
    private var recent: [DownloadItem] = []
    private var subscriber: Any?
    private var timer: Timer?
    private var prefsObserver: Any?

    /// Média do que está baixando agora, ou nil se não há nada em andamento.
    var activeFraction: Double? {
        let active = items.filter { !$0.finished }
        return active.isEmpty ? nil : active.reduce(0) { $0 + $1.fraction } / Double(active.count)
    }

    init() {
        if Demo.enabled {
            items = Demo.downloads
            return
        }
        prefsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            self?.syncEnabled()
        }
        syncEnabled()
    }

    private func syncEnabled() {
        let wanted = Prefs.shared.bool(.modDownloads)
        if wanted, subscriber == nil { start() } else if !wanted, subscriber != nil { stop() }
    }

    private func start() {
        guard let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        subscriber = Progress.addSubscriber(forFileURL: folder) { [weak self] progress in
            let id = UUID()
            DispatchQueue.main.async { self?.live.append((id, progress)) }
            return { DispatchQueue.main.async { self?.ended(id) } }
        }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stop() {
        if let subscriber { Progress.removeSubscriber(subscriber) }
        subscriber = nil
        timer?.invalidate()
        timer = nil
        live = []
        recent = []
        items = []
    }

    private func item(_ id: UUID, _ progress: Progress) -> DownloadItem {
        let url = progress.fileURL
        // Chrome e Brave baixam para "arquivo.ext.crdownload"; mostra o nome final.
        var name = url?.lastPathComponent ?? L("Download")
        for suffix in [".crdownload", ".download", ".part"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return DownloadItem(id: id, name: name, url: url, fraction: min(max(progress.fractionCompleted, 0), 1),
                            bytesDone: progress.completedUnitCount, bytesTotal: progress.totalUnitCount)
    }

    private func ended(_ id: UUID) {
        guard let index = live.firstIndex(where: { $0.id == id }) else { return }
        let (_, progress) = live.remove(at: index)
        guard progress.fileOperationKind == .downloading else { return }
        var done = item(id, progress)
        // Encerrou perto do fim = terminou; antes disso foi cancelado e não fica na lista.
        guard !progress.isCancelled, done.fraction >= 0.98 || progress.isFinished else {
            refresh()
            return
        }
        done.finished = true
        done.fraction = 1
        recent.insert(done, at: 0)
        if recent.count > 5 { recent.removeLast(recent.count - 5) }
        refresh()
        onFinished?(done)
    }

    private func refresh() {
        let active = live.filter { $0.progress.fileOperationKind == .downloading }.map { item($0.id, $0.progress) }
        let combined = active + recent
        if combined != items { items = combined }
    }

    func clearFinished() {
        recent = []
        refresh()
    }

    func reveal(_ item: DownloadItem) {
        guard let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        let file = folder.appendingPathComponent(item.name)
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            NSWorkspace.shared.open(folder)
        }
    }
}

struct DownloadsPanel: View {
    @EnvironmentObject var downloads: DownloadsMonitor

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Downloads").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 0)
                if downloads.items.contains(where: \.finished) {
                    Button("Limpar", action: downloads.clearFinished)
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .frame(height: 18)
            if downloads.items.isEmpty {
                Text("Nenhum download em andamento").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(downloads.items) { DownloadRow(item: $0) }
                    }
                }
            }
        }
    }
}

private struct DownloadRow: View {
    let item: DownloadItem
    @EnvironmentObject var downloads: DownloadsMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: item.finished ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 11)).foregroundStyle(item.finished ? Color.green : Color.blue)
                Text(item.name).font(.system(size: 12)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(detail).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
            }
            if !item.finished {
                UsageBar(value: item.fraction, tint: .blue)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { downloads.reveal(item) }
        .help("Clique para mostrar no Finder")
    }

    private var detail: String {
        if item.finished { return L("Concluído") }
        let percent = "\(Int((item.fraction * 100).rounded()))%"
        guard item.bytesTotal > 0 else { return percent }
        return percent + " · " + ByteCountFormatter.string(fromByteCount: item.bytesTotal, countStyle: .file)
    }
}
