using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace OpenNotch;

public enum NotchTab { Home, Agents, Apps, Mixer, Capture, Texts, Files, Timers, System }

/// <summary>
/// O notch de uma tela: uma barra no topo que abre ao passar o mouse.
/// Equivale a ScreenNotch + NotchRootView na versão macOS.
/// </summary>
public partial class NotchWindow : Window
{
    private static readonly Size OpenSize = new(640, 224);
    private const double ClosedHeight = 26, ClosedWidth = 190, ClosedWidthWithEars = 260;

    private sealed record TabInfo(NotchTab Tab, string Glyph, string Title, Func<bool> Enabled, Func<UserControl> Create);

    private readonly System.Windows.Forms.Screen _screen;
    private readonly Services _services = Services.Instance;
    private readonly List<TabInfo> _tabs;
    private readonly Dictionary<NotchTab, UserControl> _views = [];
    private readonly DispatcherTimer _openTimer = new(), _closeTimer = new(), _flashTimer = new();
    private NotchTab _tab = NotchTab.Home;
    private bool _hovering;

    public bool IsOpen { get; private set; }
    public event Action? SettingsRequested;

    public NotchWindow(System.Windows.Forms.Screen screen)
    {
        _screen = screen;
        InitializeComponent();
        var s = Settings.Current;
        _tabs =
        [
            new(NotchTab.Home, "", Loc.T("Início"), () => true, () => new HomeView()),
            new(NotchTab.Agents, "", Loc.T("Agentes de IA"), () => s.ModAgents, () => new AgentsView()),
            new(NotchTab.Apps, "", Loc.T("Apps abertos"), () => s.ModApps, () => new AppsView()),
            new(NotchTab.Mixer, "\uE767", Loc.T("Volume por app"), () => s.ModMixer, () => new MixerView()),
            new(NotchTab.Capture, "", Loc.T("Captura de tela"), () => s.ModCapture, () => new CaptureView()),
            new(NotchTab.Texts, "", Loc.T("Textos"), () => s.ModNotes || s.ModClipboard, () => new TextsView()),
            new(NotchTab.Files, "", Loc.T("Arquivos"), () => s.ModTray || s.ModDownloads, () => new FilesView()),
            new(NotchTab.Timers, "", Loc.T("Timers"), () => s.ModTimers, () => new TimersView()),
            new(NotchTab.System, "", Loc.T("Sistema"), () => s.ModSystem, () => new SystemView()),
        ];

        _openTimer.Tick += (_, _) => { _openTimer.Stop(); Open(); };
        _closeTimer.Tick += (_, _) => { _closeTimer.Stop(); if (!_hovering && !IsTyping) Close(animated: true); };
        _flashTimer.Tick += (_, _) => { _flashTimer.Stop(); if (!_hovering && !IsTyping) Close(animated: true); };

        Shell.MouseEnter += (_, _) => Hover(true);
        Shell.MouseLeave += (_, _) => Hover(false);
        Shell.MouseLeftButtonDown += (_, _) => { if (!IsOpen) Open(); };
        Deactivated += (_, _) => { if (IsOpen) Close(animated: true); };
        DragEnter += OnDragEnter;
        Drop += OnDrop;
        SourceInitialized += OnSourceInitialized;

        Settings.Current.PropertyChanged += OnChanged;
        _services.Music.PropertyChanged += OnChanged;
        _services.Agents.PropertyChanged += OnChanged;
        _services.Timers.PropertyChanged += OnChanged;
        _services.Downloads.PropertyChanged += OnChanged;
        Closed += (_, _) =>
        {
            Settings.Current.PropertyChanged -= OnChanged;
            _services.Music.PropertyChanged -= OnChanged;
            _services.Agents.PropertyChanged -= OnChanged;
            _services.Timers.PropertyChanged -= OnChanged;
            _services.Downloads.PropertyChanged -= OnChanged;
        };
        BuildTabs();
        UpdateEars();
    }

    private bool IsTyping => Keyboard.FocusedElement is TextBox box && box.IsKeyboardFocusWithin && IsActive;

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        var handle = new WindowInteropHelper(this).Handle;
        // Janela de ferramenta: não aparece no Alt+Tab nem na barra de tarefas.
        var style = Native.GetWindowLongPtr(handle, Native.GWL_EXSTYLE).ToInt64();
        Native.SetWindowLongPtr(handle, Native.GWL_EXSTYLE, new IntPtr(style | Native.WS_EX_TOOLWINDOW));

        ApplyCaptureVisibility();

