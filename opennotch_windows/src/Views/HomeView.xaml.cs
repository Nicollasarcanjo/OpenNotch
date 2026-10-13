using System.Diagnostics;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace OpenNotch;

/// <summary>Tela inicial: uma fileira de blocos escolhidos pelo usuário nas configurações.</summary>
public partial class HomeView : UserControl
{
    public event Action? CustomizeRequested;

    public HomeView()
    {
        InitializeComponent();
        Settings.Current.PropertyChanged += (_, e) =>
        {
            var name = e.PropertyName ?? "";
            if (name.StartsWith("Home") || name is nameof(Settings.ModMusic) or nameof(Settings.ModSystem)
                or nameof(Settings.ModTimers)) Build();
        };
        Build();
    }

    private void Build()
    {
        Blocks.Children.Clear();
        var settings = Settings.Current;
        foreach (var id in settings.HomeBlocks)
        {
            FrameworkElement? block = id switch
            {
                "music" when settings.ModMusic => new MusicBlock(),
                "clock" => new ClockBlock(),
                "calendar" => new CalendarBlock(),
                "apps" => new AppsBlock(),
                "gif" => new GifBlock(),
                "slideshow" => new SlideshowBlock(),
                "system" when settings.ModSystem => new SystemMiniBlock(),
                "timer" when settings.ModTimers => new TimerMiniBlock(),
                _ => null,
            };
            if (block == null) continue;
            block.Margin = new Thickness(0, 0, 18, 0);
            Blocks.Children.Add(block);
        }
        if (Blocks.Children.Count > 0) return;

        var empty = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Width = 600 };
        empty.Children.Add(new TextBlock
        {
            Text = Loc.T("A tela inicial está vazia"), FontSize = 14, FontWeight = FontWeights.SemiBold,
            HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, 8),
        });
        var button = new Button
        {
            Style = (Style)FindResource("Chip"), Content = Loc.T("Personalizar"), HorizontalAlignment = HorizontalAlignment.Center,
        };
        button.Click += (_, _) => CustomizeRequested?.Invoke();
        empty.Children.Add(button);
        Blocks.Children.Add(empty);
    }
}

/// <summary>Base dos blocos de imagem: tamanho da configuração e cantos arredondados.</summary>
internal abstract class MediaBlock : Border
{
    protected readonly Grid Content = new();

    protected MediaBlock()
    {
        Width = Math.Clamp(Settings.Current.HomeMediaWidth, 80, 500);
        CornerRadius = new CornerRadius(14);
        Background = new SolidColorBrush(Color.FromArgb(0x14, 255, 255, 255));
        Child = Content;
        // O Border arredonda o próprio fundo, mas não corta o conteúdo; o recorte é feito aqui.
        SizeChanged += (_, e) => Clip = new RectangleGeometry(new Rect(e.NewSize), 14, 14);
    }

    protected void ShowHint(string text)
    {
        Content.Children.Clear();
        Content.Children.Add(new TextBlock
        {
            Text = text, FontSize = 11, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center,
            Foreground = new SolidColorBrush(Color.FromArgb(0x99, 255, 255, 255)),
            VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(10),
        });
    }
}

internal sealed class GifBlock : MediaBlock
{
    private readonly DispatcherTimer _timer = new();
    private GifFrames.Animation? _animation;
    private int _index;
    private readonly Image _image = new() { Stretch = Stretch.UniformToFill };

    public GifBlock()
    {
        var path = Settings.Current.HomeGif;
        _animation = path.Length > 0 ? GifFrames.Load(path) : null;
        if (_animation == null)
        {
            ShowHint(Loc.T("Escolha um GIF nas configurações"));
            return;
        }
        Content.Children.Add(_image);
        _image.Source = _animation.Frames[0];
        _timer.Tick += (_, _) => Advance();
        // Só anima enquanto o bloco está na tela.
        Loaded += (_, _) => { if (_animation.Frames.Count > 1) Schedule(); };
        Unloaded += (_, _) => _timer.Stop();
    }

    private void Schedule()
    {
        _timer.Interval = TimeSpan.FromMilliseconds(_animation!.DelaysMs[_index]);
        _timer.Start();
    }

    private void Advance()
    {
        _index = (_index + 1) % _animation!.Frames.Count;
        _image.Source = _animation.Frames[_index];
        Schedule();
    }
}

