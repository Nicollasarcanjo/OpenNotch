import AppKit
import IOKit
import SwiftUI

struct ProcessRow: Identifiable, Equatable {
    let id: pid_t
    var name: String
    var cpu: Double        // 0...100, relativo a todos os núcleos
    var gpu: Double        // 0...100
    var memory: UInt64     // bytes
}

struct AppRow: Identifiable, Equatable {
    let id: String
    var name: String
    var icon: NSImage?
    var instances: [pid_t]      // processos principais (mais de um se o app foi aberto várias vezes)
    var cpu: Double
    var gpu: Double
    var memory: UInt64
    var processes: [ProcessRow] // todos os processos do app, incluindo auxiliares

    static func == (a: AppRow, b: AppRow) -> Bool {
        a.id == b.id && a.name == b.name && a.instances == b.instances && a.cpu == b.cpu
            && a.gpu == b.gpu && a.memory == b.memory && a.processes == b.processes
    }
}

enum AppSort: String, CaseIterable {
    case cpu, gpu, memory, name
}

/// Tempo de GPU acumulado por processo, lido do registro de E/S (clientes do acelerador gráfico).
private enum GPUScan {
    static func accumulatedNanos() -> [pid_t: Double] {
        var result: [pid_t: Double] = [:]
        var accelerators: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"),
                                           &accelerators) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(accelerators) }
        while case let accelerator = IOIteratorNext(accelerators), accelerator != 0 {
            defer { IOObjectRelease(accelerator) }
            var clients: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &clients) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(clients) }
            while case let client = IOIteratorNext(clients), client != 0 {
                defer { IOObjectRelease(client) }
                // "IOUserClientCreator" = "pid 135, WindowServer"
                guard let creator = property(client, "IOUserClientCreator") as? String,
                      let usage = property(client, "AppUsage") as? [[String: Any]], !usage.isEmpty,
                      let pidText = creator.dropFirst(4).split(separator: ",").first,
                      let pid = pid_t(pidText) else { continue }
                let total = usage.reduce(0.0) { $0 + (($1["accumulatedGPUTime"] as? NSNumber)?.doubleValue ?? 0) }
                result[pid, default: 0] += total
            }
        }
        return result
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

/// Gerenciador de apps: agrupa todos os processos de cada app aberto e mede CPU, GPU e memória.
final class AppMonitor: ObservableObject {
    @Published private(set) var apps: [AppRow] = []
    /// Só mede enquanto a aba está visível.
    var active = false { didSet { if active && !oldValue { sample() } } }

    let memoryTotal = ProcessInfo.processInfo.physicalMemory
    private let cores = Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
    private let queue = DispatchQueue(label: "opennotch.apps", qos: .utility)
    private var timer: Timer?
    private var sampling = false
    private var lastCPU: [pid_t: Double] = [:]
    private var lastGPU: [pid_t: Double] = [:]
    private var lastSample: Date?

    private struct AppInfo {
        let key: String
        let pid: pid_t
        let name: String
        let icon: NSImage?
    }

    init() {
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func sample() {
        let prefs = Prefs.shared
        guard active, prefs.bool(.modApps), !sampling else { return }
        sampling = true
        let background = prefs.bool(.appsShowBackground)
        let sort = AppSort(rawValue: prefs.string(.appsSort)) ?? .cpu
        let me = ProcessInfo.processInfo.processIdentifier
        let running: [AppInfo] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier != me, app.processIdentifier > 0,
                  app.activationPolicy == .regular || (background && app.activationPolicy == .accessory) else { return nil }
            // Instâncias do mesmo app (mesmo bundle) caem no mesmo grupo.
            return AppInfo(key: app.bundleIdentifier ?? "pid-\(app.processIdentifier)",
                           pid: app.processIdentifier,
                           name: app.localizedName ?? app.bundleIdentifier ?? "App", icon: app.icon)
        }
        queue.async { [weak self] in
            guard let self else { return }
            let rows = self.measure(running, sort: sort)
            DispatchQueue.main.async {
                self.sampling = false
                if rows != self.apps { self.apps = rows }
            }
        }
    }

