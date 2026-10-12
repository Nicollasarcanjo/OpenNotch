namespace OpenNotch;

/// <summary>Tudo que os notches de todas as telas compartilham. Equivale a `Services` no macOS.</summary>
public sealed class Services
{
    public static Services Instance { get; } = new();

    public MusicManager Music { get; } = new();
    public AgentMonitor Agents { get; } = new();
    public AppMonitor Apps { get; } = new();
    public CaptureManager Capture { get; } = new();
    public NotesStore Notes { get; } = new();
    public ClipboardManager Clipboard { get; } = new();
    public TrayStore Tray { get; } = new();
    public DownloadsMonitor Downloads { get; } = new();
    public TimerManager Timers { get; } = new();
    public SystemMonitor System { get; } = new();
    public Updater Updater { get; } = new();
}
