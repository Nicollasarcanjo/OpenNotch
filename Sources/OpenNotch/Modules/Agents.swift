import AppKit
import SwiftUI

// MARK: - Modelo

struct AgentSession: Identifiable, Equatable {
    let id: String
    var title: String
    var project: String
    var working: Bool
    /// Texto de estado quando não está trabalhando (ex.: "ocioso", "aguardando você").
    var idleText = L("ocioso")
    var usage: Double?          // 0...1
    var usageLabel = ""         // o que a porcentagem mede: "contexto", "CPU"
    var updated = Date.distantPast
}

struct AgentLimit: Equatable {
    let label: String
    let percent: Double         // 0...100
}

struct AgentProvider: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    var limits: [AgentLimit] = []
    var sessions: [AgentSession] = []
    /// Detecção por heurística (atividade de arquivos ou CPU), não pelo estado real da ferramenta.
    var approximate = false
}

struct AgentFinish: Equatable {
    let provider: String
    let title: String
    let project: String
}

// MARK: - Monitor

/// Acompanha sessões de agentes de IA lendo os arquivos de estado que cada ferramenta
/// grava em disco. Somente leitura: não fala com nenhuma API nem toca em credenciais.
final class AgentMonitor: ObservableObject {
    @Published private(set) var providers: [AgentProvider] = []
    var onFinish: ((AgentFinish) -> Void)?

    var workingCount: Int { providers.reduce(0) { $0 + $1.sessions.filter(\.working).count } }

    private let queue = DispatchQueue(label: "opennotch.agents", qos: .utility)
    private var timer: Timer?
    private var scanning = false
    private var lastWorking: [String: AgentFinish] = [:]   // sessões que estavam trabalhando no último scan
    private var firstScan = true

    private let claude = ClaudeScanner()
    private let codex = CodexScanner()
    private let antigravity = AntigravityScanner()
    private let custom = CustomScanner()

    init() {
        if Demo.enabled {
            providers = Demo.providers
            return
        }
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.scan() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        scan()
    }

    private func scan() {
        let prefs = Prefs.shared
        guard prefs.bool(.modAgents) else {
            if !providers.isEmpty { providers = [] }
            lastWorking = [:]
            return
        }
        guard !scanning else { return }
        scanning = true
        let useClaude = prefs.bool(.agentsClaude), useCodex = prefs.bool(.agentsCodex)
        let useAntigravity = prefs.bool(.agentsAntigravity)
        let claudeWindow = Double(max(prefs.int(.agentsClaudeWindow), 1))
        let customAgents = prefs.customAgents
        let hideIdleAfter = TimeInterval(prefs.int(.agentsHideIdleHours)) * 3600

        queue.async { [weak self] in
            guard let self else { return }
            var result: [AgentProvider] = []
            if useClaude { result.append(self.claude.scan(contextWindow: claudeWindow)) }
            if useCodex { result.append(self.codex.scan()) }
            if useAntigravity { result.append(contentsOf: self.antigravity.scan()) }
            result.append(contentsOf: self.custom.scan(customAgents))
            let now = Date()
            for i in result.indices {
                if hideIdleAfter > 0 {
                    // Sessões abertas mas paradas há muito tempo só poluem a lista.
                    result[i].sessions.removeAll { !$0.working && now.timeIntervalSince($0.updated) > hideIdleAfter }
                }
                result[i].sessions.sort { ($0.working ? 1 : 0, $0.updated) > ($1.working ? 1 : 0, $1.updated) }
            }
            DispatchQueue.main.async { self.publish(result) }
        }
    }

    private func publish(_ result: [AgentProvider]) {
        scanning = false
        if result != providers { providers = result }

        var nowWorking: [String: AgentFinish] = [:]
        var stillPresent = Set<String>()
        for provider in result {
            for session in provider.sessions {
                let key = provider.id + "|" + session.id
                stillPresent.insert(key)
                if session.working {
                    nowWorking[key] = AgentFinish(provider: provider.name, title: session.title,
                                                  project: session.project)
                }
            }
        }
        if !firstScan {
            // Terminou = estava trabalhando, continua existindo e agora parou.
            for (key, finish) in lastWorking where nowWorking[key] == nil && stillPresent.contains(key) {
                onFinish?(finish)
            }
        }
        firstScan = false
        lastWorking = nowWorking
    }
}

