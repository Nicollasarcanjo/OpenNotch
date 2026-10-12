using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Windows.Threading;

namespace OpenNotch;

public sealed record AgentLimit(string Label, double Percent);

public sealed class AgentSession
{
    public string Id { get; init; } = "";
    public string Title { get; init; } = "";
    public string Project { get; init; } = "";
    public bool Working { get; init; }
    public double? Usage { get; init; }          // 0...1
    public DateTime Updated { get; init; }

    public string StateText => Working ? Loc.T("trabalhando") : Loc.T("ocioso");
    public string UsageText => Usage is { } usage ? $"{Math.Round(usage * 100)}%" : "";
    public double UsageValue => Usage ?? 0;
    public bool HasUsage => Usage != null;
}

public sealed class AgentProvider
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public List<AgentLimit> Limits { get; init; } = [];
    public List<AgentSession> Sessions { get; init; } = [];
    public string LimitsText => string.Join("   ", Limits.Select(l => $"{l.Label} {Math.Round(l.Percent)}%"));
}

public sealed record AgentFinish(string Provider, string Title, string Project);

/// <summary>
/// Acompanha sessões de agentes de IA lendo os arquivos de estado que cada ferramenta grava em disco.
/// Mesma lógica da versão macOS (Agents.swift): somente leitura, sem rede e sem credenciais.
/// </summary>
public sealed class AgentMonitor : Observable
{
    public ObservableCollection<AgentProvider> Providers { get; } = [];
    public event Action<AgentFinish>? Finished;

    private int _workingCount;
    public int WorkingCount { get => _workingCount; private set => Set(ref _workingCount, value); }

    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(3) };
    private readonly ClaudeScanner _claude = new();
    private readonly CodexScanner _codex = new();
    private Dictionary<string, AgentFinish> _lastWorking = [];
    private bool _scanning, _first = true;

    public AgentMonitor()
    {
        _timer.Tick += (_, _) => Scan();
        _timer.Start();
        Scan();
    }

    private async void Scan()
    {
        var settings = Settings.Current;
        if (!settings.ModAgents)
        {
            Providers.Clear();
            WorkingCount = 0;
            return;
        }
        if (_scanning) return;
        _scanning = true;
        var useClaude = settings.AgentsClaude;
        var useCodex = settings.AgentsCodex;
        var window = Math.Max(settings.AgentsClaudeWindow, 1);
        var hideAfter = TimeSpan.FromHours(settings.AgentsHideIdleHours);

        List<AgentProvider> result;
        try
        {
            result = await Task.Run(() =>
            {
                var list = new List<AgentProvider>();
                if (useClaude) list.Add(_claude.Scan(window));
                if (useCodex) list.Add(_codex.Scan());
                return list.Select(provider => new AgentProvider
                {
                    Id = provider.Id,
                    Name = provider.Name,
                    Limits = provider.Limits,
                    // Sessões abertas mas paradas há muito tempo só poluem a lista.
                    Sessions = provider.Sessions
                        .Where(s => s.Working || hideAfter <= TimeSpan.Zero || DateTime.Now - s.Updated <= hideAfter)
                        .OrderByDescending(s => s.Working).ThenByDescending(s => s.Updated).ToList(),
                }).Where(provider => provider.Sessions.Count > 0).ToList();
            });
        }
        catch
        {
            _scanning = false;
            return;
        }
        _scanning = false;

        Providers.Clear();
        foreach (var provider in result) Providers.Add(provider);

        var nowWorking = new Dictionary<string, AgentFinish>();
        var present = new HashSet<string>();
        foreach (var provider in result)
        {
            foreach (var session in provider.Sessions)
            {
                var key = provider.Id + "|" + session.Id;
                present.Add(key);
                if (session.Working) nowWorking[key] = new AgentFinish(provider.Name, session.Title, session.Project);
            }
        }
        WorkingCount = nowWorking.Count;
        if (!_first)
        {
            // Terminou = estava trabalhando, continua existindo e agora parou.
            foreach (var (key, finish) in _lastWorking)
            {
                if (!nowWorking.ContainsKey(key) && present.Contains(key)) Finished?.Invoke(finish);
            }
        }
        _first = false;
        _lastWorking = nowWorking;
    }
}

