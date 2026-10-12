using System.ComponentModel;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using Microsoft.Win32;

namespace OpenNotch;

/// <summary>
/// Ponto de entrada. Cria um notch por tela, o ícone da bandeja do Windows e liga os módulos
/// entre si. Equivale a AppDelegate + NotchController na versão macOS.
/// </summary>
public partial class App : Application
{
    private static Mutex? _single;
    private readonly List<NotchWindow> _notches = [];
    private System.Windows.Forms.NotifyIcon? _trayIcon;
    private HwndSource? _messages;
    private HotKeys? _hotKeys;
    private SettingsWindow? _settings;
    private Services _services = null!;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        // Uma instância só: abrir de novo não cria um segundo notch.
        _single = new Mutex(true, "OpenNotch.SingleInstance", out var first);
        if (!first)
        {
            Shutdown();
            return;
        }
        DispatcherUnhandledException += (_, args) => args.Handled = true;   // um erro numa aba não derruba o app

        Loc.Init();
        _services = Services.Instance;

        // Janela invisível só para receber os avisos do Windows (atalhos e área de transferência).
        _messages = new HwndSource(new HwndSourceParameters("OpenNotchMessages") { ParentWindow = new IntPtr(-3) });
        _services.Clipboard.Attach(_messages);
        _hotKeys = new HotKeys(_messages);
        _hotKeys.Pressed += OnShortcut;
        _hotKeys.SetEnabled(Settings.Current.HotkeysEnabled);

        _services.Agents.Finished += OnAgentFinished;
        _services.Capture.BeforeCapture += CloseAll;
        _services.Capture.Captured += _ =>
        {
            if (Settings.Current.CaptureShowAfter) Active?.Flash(NotchTab.Capture, 4);
        };
        _services.Downloads.Finished += _ => Active?.Flash(NotchTab.Files, 4);
        Settings.Current.PropertyChanged += OnSettingsChanged;
        SystemEvents.DisplaySettingsChanged += (_, _) => Dispatcher.BeginInvoke(Rebuild);

        EnableStartupOnce();
        CreateTrayIcon();
        Rebuild();

        if (Settings.Current.UpdateAutoCheck)
        {
            var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(8) };
            timer.Tick += async (_, _) => { timer.Stop(); await _services.Updater.Check(); };
            timer.Start();
        }
    }

    /// <summary>
    /// O OpenNotch vem configurado para abrir junto com o Windows. Isso é feito uma única vez:
    /// se o usuário desligar depois nas configurações, a escolha dele é respeitada.
    /// </summary>
    private static void EnableStartupOnce()
    {
        if (Settings.Current.StartupConfigured) return;
        Settings.Current.StartupConfigured = true;
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", writable: true);
            if (key != null && Environment.ProcessPath is { } path) key.SetValue("OpenNotch", $"\"{path}\"");
        }
        catch
        {
            // sem acesso ao registro: o app só não abre sozinho
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _hotKeys?.SetEnabled(false);
        if (_trayIcon != null)
        {
            _trayIcon.Visible = false;
            _trayIcon.Dispose();
        }
        _services?.Notes.Save();
        base.OnExit(e);
    }

    /// <summary>Notch da tela onde o mouse está; se não houver um lá, o primeiro.</summary>
    private NotchWindow? Active
    {
        get
        {
            var screen = System.Windows.Forms.Screen.FromPoint(System.Windows.Forms.Cursor.Position);
            var index = Array.IndexOf(System.Windows.Forms.Screen.AllScreens, screen);
            return index >= 0 && index < _notches.Count ? _notches[index] : _notches.FirstOrDefault();
        }
    }

    /// <summary>Recria os notches conforme as telas conectadas: um por tela, ou só o da principal.</summary>
    private void Rebuild()
    {
        foreach (var notch in _notches) notch.Close();
        _notches.Clear();
        var screens = Settings.Current.DisplayAllScreens
            ? System.Windows.Forms.Screen.AllScreens
            : [System.Windows.Forms.Screen.PrimaryScreen ?? System.Windows.Forms.Screen.AllScreens[0]];
        foreach (var screen in screens)
        {
            var notch = new NotchWindow(screen);
            notch.SettingsRequested += ShowSettings;
            notch.Show();
            _notches.Add(notch);
        }
    }

    private void CloseAll()
    {
        foreach (var notch in _notches) notch.Close(animated: false);
    }

    private void OnSettingsChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(Settings.DisplayAllScreens)) Rebuild();
        if (e.PropertyName == nameof(Settings.HotkeysEnabled)) _hotKeys?.SetEnabled(Settings.Current.HotkeysEnabled);
        if (e.PropertyName == nameof(Settings.ClipPersist)) _services.Clipboard.Save();
    }

    private void OnShortcut(Shortcut shortcut)
    {
        switch (shortcut)
        {
            case Shortcut.ToggleNotch:
                if (_notches.FirstOrDefault(n => n.IsOpen) is { } open) open.Close(animated: true);
                else Active?.OpenFromKeyboard(null);
                break;
            case Shortcut.Texts:
                Active?.OpenFromKeyboard(NotchTab.Texts);
                break;
            case Shortcut.Capture:
                Active?.OpenFromKeyboard(NotchTab.Capture);
                break;
        }
    }

    /// <summary>Um agente de IA terminou a tarefa: avisa e abre o notch por alguns segundos.</summary>
    private void OnAgentFinished(AgentFinish finish)
    {
        var settings = Settings.Current;
        if (!settings.ModAgents || !settings.AgentsNotify || Active is not { } notch) return;
        var detail = finish.Project.Length == 0 || finish.Project == finish.Title
            ? finish.Title : $"{finish.Title} · {finish.Project}";
        notch.ShowAgentBanner(Loc.T("{0} terminou: {1}", finish.Provider, detail));
        if (settings.AgentsSound) System.Media.SystemSounds.Exclamation.Play();
        notch.Flash(NotchTab.Agents, Math.Max(settings.AgentsNotifySeconds, 2));
    }

    private void ShowSettings()
    {
        CloseAll();
        if (_settings == null)
        {
            _settings = new SettingsWindow();
            _settings.Closed += (_, _) => _settings = null;
        }
        _settings.Show();
        _settings.Activate();
    }

    private void CreateTrayIcon()
    {
        var icon = System.Drawing.SystemIcons.Application;
        try
        {
            var resource = GetResourceStream(new Uri("pack://application:,,,/Resources/AppIcon.ico"));
            if (resource != null) icon = new System.Drawing.Icon(resource.Stream);
        }
        catch
        {
            // sem o ícone próprio, usa o genérico do Windows
        }
        var menu = new System.Windows.Forms.ContextMenuStrip();
        menu.Items.Add(Loc.T("Abrir OpenNotch"), null, (_, _) => Active?.OpenFromKeyboard(null));
        menu.Items.Add(Loc.T("Configurações…"), null, (_, _) => ShowSettings());
        menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        menu.Items.Add(Loc.T("Sair"), null, (_, _) => Shutdown());
        _trayIcon = new System.Windows.Forms.NotifyIcon
        {
            Icon = icon,
            Text = "OpenNotch",
            Visible = true,
            ContextMenuStrip = menu,
        };
        _trayIcon.DoubleClick += (_, _) => ShowSettings();
    }
}