// MARK: - Leitura de arquivos

private enum FileTail {
    /// Últimas linhas completas de um arquivo de texto, limitado a `maxBytes`.
    static func lines(of url: URL, maxBytes: UInt64) -> [Substring] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > maxBytes ? size - maxBytes : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8)
                ?? String(data: data.dropFirst(3), encoding: .utf8) else { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }   // primeira linha pode estar cortada
        return lines
    }

    /// Primeira linha do arquivo (até `maxBytes`).
    static func firstLine(of url: URL, maxBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var data = Data()
        while data.count < maxBytes, let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            if let newline = chunk.firstIndex(of: 0x0A) {
                data.append(chunk[chunk.startIndex..<newline])
                return data
            }
            data.append(chunk)
        }
        return nil
    }

    static func json(_ line: Substring) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

private func mtime(_ url: URL) -> Date? {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
}

private func projectName(_ cwd: String) -> String {
    cwd.isEmpty ? "" : URL(fileURLWithPath: cwd).lastPathComponent
}

// MARK: - Claude Code

/// Lê ~/.claude/sessions/<pid>.json (uma por sessão aberta) e o fim da transcrição
/// de cada sessão para estimar o uso da janela de contexto.
private final class ClaudeScanner {
    private let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    private var transcriptPaths: [String: URL] = [:]
    private var contextCache: [String: (mtime: Date, tokens: Double)] = [:]

    func scan(contextWindow: Double) -> AgentProvider {
        var provider = AgentProvider(id: "claude", name: "Claude Code", icon: "sparkle")
        let dir = home.appendingPathComponent("sessions")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let pid = info["pid"] as? Int, ProcScan.isAlive(pid_t(pid)),
                  let sessionID = info["sessionId"] as? String else { continue }
            let cwd = info["cwd"] as? String ?? ""
            let status = info["status"] as? String ?? "idle"
            let updatedMs = (info["statusUpdatedAt"] as? Double) ?? (info["updatedAt"] as? Double) ?? 0
            var session = AgentSession(id: sessionID,
                                       title: (info["name"] as? String) ?? projectName(cwd),
                                       project: projectName(cwd),
                                       working: status == "busy")
            session.idleText = status == "idle" ? L("ocioso") : status
            session.updated = Date(timeIntervalSince1970: updatedMs / 1000)
            if let tokens = contextTokens(sessionID: sessionID) {
                // Sem informação local sobre o tamanho da janela: usa o configurado e,
                // se a sessão já passou dele, assume a janela de 1M.
                let window = tokens > contextWindow ? max(1_000_000, tokens) : contextWindow
                session.usage = min(tokens / window, 1)
                session.usageLabel = L("contexto")
            }
            provider.sessions.append(session)
        }
        return provider
    }

    private func transcript(for sessionID: String) -> URL? {
        if let url = transcriptPaths[sessionID] { return url }
        let projects = home.appendingPathComponent("projects")
        let dirs = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        for dir in dirs {
            let candidate = dir.appendingPathComponent(sessionID + ".jsonl")
            if FileManager.default.fileExists(atPath: candidate.path) {
                transcriptPaths[sessionID] = candidate
                return candidate
            }
        }
        return nil
    }

    private func contextTokens(sessionID: String) -> Double? {
        guard let url = transcript(for: sessionID), let modified = mtime(url) else { return nil }
        if let cached = contextCache[sessionID], cached.mtime == modified { return cached.tokens }
        for line in FileTail.lines(of: url, maxBytes: 512 * 1024).reversed() where line.contains("\"usage\"") {
            guard let entry = FileTail.json(line), entry["type"] as? String == "assistant",
                  entry["isSidechain"] as? Bool != true,
                  let usage = (entry["message"] as? [String: Any])?["usage"] as? [String: Any] else { continue }
            let tokens = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
                .reduce(0.0) { $0 + ((usage[$1] as? Double) ?? 0) }
            contextCache[sessionID] = (modified, tokens)
            return tokens
        }
        return contextCache[sessionID]?.tokens
    }
}

