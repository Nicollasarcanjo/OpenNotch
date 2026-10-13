using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Windows.Media;
using System.Windows.Threading;

namespace OpenNotch;

public sealed class ProcessRow
{
    public int Pid { get; init; }
    public string Name { get; init; } = "";
    public double Cpu { get; init; }
    public double Gpu { get; init; }
    public long Memory { get; init; }
    public string CpuText => AppRow.Percent(Cpu);
    public string GpuText => AppRow.Percent(Gpu);
    public string MemoryText => AppRow.Percent(Memory / (double)AppMonitor.MemoryTotal * 100);
}

public sealed class AppRow : Observable
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public ImageSource? Icon { get; init; }
    public List<int> MainPids { get; init; } = [];
    public double Cpu { get; init; }
    public double Gpu { get; init; }
    public long Memory { get; init; }
    public List<ProcessRow> Processes { get; init; } = [];

    private bool _expanded;
    public bool Expanded { get => _expanded; set => Set(ref _expanded, value); }

    public bool HasChildren => Processes.Count > 1;
    public string Count => Processes.Count.ToString();
    public string CpuText => Percent(Cpu);
    public string GpuText => Percent(Gpu);
    public string MemoryText => Percent(Memory / (double)AppMonitor.MemoryTotal * 100);
    public string MemoryTooltip => Loc.T("Memória: {0}", Paths.FormatBytes(Memory));

    public static string Percent(double value) =>
        value < 0.05 ? "0%" : value < 10 ? $"{value:0.0}%" : $"{Math.Round(value)}%";
}

/// <summary>
/// Gerenciador de apps: agrupa os processos de cada app com janela (pelo nome do executável)
/// e mede CPU, GPU e memória. Só mede enquanto a aba está visível.
/// </summary>
public sealed class AppMonitor : Observable
{
    public static long MemoryTotal { get; } = (long)Native.Memory().total;

    public ObservableCollection<AppRow> Apps { get; } = [];
    public string Sort { get; set; } = "cpu";