internal static class FileTail
{
    /// <summary>Últimas linhas completas de um arquivo de texto, limitado a <paramref name="maxBytes"/>.</summary>
    public static List<string> Lines(string path, int maxBytes)
    {
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            var start = Math.Max(0, stream.Length - maxBytes);
            stream.Seek(start, SeekOrigin.Begin);
            using var reader = new StreamReader(stream, Encoding.UTF8);
            var lines = reader.ReadToEnd().Split('\n', StringSplitOptions.RemoveEmptyEntries).ToList();
            if (start > 0 && lines.Count > 0) lines.RemoveAt(0);   // primeira linha pode estar cortada
            return lines;
        }
        catch
        {
            return [];
        }
    }

    public static string? FirstLine(string path)
    {
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var reader = new StreamReader(stream, Encoding.UTF8);
            return reader.ReadLine();
        }
        catch
        {
            return null;
        }
    }

    public static JsonElement? Json(string line)
    {
        try { return JsonDocument.Parse(line).RootElement; }
        catch { return null; }
    }

    public static string Str(this JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value)
            && value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : "";

    public static double? Num(this JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value)
            && value.ValueKind == JsonValueKind.Number ? value.GetDouble() : null;

    public static JsonElement? Obj(this JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value)
            && value.ValueKind == JsonValueKind.Object ? value : null;

    public static string ProjectName(string cwd) =>
        string.IsNullOrEmpty(cwd) ? "" : Path.GetFileName(cwd.TrimEnd('\\', '/'));
}

/// <summary>Lê ~/.claude/sessions/&lt;pid&gt;.json e o fim da transcrição de cada sessão.</summary>
internal sealed class ClaudeScanner
{
    private readonly string _home = Path.Combine(Paths.Home, ".claude");
    private readonly Dictionary<string, string> _transcripts = [];
    private readonly Dictionary<string, (DateTime mtime, double tokens)> _context = [];

    public AgentProvider Scan(double contextWindow)
    {
        var sessions = new List<AgentSession>();
        var dir = Path.Combine(_home, "sessions");
        if (Directory.Exists(dir))
        {
            foreach (var file in Directory.EnumerateFiles(dir, "*.json"))
            {
                JsonElement? info;
                try { info = FileTail.Json(File.ReadAllText(file)); }
                catch { continue; }
                if (info is not { } json || json.Num("pid") is not { } pid || !IsAlive((int)pid)) continue;
                var id = json.Str("sessionId");
                if (id.Length == 0) continue;
                var cwd = json.Str("cwd");
                var name = json.Str("name");
                var updated = json.Num("statusUpdatedAt") ?? json.Num("updatedAt") ?? 0;
                double? usage = null;
                if (ContextTokens(id) is { } tokens)
                {
                    // Sem informação local sobre o tamanho da janela: usa o configurado e,
                    // se a sessão já passou dele, assume a janela de 1M.
                    var window = tokens > contextWindow ? Math.Max(1_000_000, tokens) : contextWindow;
                    usage = Math.Min(tokens / window, 1);
                }
                sessions.Add(new AgentSession
                {
                    Id = id,
                    Title = name.Length > 0 ? name : FileTail.ProjectName(cwd),
                    Project = FileTail.ProjectName(cwd),
                    Working = json.Str("status") == "busy",
                    Usage = usage,
                    Updated = DateTimeOffset.FromUnixTimeMilliseconds((long)updated).LocalDateTime,
                });
            }
        }
        return new AgentProvider { Id = "claude", Name = "Claude Code", Sessions = sessions };
    }