// MARK: - Codex

/// Lê os arquivos de sessão em ~/.codex/sessions. Cada um registra início/fim de tarefa,
/// uso de tokens e os limites do plano (janela de 5 h e semanal).
private final class CodexScanner {
    private struct Parsed {
        var mtime: Date
        var taskRunning = false
        var contextPercent: Double?
        var limits: [AgentLimit] = []
    }

    private let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    private var files: [URL] = []
    private var lastListing = Date.distantPast
    private var parsed: [URL: Parsed] = [:]
    private var cwds: [URL: String] = [:]
    private var names: [String: String] = [:]
    private var namesMtime: Date?

    func scan() -> AgentProvider {
        var provider = AgentProvider(id: "codex", name: "Codex", icon: "chevron.left.forwardslash.chevron.right")
        let now = Date()
        if now.timeIntervalSince(lastListing) > 30 {
            lastListing = now
            files = listFiles()
        }
        loadNames()

        var newest: (date: Date, limits: [AgentLimit])?
        for file in files {
            guard let modified = mtime(file), now.timeIntervalSince(modified) < 3 * 3600 else { continue }
            let info = parse(file, modified: modified)
            if !info.limits.isEmpty, newest == nil || modified > newest!.date { newest = (modified, info.limits) }

            let id = sessionID(file)
            let cwd = cwd(of: file)
            // Sem atividade há muito tempo com tarefa "aberta" = sessão interrompida, não trabalhando.
            let working = info.taskRunning && now.timeIntervalSince(modified) < 20 * 60
            var session = AgentSession(id: id, title: names[id] ?? projectName(cwd),
                                       project: projectName(cwd), working: working)
            session.updated = modified
            if let percent = info.contextPercent {
                session.usage = percent
                session.usageLabel = L("contexto")
            }
            provider.sessions.append(session)
        }
        provider.limits = newest?.limits ?? []
        return provider
    }

    private func listFiles() -> [URL] {
        let root = home.appendingPathComponent("sessions")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }

    /// O id da sessão são os 36 caracteres finais do nome do arquivo.
    private func sessionID(_ file: URL) -> String {
        String(file.deletingPathExtension().lastPathComponent.suffix(36))
    }

    private func loadNames() {
        let index = home.appendingPathComponent("session_index.jsonl")
        guard let modified = mtime(index), modified != namesMtime else { return }
        namesMtime = modified
        for line in FileTail.lines(of: index, maxBytes: 2 * 1024 * 1024) {
            if let entry = FileTail.json(line), let id = entry["id"] as? String,
               let name = entry["thread_name"] as? String {
                names[id] = name
            }
        }
    }

    private func cwd(of file: URL) -> String {
        if let known = cwds[file] { return known }
        var cwd = ""
        if let data = FileTail.firstLine(of: file, maxBytes: 4 * 1024 * 1024),
           let entry = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let payload = entry["payload"] as? [String: Any] {
            cwd = payload["cwd"] as? String ?? ""
        }
        cwds[file] = cwd
        return cwd
    }

    private func parse(_ file: URL, modified: Date) -> Parsed {
        if let cached = parsed[file], cached.mtime == modified { return cached }
        var info = Parsed(mtime: modified)
        var foundTask = false, foundTokens = false
        for line in FileTail.lines(of: file, maxBytes: 768 * 1024).reversed() {
            if foundTask && foundTokens { break }
            let isTask = !foundTask && (line.contains("\"task_started\"") || line.contains("\"task_complete\"")
                                        || line.contains("\"turn_aborted\""))
            let isTokens = !foundTokens && line.contains("\"token_count\"")
            guard isTask || isTokens, let entry = FileTail.json(line),
                  entry["type"] as? String == "event_msg",
                  let payload = entry["payload"] as? [String: Any],
                  let type = payload["type"] as? String else { continue }
            switch type {
            case "task_started" where !foundTask:
                info.taskRunning = true
                foundTask = true
            case "task_complete" where !foundTask, "turn_aborted" where !foundTask:
                foundTask = true
            case "token_count" where !foundTokens:
                foundTokens = true
                if let usage = payload["info"] as? [String: Any],
                   let last = usage["last_token_usage"] as? [String: Any],
                   let total = last["total_tokens"] as? Double,
                   let window = usage["model_context_window"] as? Double, window > 0 {
                    info.contextPercent = min(total / window, 1)
                }
                if let limits = payload["rate_limits"] as? [String: Any] {
                    info.limits = ["primary", "secondary"].compactMap { Self.limit(limits[$0]) }
                }
            default:
                break
            }
        }
        parsed[file] = info
        return info
    }