        // A tela vem em pixels; o WPF posiciona em unidades independentes de DPI.
        var scale = PresentationSource.FromVisual(this)?.CompositionTarget?.TransformToDevice.M11 ?? 1;
        var bounds = _screen.Bounds;
        Left = bounds.Left / scale + (bounds.Width / scale - Width) / 2;
        Top = bounds.Top / scale;
    }

    /// <summary>
    /// Por padrão o notch fica fora de prints e gravações (de qualquer app); a opção
    /// "Mostrar o OpenNotch em prints e gravações" faz ele aparecer.
    /// </summary>
    private void ApplyCaptureVisibility()
    {
        var handle = new WindowInteropHelper(this).Handle;
        if (handle == IntPtr.Zero) return;
        Native.SetWindowDisplayAffinity(handle,
            Settings.Current.CaptureShowNotch ? Native.WDA_NONE : Native.WDA_EXCLUDEFROMCAPTURE);
    }

    private void OnChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (sender is Settings)
        {
            if (e.PropertyName == nameof(Settings.CaptureShowNotch)) ApplyCaptureVisibility();
            BuildTabs();
        }
        UpdateEars();
    }

    // MARK: Abas

    private void BuildTabs()
    {
        TabBar.Children.Clear();
        var enabled = _tabs.Where(t => t.Enabled()).ToList();
        if (enabled.All(t => t.Tab != _tab)) _tab = enabled.FirstOrDefault()?.Tab ?? NotchTab.Home;
        foreach (var info in enabled)
        {
            var button = new Button
            {
                Style = (Style)FindResource("Flat"),
                ToolTip = info.Title,
                Margin = new Thickness(0, 0, 2, 0),
                Opacity = info.Tab == _tab ? 1 : 0.5,
                Content = new TextBlock { Style = (Style)FindResource("Glyph"), Text = info.Glyph, FontSize = 14 },
            };
            button.Click += (_, _) => Select(info.Tab);
            TabBar.Children.Add(button);
        }
        if (IsOpen) ShowTab();
    }

    public void Select(NotchTab tab)
    {
        if (_tabs.First(t => t.Tab == tab).Enabled()) _tab = tab;
        BuildTabs();
    }

    private void ShowTab()
    {
        var info = _tabs.First(t => t.Tab == _tab);
        if (!_views.TryGetValue(_tab, out var view)) _views[_tab] = view = info.Create();
        TabContent.Content = view;
        TabTitle.Text = info.Title;
        // O gerenciador de apps só mede enquanto a aba dele está na tela.
        _services.Apps.Active = _tab == NotchTab.Apps;
    }

    // MARK: Abrir e fechar

    private void Hover(bool inside)
    {
        _hovering = inside;
        _openTimer.Stop();
        _closeTimer.Stop();
        var settings = Settings.Current;
        if (inside)
        {
            if (IsOpen || !settings.HoverOpens) return;
            _openTimer.Interval = TimeSpan.FromSeconds(Math.Max(settings.HoverDelay, 0.01));
            _openTimer.Start();
        }
        else if (IsOpen)
        {
            _closeTimer.Interval = TimeSpan.FromSeconds(Math.Max(settings.CloseDelay, 0.05));
            _closeTimer.Start();
        }
    }

    public void Open(NotchTab? tab = null)
    {
        if (tab is { } wanted) Select(wanted);
        if (IsOpen) return;
        IsOpen = true;
        ClosedView.Visibility = Visibility.Collapsed;
        OpenView.Visibility = Visibility.Visible;
        ShowTab();
        Shell.CornerRadius = new CornerRadius(0, 0, 22, 22);
        Animate(OpenSize.Width, OpenSize.Height);
    }

    public void Close(bool animated)
    {
        _openTimer.Stop();
        _closeTimer.Stop();
        _flashTimer.Stop();
        if (!IsOpen) return;
        IsOpen = false;
        _services.Apps.Active = false;
        (_views.GetValueOrDefault(NotchTab.Agents) as AgentsView)?.ClearBanner();
        OpenView.Visibility = Visibility.Collapsed;
        ClosedView.Visibility = Visibility.Visible;
        Shell.CornerRadius = new CornerRadius(0, 0, 12, 12);
        UpdateEars(animated);
    }

    /// <summary>Abre sozinho por alguns segundos (ex.: um agente terminou) e fecha se ninguém interagir.</summary>
    public void Flash(NotchTab tab, double seconds)
    {
        var wasOpen = IsOpen;
        Open(tab);
        if (wasOpen) return;   // já estava em uso: não fecha na cara do usuário
        _flashTimer.Interval = TimeSpan.FromSeconds(seconds);
        _flashTimer.Start();
    }

    public void OpenFromKeyboard(NotchTab? tab)
    {
        Open(tab);
        Activate();
    }

    public void ShowAgentBanner(string text)
    {
        if (!_views.TryGetValue(NotchTab.Agents, out var view)) _views[NotchTab.Agents] = view = new AgentsView();
        ((AgentsView)view).ShowBanner(text);
    }

    private void Animate(double width, double height, bool animated = true)
    {
        var duration = TimeSpan.FromMilliseconds(animated ? 180 : 0);
        var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
        Shell.BeginAnimation(WidthProperty, new DoubleAnimation(width, duration) { EasingFunction = ease });
        Shell.BeginAnimation(HeightProperty, new DoubleAnimation(height, duration) { EasingFunction = ease });
    }

    // MARK: Notch fechado

    /// <summary>Com o notch fechado: capa da música à esquerda e, à direita, timer ou agentes trabalhando.</summary>
    private void UpdateEars(bool animated = true)
    {
        if (IsOpen) return;
        var settings = Settings.Current;
        var music = settings.ModMusic && _services.Music.IsPlaying;
        var timer = settings.ModTimers && _services.Timers.IsRunning;
        var agents = settings.ModAgents ? _services.Agents.WorkingCount : 0;
        var downloading = settings.ModDownloads && _services.Downloads.Downloading;

        EarArtwork.Source = music ? _services.Music.Artwork : null;
        EarText.Text = timer ? _services.Timers.Display
            : agents > 0 ? $"● {agents}"
            : downloading ? "↓" : "";
        var ears = music || timer || agents > 0 || downloading;
        Animate(ears ? ClosedWidthWithEars : ClosedWidth, ClosedHeight, animated);
    }

    // MARK: Arrastar arquivos

    private void OnDragEnter(object sender, DragEventArgs e)
    {
        if (!e.Data.GetDataPresent(DataFormats.FileDrop) || !Settings.Current.ModTray) return;
        Open(NotchTab.Files);
    }

    private void OnDrop(object sender, DragEventArgs e)
    {
        if (!Settings.Current.ModTray || e.Data.GetData(DataFormats.FileDrop) is not string[] files) return;
        _services.Tray.Add(files);
        Select(NotchTab.Files);
    }

    private void OnGear(object sender, RoutedEventArgs e) => SettingsRequested?.Invoke();
}