internal sealed class SlideshowBlock : MediaBlock
{
    private readonly DispatcherTimer _timer = new();
    private readonly List<string> _paths;
    private readonly Image _front = new() { Stretch = Stretch.UniformToFill };
    private readonly Image _back = new() { Stretch = Stretch.UniformToFill };
    private int _index;

    public SlideshowBlock()
    {
        _paths = Settings.Current.HomeSlides.Where(System.IO.File.Exists).ToList();
        if (_paths.Count == 0)
        {
            ShowHint(Loc.T("Escolha as imagens nas configurações"));
            return;
        }
        Content.Children.Add(_back);
        Content.Children.Add(_front);
        _front.Source = LoadImage(_paths[0]);
        _timer.Interval = TimeSpan.FromSeconds(Math.Max(Settings.Current.HomeSlideInterval, 1));
        _timer.Tick += (_, _) => Next();
        Loaded += (_, _) => { if (_paths.Count > 1) _timer.Start(); };
        Unloaded += (_, _) => _timer.Stop();
    }

    private void Next()
    {
        _index = (_index + 1) % _paths.Count;
        if (LoadImage(_paths[_index]) is not { } image) return;
        // A imagem atual vai para trás e a nova aparece por cima, com transição.
        _back.Source = _front.Source;
        _front.Source = image;
        _front.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(600)));
    }

    private static BitmapSource? LoadImage(string path)
    {
        try
        {
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.DecodePixelWidth = 700;
            image.UriSource = new Uri(path);
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch
        {
            return null;
        }
    }
}

internal sealed class ClockBlock : StackPanel
{
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly TextBlock _time = new() { FontSize = 38, FontWeight = FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Center };
    private readonly TextBlock _date = new() { HorizontalAlignment = HorizontalAlignment.Center, Foreground = new SolidColorBrush(Color.FromArgb(0x99, 255, 255, 255)) };

    public ClockBlock()
    {
        Width = 132;
        VerticalAlignment = VerticalAlignment.Center;
        Children.Add(_time);
        Children.Add(_date);
        _timer.Tick += (_, _) => Update();
        Loaded += (_, _) => { Update(); _timer.Start(); };
        Unloaded += (_, _) => _timer.Stop();
    }

    private void Update()
    {
        var now = DateTime.Now;
        _time.Text = now.ToString("HH:mm");
        _date.Text = now.ToString("ddd, d MMM");
    }
}

/// <summary>Calendário do mês, com o dia de hoje em destaque. (No Windows não há acesso aos eventos.)</summary>
internal sealed class CalendarBlock : StackPanel
{
    public CalendarBlock()
    {
        Width = 190;
        VerticalAlignment = VerticalAlignment.Center;
        var today = DateTime.Today;
        var culture = CultureInfo.CurrentCulture;
        var dim = new SolidColorBrush(Color.FromArgb(0x99, 255, 255, 255));

        var month = today.ToString("MMMM yyyy", culture);
        Children.Add(new TextBlock
        {
            Text = char.ToUpper(month[0], culture) + month[1..], FontSize = 12, FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(4, 0, 0, 4),
        });

        var grid = new UniformGrid { Columns = 7 };
        var firstDay = culture.DateTimeFormat.FirstDayOfWeek;
        for (var i = 0; i < 7; i++)
        {
            var day = (DayOfWeek)(((int)firstDay + i) % 7);
            grid.Children.Add(new TextBlock
            {
                Text = culture.DateTimeFormat.GetShortestDayName(day), FontSize = 9, Foreground = dim,
                TextAlignment = TextAlignment.Center,
            });
        }
        var first = new DateTime(today.Year, today.Month, 1);
        var offset = ((int)first.DayOfWeek - (int)firstDay + 7) % 7;
        for (var i = 0; i < offset; i++) grid.Children.Add(new TextBlock());
        for (var day = 1; day <= DateTime.DaysInMonth(today.Year, today.Month); day++)
        {
            var isToday = day == today.Day;
            grid.Children.Add(new Border
            {
                Width = 20, Height = 18, CornerRadius = new CornerRadius(9), Margin = new Thickness(0, 1, 0, 0),
                Background = isToday ? new SolidColorBrush(Color.FromRgb(0xFF, 0x45, 0x3A)) : Brushes.Transparent,
                Child = new TextBlock
                {
                    Text = day.ToString(), FontSize = 10, TextAlignment = TextAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center, FontWeight = isToday ? FontWeights.SemiBold : FontWeights.Normal,
                },
            });
        }
        Children.Add(grid);
    }
}