    private static func limit(_ raw: Any?) -> AgentLimit? {
        guard let dict = raw as? [String: Any], let used = dict["used_percent"] as? Double else { return nil }
        let minutes = dict["window_minutes"] as? Double ?? 0
        let label: String
        switch minutes {
        case 10080: label = L("semana")
        case let m where m >= 1440: label = L("%lld dias", Int(m / 1440))
        case let m where m >= 60: label = "\(Int(m / 60)) h"
        default: label = L("limite")
        }
        // Se a janela já virou desde a última leitura, o uso voltou a zero.
        if let resets = dict["resets_at"] as? Double, resets < Date().timeIntervalSince1970 {
            return AgentLimit(label: label, percent: 0)
        }
        return AgentLimit(label: label, percent: used)
    }
}

// MARK: - Antigravity

/// O Antigravity não expõe estado legível, então a detecção é aproximada:
/// "trabalhando" enquanto os arquivos de conversa estão sendo gravados.
private final class AntigravityScanner {
    private struct Variant {
        let id: String
        let name: String
        let folder: String
    }

    private let variants = [
        Variant(id: "antigravity", name: "Antigravity", folder: "antigravity"),
        Variant(id: "antigravity-ide", name: "Antigravity IDE", folder: "antigravity-ide"),
    ]
    private let activeWindow: TimeInterval = 25

    func scan() -> [AgentProvider] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.localizedName))
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini")
        return variants.compactMap { variant in
            guard running.contains(variant.name) else { return nil }
            var provider = AgentProvider(id: variant.id, name: variant.name, icon: "atom", approximate: true)
            let root = base.appendingPathComponent(variant.folder)
            let latest = ["conversations", "brain"].compactMap { newestChange(in: root.appendingPathComponent($0)) }.max()
            var session = AgentSession(id: variant.id, title: L("Agente"), project: "",
                                       working: latest.map { Date().timeIntervalSince($0) < activeWindow } ?? false)
            session.updated = latest ?? .distantPast
            provider.sessions = [session]
            return provider
        }
    }

    private func newestChange(in dir: URL) -> Date? {
        guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                                                          options: [.skipsPackageDescendants]) else { return nil }
        var newest: Date?
        var visited = 0
        for case let url as URL in walker {
            visited += 1
            if visited > 2000 { break }
            if let date = mtime(url), newest == nil || date > newest! { newest = date }
        }
        return newest
    }
}

// MARK: - Ferramentas personalizadas

/// Ferramentas cadastradas pelo usuário: agrupa os processos pelo nome e pela pasta
/// em que estão rodando, e usa o consumo de CPU como sinal de atividade.
private final class CustomScanner {
    private var lastCPU: [pid_t: Double] = [:]
    private var lastSample = Date()
    private var busySince: [String: Date] = [:]

    private let busyThreshold = 8.0     // % de CPU
    private let minBusy: TimeInterval = 9

