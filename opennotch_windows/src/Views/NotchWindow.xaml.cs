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
    // Fechado, o notch é só um risco discreto no topo; com "mostrar indicadores" ligado,
    // ele cresce para caber a capa da música, o timer ou os agentes.
    private static readonly Size Minimized = new(150, 4);
    private static readonly Size WithIndicators = new(260, 26);

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

        Root.MouseEnter += (_, _) => Hover(true);
        Root.MouseLeave += (_, _) => Hover(false);
        Root.MouseLeftButtonDown += (_, _) => { if (!IsOpen) Open(); };
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
        if (!ReferenceEquals(TabContent.Content, view))
        {
            TabContent.Content = view;
            if (IsOpen) TabContent.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(160)));
        }
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
        Shell.CornerRadius = new CornerRadius(0, 0, 24, 24);
        Shell.BeginAnimation(OpacityProperty, Fade(1, 120));

        // A casca cresce com um leve "passar do ponto e voltar", como uma mola;
        // o conteúdo entra um instante depois, subindo e ganhando opacidade.
        var spring = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.35 };
        Resize(OpenSize, 380, spring);
        OpenView.BeginAnimation(OpacityProperty, Fade(1, 220, delay: 90));
        OpenShift.BeginAnimation(System.Windows.Media.TranslateTransform.YProperty,
            new DoubleAnimation(-8, 0, TimeSpan.FromMilliseconds(300))
            {
                BeginTime = TimeSpan.FromMilliseconds(70),
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
            });
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

        // Primeiro o conteúdo some; a casca encolhe em seguida e só então o painel é escondido.
        OpenView.BeginAnimation(OpacityProperty, Fade(0, animated ? 110 : 0));
        var settle = new DoubleAnimation(0, TimeSpan.FromMilliseconds(animated ? 260 : 0));
        settle.Completed += (_, _) =>
        {
            if (IsOpen) return;   // reabriu durante a animação
            OpenView.Visibility = Visibility.Collapsed;
            TabContent.Content = null;
        };
        // Uma animação "vazia" só para avisar quando o fechamento terminou.
        OpenShift.BeginAnimation(System.Windows.Media.TranslateTransform.XProperty, settle);
        UpdateEars(animated);
    }

    private static DoubleAnimation Fade(double to, double milliseconds, double delay = 0) =>
        new(to, TimeSpan.FromMilliseconds(milliseconds)) { BeginTime = TimeSpan.FromMilliseconds(delay) };

    private void Resize(Size size, double milliseconds, IEasingFunction ease)
    {
        var duration = TimeSpan.FromMilliseconds(milliseconds);
        Shell.BeginAnimation(WidthProperty, new DoubleAnimation(size.Width, duration) { EasingFunction = ease });
        Shell.BeginAnimation(HeightProperty, new DoubleAnimation(size.Height, duration) { EasingFunction = ease });
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

    // MARK: Notch fechado

    /// <summary>
    /// Com o notch fechado: por padrão só um risco discreto, para não ocupar espaço. Com a opção
    /// "mostrar indicadores" ligada, aparece a capa da música e o timer ou os agentes trabalhando.
    /// </summary>
    private void UpdateEars(bool animated = true)
    {
        if (IsOpen) return;
        var settings = Settings.Current;
        var music = settings.ModMusic && _services.Music.IsPlaying;
        var timer = settings.ModTimers && _services.Timers.IsRunning;
        var agents = settings.ModAgents ? _services.Agents.WorkingCount : 0;
        var downloading = settings.ModDownloads && _services.Downloads.Downloading;
        var indicators = settings.ShowClosedIndicators && (music || timer || agents > 0 || downloading);

        EarArtwork.Source = music ? _services.Music.Artwork : null;
        EarText.Text = timer ? _services.Timers.Display
            : agents > 0 ? $"● {agents}"
            : downloading ? "↓" : "";
        ClosedView.Visibility = indicators ? Visibility.Visible : Visibility.Collapsed;
        Shell.CornerRadius = indicators ? new CornerRadius(0, 0, 12, 12) : new CornerRadius(0, 0, 4, 4);
        Shell.BeginAnimation(OpacityProperty, Fade(indicators ? 1 : 0.6, animated ? 200 : 0));
        Resize(indicators ? WithIndicators : Minimized, animated ? 260 : 0,
               new CubicEase { EasingMode = EasingMode.EaseInOut });
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