    private static bool IsAlive(int pid)
    {
        try
        {
            using var process = Process.GetProcessById(pid);
            return !process.HasExited;
        }
        catch
        {
            return false;
        }
    }

    private string? Transcript(string sessionId)
    {
        if (_transcripts.TryGetValue(sessionId, out var known)) return known;
        var projects = Path.Combine(_home, "projects");
        if (!Directory.Exists(projects)) return null;
        foreach (var dir in Directory.EnumerateDirectories(projects))
        {
            var candidate = Path.Combine(dir, sessionId + ".jsonl");
            if (!File.Exists(candidate)) continue;
            _transcripts[sessionId] = candidate;
            return candidate;
        }
        return null;
    }

    private double? ContextTokens(string sessionId)
    {
        if (Transcript(sessionId) is not { } path) return null;
        var mtime = File.GetLastWriteTimeUtc(path);
        if (_context.TryGetValue(sessionId, out var cached) && cached.mtime == mtime) return cached.tokens;
        var lines = FileTail.Lines(path, 512 * 1024);
        for (var i = lines.Count - 1; i >= 0; i--)
        {
            if (!lines[i].Contains("\"usage\"")) continue;
            if (FileTail.Json(lines[i]) is not { } entry || entry.Str("type") != "assistant") continue;
            if (entry.TryGetProperty("isSidechain", out var side) && side.ValueKind == JsonValueKind.True) continue;
            if (entry.Obj("message")?.Obj("usage") is not { } usage) continue;
            var tokens = (usage.Num("input_tokens") ?? 0) + (usage.Num("cache_read_input_tokens") ?? 0)
                + (usage.Num("cache_creation_input_tokens") ?? 0);
            _context[sessionId] = (mtime, tokens);
            return tokens;
        }
        return _context.TryGetValue(sessionId, out var old) ? old.tokens : null;
    }
}

/// <summary>Lê os arquivos de sessão em ~/.codex/sessions (início/fim de tarefa, tokens e limites do plano).</summary>
internal sealed class CodexScanner
{
    private sealed class Parsed
    {
        public DateTime Mtime;
        public bool TaskRunning;
        public double? Context;
        public List<AgentLimit> Limits = [];
    }

    private readonly string _home = Path.Combine(Paths.Home, ".codex");
    private List<string> _files = [];
    private DateTime _lastListing = DateTime.MinValue;
    private readonly Dictionary<string, Parsed> _parsed = [];
    private readonly Dictionary<string, string> _cwds = [];
    private readonly Dictionary<string, string> _names = [];
    private DateTime _namesMtime;

    public AgentProvider Scan()
    {
        var now = DateTime.Now;
        var root = Path.Combine(_home, "sessions");
        if ((now - _lastListing).TotalSeconds > 30)
        {
            _lastListing = now;
            _files = Directory.Exists(root)
                ? Directory.EnumerateFiles(root, "*.jsonl", SearchOption.AllDirectories).ToList() : [];
        }
        LoadNames();

        var sessions = new List<AgentSession>();
        (DateTime date, List<AgentLimit> limits)? newest = null;
        foreach (var file in _files)
        {
            DateTime mtime;
            try { mtime = File.GetLastWriteTime(file); }
            catch { continue; }
            if ((now - mtime).TotalHours > 3) continue;
            var info = Parse(file, mtime);
            if (info.Limits.Count > 0 && (newest == null || mtime > newest.Value.date)) newest = (mtime, info.Limits);

            // O id da sessão são os 36 caracteres finais do nome do arquivo.
            var stem = Path.GetFileNameWithoutExtension(file);
            var id = stem.Length >= 36 ? stem[^36..] : stem;
            var cwd = Cwd(file);
            sessions.Add(new AgentSession
            {
                Id = id,
                Title = _names.TryGetValue(id, out var name) ? name : FileTail.ProjectName(cwd),
                Project = FileTail.ProjectName(cwd),
                // Sem atividade há muito tempo com tarefa "aberta" = sessão interrompida.
                Working = info.TaskRunning && (now - mtime).TotalMinutes < 20,
                Usage = info.Context,
                Updated = mtime,
            });
        }
        return new AgentProvider { Id = "codex", Name = "Codex", Sessions = sessions, Limits = newest?.limits ?? [] };
    }

