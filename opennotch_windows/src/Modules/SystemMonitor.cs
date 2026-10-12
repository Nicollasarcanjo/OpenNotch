using System.IO;
using System.Net.NetworkInformation;
using System.Windows.Threading;

namespace OpenNotch;

/// <summary>CPU, memória, disco, bateria e rede, amostrados a cada 2 segundos.</summary>
public sealed class SystemMonitor : Observable
{
    private double _cpu, _memory, _disk, _down, _up;
    private int? _battery;
    private bool _charging;
    private string _memoryText = "", _diskText = "";

    public double Cpu { get => _cpu; private set { if (Set(ref _cpu, value)) Raise(nameof(CpuText)); } }
    public double Memory { get => _memory; private set { if (Set(ref _memory, value)) Raise(nameof(MemoryPercent)); } }
    public double Disk { get => _disk; private set { if (Set(ref _disk, value)) Raise(nameof(DiskPercent)); } }
    public int? Battery { get => _battery; private set { if (Set(ref _battery, value)) { Raise(nameof(BatteryText)); Raise(nameof(HasBattery)); Raise(nameof(BatteryValue)); } } }
    public bool Charging { get => _charging; private set { if (Set(ref _charging, value)) Raise(nameof(BatteryTitle)); } }
    public string MemoryText { get => _memoryText; private set => Set(ref _memoryText, value); }
    public string DiskText { get => _diskText; private set => Set(ref _diskText, value); }
    public double Down { get => _down; private set { if (Set(ref _down, value)) Raise(nameof(DownText)); } }
    public double Up { get => _up; private set { if (Set(ref _up, value)) Raise(nameof(UpText)); } }

    public string CpuText => $"{Math.Round(Cpu * 100)}%";
    public string MemoryPercent => $"{Math.Round(Memory * 100)}%";
    public string DiskPercent => $"{Math.Round(Disk * 100)}%";
    public bool HasBattery => Battery != null;
    public double BatteryValue => (Battery ?? 0) / 100.0;
    public string BatteryText => Battery is { } value ? $"{value}%" : "";
    public string BatteryTitle => Charging ? Loc.T("Carregando") : Loc.T("Bateria");
    public string DownText => "↓ " + Paths.FormatBytes(Down) + "/s";
    public string UpText => "↑ " + Paths.FormatBytes(Up) + "/s";

    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(2) };
    private (long idle, long total)? _lastCpu;
    private (long rx, long tx, DateTime at)? _lastNet;

    public SystemMonitor()
    {
        _timer.Tick += (_, _) => Sample();
        _timer.Start();
        Sample();
    }

    private void Sample()
    {
        if (!Settings.Current.ModSystem) return;

        if (Native.GetSystemTimes(out var idle, out var kernel, out var user))
        {
            var total = kernel + user;   // o tempo de kernel já inclui o ocioso
            if (_lastCpu is { } last && total > last.total)
            {
                Cpu = Math.Clamp(1 - (idle - last.idle) / (double)(total - last.total), 0, 1);
            }
            _lastCpu = (idle, total);
        }

        var (memTotal, memAvailable) = Native.Memory();
        Memory = 1 - memAvailable / (double)memTotal;
        MemoryText = Paths.FormatBytes(memTotal - memAvailable);

        try
        {
            var drive = new DriveInfo(Path.GetPathRoot(Environment.SystemDirectory) ?? "C:\\");
            Disk = 1 - drive.AvailableFreeSpace / (double)drive.TotalSize;
            DiskText = Loc.T("{0} livres", Paths.FormatBytes(drive.AvailableFreeSpace));
        }
        catch { }

        var power = System.Windows.Forms.SystemInformation.PowerStatus;
        var hasBattery = power.BatteryChargeStatus != System.Windows.Forms.BatteryChargeStatus.NoSystemBattery
            && power.BatteryLifePercent <= 1;
        Battery = hasBattery ? (int)Math.Round(power.BatteryLifePercent * 100) : null;
        Charging = power.PowerLineStatus == System.Windows.Forms.PowerLineStatus.Online;

        try
        {
            long rx = 0, tx = 0;
            foreach (var adapter in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (adapter.OperationalStatus != OperationalStatus.Up
                    || adapter.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                var stats = adapter.GetIPStatistics();
                rx += stats.BytesReceived;
                tx += stats.BytesSent;
            }
            var now = DateTime.UtcNow;
            if (_lastNet is { } last)
            {
                var seconds = Math.Max((now - last.at).TotalSeconds, 0.5);
                Down = Math.Max(rx - last.rx, 0) / seconds;
                Up = Math.Max(tx - last.tx, 0) / seconds;
            }
            _lastNet = (rx, tx, now);
        }
        catch { }
    }
}