    private bool _active;
    public bool Active
    {
        get => _active;
        set
        {
            if (_active == value) return;
            _active = value;
            if (value) Sample();
        }
    }

    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(2) };
    private Dictionary<int, TimeSpan> _lastCpu = [];
    private DateTime? _lastSample;
    private bool _sampling;
    private readonly HashSet<string> _expanded = [];
    private readonly Dictionary<string, ImageSource?> _icons = [];

    public AppMonitor()
    {
        if (Demo.Enabled)
        {
            foreach (var app in Demo.Apps()) Apps.Add(app);
            return;
        }
        _timer.Tick += (_, _) => Sample();
        _timer.Start();
    }

    private async void Sample()
    {
        if (!_active || !Settings.Current.ModApps || _sampling) return;
        _sampling = true;
        foreach (var app in Apps) { if (app.Expanded) _expanded.Add(app.Id); else _expanded.Remove(app.Id); }
        List<AppRow> rows;
        try { rows = await Task.Run(Measure); }
        catch { rows = []; }
        _sampling = false;
        Apps.Clear();
        foreach (var row in rows)
        {
            row.Expanded = _expanded.Contains(row.Id);
            Apps.Add(row);
        }
    }

    private List<AppRow> Measure()
    {
        var now = DateTime.UtcNow;
        var elapsed = _lastSample is { } last ? Math.Max((now - last).TotalSeconds, 0.2) : 0;
        _lastSample = now;
        var cores = Math.Max(Environment.ProcessorCount, 1);
        var me = Environment.ProcessId;
        var gpu = GpuUsage.Read();

        var cpuNow = new Dictionary<int, TimeSpan>();
        var groups = new Dictionary<string, List<(Process process, ProcessRow row, bool main)>>(StringComparer.OrdinalIgnoreCase);
        foreach (var process in Process.GetProcesses())
        {
            try
            {
                if (process.Id == me || process.SessionId == 0) continue;
                var total = process.TotalProcessorTime;
                cpuNow[process.Id] = total;
                double cpu = 0;
                if (elapsed > 0 && _lastCpu.TryGetValue(process.Id, out var before))
                {
                    cpu = Math.Max((total - before).TotalSeconds, 0) / elapsed * 100 / cores;
                }
                var row = new ProcessRow
                {
                    Pid = process.Id,
                    Name = process.ProcessName,
                    Cpu = Math.Min(cpu, 100),
                    Gpu = gpu.TryGetValue(process.Id, out var g) ? Math.Min(g, 100) : 0,
                    Memory = process.WorkingSet64,
                };
                var main = process.MainWindowHandle != IntPtr.Zero && Native.IsWindowVisible(process.MainWindowHandle)
                    && !string.IsNullOrWhiteSpace(process.MainWindowTitle);
                if (!groups.TryGetValue(process.ProcessName, out var list)) groups[process.ProcessName] = list = [];
                list.Add((process, row, main));
            }
            catch
            {
                // processo de outro usuário ou que acabou de fechar
            }
        }
        _lastCpu = cpuNow;

        var rows = new List<AppRow>();
        foreach (var (name, members) in groups)
        {
            // Só vira "app" o grupo que tem pelo menos uma janela visível.
            var mains = members.Where(m => m.main).ToList();
            if (mains.Count == 0) continue;
            var first = mains[0].process;
            string display = name, path = "";
            try
            {
                path = first.MainModule?.FileName ?? "";
                var description = first.MainModule?.FileVersionInfo.FileDescription;
                if (!string.IsNullOrWhiteSpace(description)) display = description;
            }
            catch
            {
                // sem acesso ao executável (app elevado): fica o nome do processo
            }
            rows.Add(new AppRow
            {
                Id = name,
                Name = display,
                Icon = IconFor(path),
                MainPids = mains.Select(m => m.row.Pid).ToList(),
                Cpu = Math.Min(members.Sum(m => m.row.Cpu), 100),
                Gpu = Math.Min(members.Sum(m => m.row.Gpu), 100),
                Memory = members.Sum(m => m.row.Memory),
                Processes = members.OrderByDescending(m => m.main).ThenByDescending(m => m.row.Cpu)
                    .Select(m => m.row).ToList(),
            });
        }
        foreach (var members in groups.Values) foreach (var member in members) member.process.Dispose();

        return Sort switch
        {
            "gpu" => rows.OrderByDescending(r => r.Gpu).ThenByDescending(r => r.Cpu).ToList(),
            "memory" => rows.OrderByDescending(r => r.Memory).ToList(),
            "name" => rows.OrderBy(r => r.Name, StringComparer.CurrentCultureIgnoreCase).ToList(),
            _ => rows.OrderByDescending(r => r.Cpu).ToList(),
        };
    }

    private ImageSource? IconFor(string path)
    {
        if (path.Length == 0) return null;
        lock (_icons)
        {
            if (_icons.TryGetValue(path, out var cached)) return cached;
            ImageSource? image = null;
            try
            {
                using var icon = System.Drawing.Icon.ExtractAssociatedIcon(path);
                if (icon != null)
                {
                    image = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(
                        icon.Handle, System.Windows.Int32Rect.Empty,
                        System.Windows.Media.Imaging.BitmapSizeOptions.FromEmptyOptions());
                    image.Freeze();
                }
            }
            catch
            {
                // sem ícone: a linha aparece só com o nome
            }
            _icons[path] = image;
            return image;
        }
    }

    /// <summary>Pede para o app fechar (ele ainda pode perguntar se quer salvar). <paramref name="force"/> encerra tudo na hora.</summary>
    public void Quit(AppRow app, bool force = false)
    {
        foreach (var row in force ? app.Processes : app.Processes.Where(p => app.MainPids.Contains(p.Pid)))
        {
            try
            {
                using var process = Process.GetProcessById(row.Pid);
                if (force) process.Kill(true); else process.CloseMainWindow();
            }
            catch
            {
                // já fechou
            }
        }
    }

    public void Kill(ProcessRow row)
    {
        try
        {
            using var process = Process.GetProcessById(row.Pid);
            process.Kill();
        }
        catch
        {
            // já fechou
        }
    }
}

/// <summary>Uso de GPU por processo, pelos contadores de desempenho "GPU Engine" do Windows.</summary>
internal static class GpuUsage
{
    private static List<PerformanceCounter>? _counters;
    private static DateTime _built = DateTime.MinValue;

    public static Dictionary<int, double> Read()
    {
        var result = new Dictionary<int, double>();
        try
        {
            // A lista de instâncias muda quando apps abrem e fecham; refaz a cada 10 s.
            if (_counters == null || (DateTime.UtcNow - _built).TotalSeconds > 10)
            {
                _counters?.ForEach(c => c.Dispose());
                var category = new PerformanceCounterCategory("GPU Engine");
                _counters = category.GetInstanceNames()
                    .Where(name => name.Contains("engtype_3D"))
                    .Select(name => new PerformanceCounter("GPU Engine", "Utilization Percentage", name))
                    .ToList();
                _built = DateTime.UtcNow;
                foreach (var counter in _counters) { try { counter.NextValue(); } catch { } }
                return result;   // a primeira leitura de um contador é sempre zero
            }
            foreach (var counter in _counters)
            {
                try
                {
                    // Nome da instância: "pid_1234_luid_..._engtype_3D"
                    var parts = counter.InstanceName.Split('_');
                    if (parts.Length < 2 || !int.TryParse(parts[1], out var pid)) continue;
                    result[pid] = result.GetValueOrDefault(pid) + counter.NextValue();
                }
                catch
                {
                    // instância sumiu
                }
            }
        }
        catch
        {
            // sem contadores de GPU nesta máquina: a coluna fica em 0%
        }
        return result;
    }
}