    private void LoadNames()
    {
        var index = Path.Combine(_home, "session_index.jsonl");
        if (!File.Exists(index)) return;
        var mtime = File.GetLastWriteTimeUtc(index);
        if (mtime == _namesMtime) return;
        _namesMtime = mtime;
        foreach (var line in FileTail.Lines(index, 2 * 1024 * 1024))
        {
            if (FileTail.Json(line) is not { } entry) continue;
            var id = entry.Str("id");
            var name = entry.Str("thread_name");
            if (id.Length > 0 && name.Length > 0) _names[id] = name;
        }
    }

    private string Cwd(string file)
    {
        if (_cwds.TryGetValue(file, out var known)) return known;
        var cwd = "";
        if (FileTail.FirstLine(file) is { } line && FileTail.Json(line) is { } entry)
        {
            cwd = entry.Obj("payload")?.Str("cwd") ?? "";
        }
        _cwds[file] = cwd;
        return cwd;
    }

    private Parsed Parse(string file, DateTime mtime)
    {
        if (_parsed.TryGetValue(file, out var cached) && cached.Mtime == mtime) return cached;
        var info = new Parsed { Mtime = mtime };
        bool foundTask = false, foundTokens = false;
        var lines = FileTail.Lines(file, 768 * 1024);
        for (var i = lines.Count - 1; i >= 0 && !(foundTask && foundTokens); i--)
        {
            var line = lines[i];
            var isTask = !foundTask && (line.Contains("\"task_started\"") || line.Contains("\"task_complete\"")
                                        || line.Contains("\"turn_aborted\""));
            var isTokens = !foundTokens && line.Contains("\"token_count\"");
            if (!isTask && !isTokens) continue;
            if (FileTail.Json(line) is not { } entry || entry.Str("type") != "event_msg") continue;
            if (entry.Obj("payload") is not { } payload) continue;
            switch (payload.Str("type"))
            {
                case "task_started" when !foundTask:
                    info.TaskRunning = true;
                    foundTask = true;
                    break;
                case "task_complete" or "turn_aborted" when !foundTask:
                    foundTask = true;
                    break;
                case "token_count" when !foundTokens:
                    foundTokens = true;
                    if (payload.Obj("info") is { } usage && usage.Obj("last_token_usage")?.Num("total_tokens") is { } total
                        && usage.Num("model_context_window") is { } window && window > 0)
                    {
                        info.Context = Math.Min(total / window, 1);
                    }
                    if (payload.Obj("rate_limits") is { } limits)
                    {
                        foreach (var name in new[] { "primary", "secondary" })
                        {
                            if (Limit(limits.Obj(name)) is { } limit) info.Limits.Add(limit);
                        }
                    }
                    break;
            }
        }
        _parsed[file] = info;
        return info;
    }

    private static AgentLimit? Limit(JsonElement? raw)
    {
        if (raw is not { } limit || limit.Num("used_percent") is not { } used) return null;
        var minutes = limit.Num("window_minutes") ?? 0;
        var label = minutes switch
        {
            10080 => Loc.T("semana"),
            >= 1440 => Loc.T("{0} dias", (int)(minutes / 1440)),
            >= 60 => $"{(int)(minutes / 60)} h",
            _ => Loc.T("limite"),
        };
        // Se a janela já virou desde a última leitura, o uso voltou a zero.
        if (limit.Num("resets_at") is { } resets && resets < DateTimeOffset.Now.ToUnixTimeSeconds())
        {
            return new AgentLimit(label, 0);
        }
        return new AgentLimit(label, used);
    }
}