    func scan(_ agents: [CustomAgent]) -> [AgentProvider] {
        let valid = agents.filter { !$0.match.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !valid.isEmpty else {
            lastCPU = [:]
            return []
        }
        let now = Date()
        let elapsed = max(now.timeIntervalSince(lastSample), 0.5)
        lastSample = now
        let procs = ProcScan.all()
        var currentCPU: [pid_t: Double] = [:]
        var providers: [AgentProvider] = []
        var liveKeys = Set<String>()

        for agent in valid {
            let needle = agent.match.lowercased()
            var byFolder: [String: Double] = [:]
            for proc in procs where proc.path.lowercased().contains(needle) {
                guard let cpu = ProcScan.cpuSeconds(of: proc.pid) else { continue }
                currentCPU[proc.pid] = cpu
                let percent = lastCPU[proc.pid].map { max(cpu - $0, 0) / elapsed * 100 } ?? 0
                let cwd = ProcScan.cwd(of: proc.pid) ?? ""
                byFolder[cwd == "/" ? "" : cwd, default: 0] += percent
            }
            guard !byFolder.isEmpty else { continue }
            var provider = AgentProvider(id: "custom-" + agent.id.uuidString,
                                         name: agent.name.isEmpty ? agent.match : agent.name,
                                         icon: "terminal", approximate: true)
            for (cwd, percent) in byFolder {
                let key = provider.id + "|" + cwd
                liveKeys.insert(key)
                if percent >= busyThreshold {
                    if busySince[key] == nil { busySince[key] = now }
                } else {
                    busySince[key] = nil
                }
                // Só conta como "trabalhando" depois de alguns segundos seguidos de CPU alta.
                let working = busySince[key].map { now.timeIntervalSince($0) >= minBusy } ?? false
                var session = AgentSession(id: cwd, title: cwd.isEmpty ? provider.name : projectName(cwd),
                                           project: "", working: working)
                session.usage = min(percent / 100, 1)
                session.usageLabel = "CPU"
                session.updated = now
                provider.sessions.append(session)
            }
            providers.append(provider)
        }
        lastCPU = currentCPU
        busySince = busySince.filter { liveKeys.contains($0.key) }
        return providers
    }
}

// MARK: - Views

struct AgentsView: View {
    @EnvironmentObject var agents: AgentMonitor
    @EnvironmentObject var model: NotchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let banner = model.banner {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(banner).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.green.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            }
            if agents.providers.allSatisfy(\.sessions.isEmpty) {
                VStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("Nenhum agente rodando").font(.headline)
                    Text("Sessões do Claude Code, Codex e Antigravity aparecem aqui.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(agents.providers.filter { !$0.sessions.isEmpty }) { provider in
                            ProviderSection(provider: provider)
                        }
                    }
                }
            }
        }
    }
}

private struct ProviderSection: View {
    let provider: AgentProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: provider.icon).font(.system(size: 10, weight: .semibold))
                Text(provider.name).font(.system(size: 11, weight: .semibold))
                if provider.approximate {
                    Text("aprox.").font(.system(size: 9)).foregroundStyle(.tertiary)
                        .help("Detecção aproximada, por atividade de arquivos ou CPU")
                }
                Spacer(minLength: 0)
                ForEach(provider.limits, id: \.label) { limit in
                    HStack(spacing: 4) {
                        Text(limit.label).foregroundStyle(.secondary)
                        UsageBar(value: limit.percent / 100).frame(width: 34)
                        Text("\(Int(limit.percent.rounded()))%").monospacedDigit()
                    }
                    .font(.system(size: 10))
                    .help("Uso do limite do plano (\(limit.label))")
                }
            }
            .foregroundStyle(.white.opacity(0.85))
            ForEach(provider.sessions) { AgentRow(session: $0) }
        }
    }
}

private struct AgentRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(working: session.working)
            Text(session.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            if !session.project.isEmpty, session.project != session.title {
                Text(session.project).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let usage = session.usage {
                Text(session.usageLabel).font(.system(size: 9)).foregroundStyle(.tertiary)
                UsageBar(value: usage).frame(width: 46)
                Text("\(Int((usage * 100).rounded()))%")
                    .font(.system(size: 10).monospacedDigit()).frame(width: 30, alignment: .trailing)
            }
            Text(session.working ? L("trabalhando") : session.idleText)
                .font(.system(size: 10))
                .foregroundStyle(session.working ? Color.orange : Color.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct UsageBar: View {
    let value: Double
    /// Cor fixa; sem ela a barra vai de verde a vermelho conforme enche.
    var tint: Color?

    private var color: Color { tint ?? (value >= 0.9 ? .red : value >= 0.7 ? .orange : .green) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(color).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
    }
}

struct StatusDot: View {
    let working: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(working ? Color.orange : Color.white.opacity(0.3))
            .frame(width: 7, height: 7)
            .opacity(working && pulse ? 0.35 : 1)
            .animation(working ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: pulse)
            .onAppear { pulse = true }
    }
}