    private func measure(_ running: [AppInfo], sort: AppSort) -> [AppRow] {
        let now = Date()
        let elapsed = lastSample.map { max(now.timeIntervalSince($0), 0.2) }
        lastSample = now

        let appOfPid = Dictionary(running.map { ($0.pid, $0.key) }, uniquingKeysWith: { a, _ in a })
        let procs = ProcScan.all()
        let gpuNow = GPUScan.accumulatedNanos()
        var parents: [pid_t: pid_t] = [:]
        for proc in procs { parents[proc.pid] = ProcScan.parent(of: proc.pid) }

        // Dono de um processo: o app responsável por ele, ou o primeiro app subindo na árvore de pais.
        func owner(of pid: pid_t) -> String? {
            var current = pid
            for _ in 0..<12 {
                if let key = appOfPid[current] { return key }
                if let responsible = ProcScan.responsible(for: current), responsible != current,
                   let key = appOfPid[responsible] { return key }
                guard let parent = parents[current], parent > 1, parent != current else { return nil }
                current = parent
            }
            return nil
        }

        var grouped: [String: [ProcessRow]] = [:]
        var cpuNow: [pid_t: Double] = [:]
        for proc in procs {
            guard let key = owner(of: proc.pid), let usage = ProcScan.usage(of: proc.pid) else { continue }
            cpuNow[proc.pid] = usage.cpuSeconds
            var cpu = 0.0, gpu = 0.0
            if let elapsed {
                if let before = lastCPU[proc.pid] {
                    cpu = max(usage.cpuSeconds - before, 0) / elapsed * 100 / cores
                }
                if let after = gpuNow[proc.pid], let before = lastGPU[proc.pid] {
                    gpu = min(max(after - before, 0) / (elapsed * 1_000_000_000) * 100, 100)
                }
            }
            grouped[key, default: []].append(ProcessRow(id: proc.pid,
                                                         name: URL(fileURLWithPath: proc.path).lastPathComponent,
                                                         cpu: min(cpu, 100), gpu: gpu, memory: usage.memory))
        }
        lastCPU = cpuNow
        lastGPU = gpuNow

        var rows: [AppRow] = []
        var seen = Set<String>()
        for app in running where seen.insert(app.key).inserted {
            let instances = running.filter { $0.key == app.key }.map(\.pid)
            var processes = grouped[app.key] ?? []
            // Principal(is) primeiro, depois os auxiliares por uso de CPU.
            processes.sort {
                let a = instances.contains($0.id), b = instances.contains($1.id)
                return a != b ? a : $0.cpu > $1.cpu
            }
            rows.append(AppRow(id: app.key, name: app.name, icon: app.icon, instances: instances,
                               cpu: min(processes.reduce(0) { $0 + $1.cpu }, 100),
                               gpu: min(processes.reduce(0) { $0 + $1.gpu }, 100),
                               memory: processes.reduce(0) { $0 + $1.memory },
                               processes: processes))
        }
        switch sort {
        case .cpu: rows.sort { $0.cpu > $1.cpu }
        case .gpu: rows.sort { ($0.gpu, $0.cpu) > ($1.gpu, $1.cpu) }
        case .memory: rows.sort { $0.memory > $1.memory }
        case .name: rows.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return rows
    }

    /// Fecha o app inteiro (todas as instâncias). `force` encerra sem dar chance de salvar.
    func quit(_ app: AppRow, force: Bool = false) {
        for pid in app.instances {
            guard let running = NSRunningApplication(processIdentifier: pid) else { continue }
            if force { running.forceTerminate() } else { running.terminate() }
        }
    }

    func activate(_ app: AppRow) {
        guard let pid = app.instances.first else { return }
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    /// Encerra um único processo do app (ex.: uma aba ou auxiliar travado).
    func kill(_ process: ProcessRow) {
        Darwin.kill(process.id, SIGTERM)
    }
}

struct AppsView: View {
    @EnvironmentObject var monitor: AppMonitor
    @EnvironmentObject var prefs: Prefs
    @State private var expanded = Set<String>()

    private var sort: AppSort { AppSort(rawValue: prefs.string(.appsSort)) ?? .cpu }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 0) {
                header("App", .name).frame(maxWidth: .infinity, alignment: .leading)
                header("CPU", .cpu).frame(width: Metrics.column, alignment: .trailing)
                header("GPU", .gpu).frame(width: Metrics.column, alignment: .trailing)
                header("RAM", .memory).frame(width: Metrics.column, alignment: .trailing)
                Color.clear.frame(width: Metrics.action, height: 1)
            }
            .padding(.horizontal, 9)

            if monitor.apps.isEmpty {
                Text("Medindo…").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(monitor.apps) { app in
                            AppRowView(app: app, memoryTotal: monitor.memoryTotal,
                                       isExpanded: expanded.contains(app.id)) {
                                if !expanded.insert(app.id).inserted { expanded.remove(app.id) }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { monitor.active = true }
        .onDisappear { monitor.active = false }
    }

    private func header(_ title: String, _ key: AppSort) -> some View {
        Button { prefs.set(key.rawValue, for: .appsSort) } label: {
            HStack(spacing: 2) {
                Text(title)
                if sort == key { Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)) }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(sort == key ? Color.white : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Ordenar por \(title)")
    }
}

private enum Metrics {
    static let column: CGFloat = 58
    static let action: CGFloat = 26
}

private struct AppRowView: View {
    let app: AppRow
    let memoryTotal: UInt64
    let isExpanded: Bool
    let toggle: () -> Void
    @EnvironmentObject var monitor: AppMonitor

    private var hasChildren: Bool { app.processes.count > 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .opacity(hasChildren ? 0.7 : 0)
                        .frame(width: 8)
                    if let icon = app.icon {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    }
                    Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if hasChildren {
                        Text("\(app.processes.count)")
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.white.opacity(0.14), in: Capsule())
                            .help(app.instances.count > 1
                                  ? "\(app.instances.count) instâncias, \(app.processes.count) processos"
                                  : "\(app.processes.count) processos")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { if hasChildren { toggle() } }

                MetricCells(cpu: app.cpu, gpu: app.gpu, memory: app.memory, memoryTotal: memoryTotal)
                Button { monitor.quit(app) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: Metrics.action, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Fechar \(app.name) (todos os processos)")
            }
            .padding(.horizontal, 9).padding(.vertical, 5)

            if isExpanded {
                ForEach(app.processes) { process in
                    HStack(spacing: 0) {
                        Text(process.name + (app.instances.contains(process.id) ? "  (principal)" : ""))
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            .padding(.leading, 40)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        MetricCells(cpu: process.cpu, gpu: process.gpu, memory: process.memory,
                                    memoryTotal: memoryTotal, dimmed: true)
                        Button { monitor.kill(process) } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(width: Metrics.action, alignment: .trailing)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Encerrar só este processo (PID \(process.id))")
                    }
                    .padding(.horizontal, 9).padding(.vertical, 3)
                }
            }
        }
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .contextMenu {
            Button("Mostrar \(app.name)") { monitor.activate(app) }
            Button("Fechar") { monitor.quit(app) }
            Button("Forçar encerramento") { monitor.quit(app, force: true) }
        }
    }
}

private struct MetricCells: View {
    let cpu: Double
    let gpu: Double
    let memory: UInt64
    let memoryTotal: UInt64
    var dimmed = false

    var body: some View {
        let ram = Double(memory) / Double(max(memoryTotal, 1)) * 100
        cell(cpu, help: "CPU: parte de todos os núcleos")
        cell(gpu, help: "GPU")
        cell(ram, help: "Memória: " + ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory))
    }

    private func cell(_ value: Double, help: String) -> some View {
        Text(value < 0.05 ? "0%" : value < 10 ? String(format: "%.1f%%", value) : "\(Int(value.rounded()))%")
            .font(.system(size: dimmed ? 10 : 11, weight: dimmed ? .regular : .medium).monospacedDigit())
            .foregroundStyle(color(value).opacity(dimmed ? 0.8 : 1))
            .frame(width: Metrics.column, alignment: .trailing)
            .help(help)
    }

    private func color(_ value: Double) -> Color {
        value >= 60 ? .red : value >= 25 ? .orange : value < 0.05 ? .secondary : .white
    }
}