internal sealed class AppsBlock : Grid
{
    public AppsBlock()
    {
        Width = 156;
        VerticalAlignment = VerticalAlignment.Center;
        var apps = Settings.Current.HomeApps.Where(p => System.IO.File.Exists(p)).ToList();
        if (apps.Count == 0)
        {
            Children.Add(new TextBlock
            {
                Text = Loc.T("Arraste um app até o notch"), FontSize = 11, TextWrapping = TextWrapping.Wrap,
                TextAlignment = TextAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
                Foreground = new SolidColorBrush(Color.FromArgb(0x99, 255, 255, 255)),
            });
            return;
        }
        var panel = new WrapPanel();
        foreach (var path in apps)
        {
            var button = new Button
            {
                Style = (Style)Application.Current.FindResource("Flat"), Padding = new Thickness(4),
                ToolTip = System.IO.Path.GetFileNameWithoutExtension(path),
                Content = new Image { Source = Icon(path), Width = 38, Height = 38 },
            };
            button.Click += (_, _) =>
            {
                try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
                catch { /* atalho quebrado: nada acontece */ }
            };
            var remove = new MenuItem { Header = Loc.T("Remover atalho") };
            remove.Click += (_, _) =>
                Settings.Current.HomeApps = Settings.Current.HomeApps.Where(p => p != path).ToList();
            button.ContextMenu = new ContextMenu { Items = { remove } };
            panel.Children.Add(button);
        }
        Children.Add(panel);
    }

    private static ImageSource? Icon(string path)
    {
        try
        {
            using var icon = System.Drawing.Icon.ExtractAssociatedIcon(path);
            if (icon == null) return null;
            var image = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(icon.Handle, Int32Rect.Empty,
                BitmapSizeOptions.FromEmptyOptions());
            image.Freeze();
            return image;
        }
        catch
        {
            return null;
        }
    }
}

internal sealed class SystemMiniBlock : StackPanel
{
    public SystemMiniBlock()
    {
        Orientation = Orientation.Horizontal;
        VerticalAlignment = VerticalAlignment.Center;
        DataContext = Services.Instance.System;
        Children.Add(Ring("CPU", nameof(SystemMonitor.Cpu), Color.FromRgb(0x0A, 0x84, 0xFF)));
        Children.Add(Ring("RAM", nameof(SystemMonitor.Memory), Color.FromRgb(0xBF, 0x5A, 0xF2)));
        Children.Add(Ring(Loc.T("Disco"), nameof(SystemMonitor.Disk), Color.FromRgb(0xFF, 0x9F, 0x0A)));
    }

    private static UIElement Ring(string title, string property, Color color)
    {
        var gauge = new RingGauge { Width = 44, Height = 44, Stroke = new SolidColorBrush(color) };
        gauge.SetBinding(RingGauge.ValueProperty, new System.Windows.Data.Binding(property));
        var panel = new StackPanel { Margin = new Thickness(0, 0, 12, 0) };
        panel.Children.Add(gauge);
        panel.Children.Add(new TextBlock
        {
            Text = title, FontSize = 10, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 5, 0, 0),
            Foreground = new SolidColorBrush(Color.FromArgb(0x99, 255, 255, 255)),
        });
        return panel;
    }
}

internal sealed class TimerMiniBlock : StackPanel
{
    public TimerMiniBlock()
    {
        Width = 124;
        VerticalAlignment = VerticalAlignment.Center;
        var timers = Services.Instance.Timers;
        DataContext = timers;
        var display = new TextBlock { FontSize = 26, FontWeight = FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Center };
        display.SetBinding(TextBlock.TextProperty, new System.Windows.Data.Binding(nameof(TimerManager.Display)));
        var toggle = new Button
        {
            Style = (Style)Application.Current.FindResource("Chip"), HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 6, 0, 0),
        };
        toggle.SetBinding(ContentControl.ContentProperty, new System.Windows.Data.Binding(nameof(TimerManager.ToggleText)));
        toggle.Click += (_, _) => timers.Toggle();
        Children.Add(display);
        Children.Add(toggle);
    }
}
