using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Interop;
using Microsoft.Win32;

namespace OpenNotch;

/// <summary>
/// Janela de configurações, com o mesmo desenho da versão macOS: barra lateral com os painéis
/// e seções em cartões. Tudo é ligado direto às preferências (Settings).
/// </summary>
public partial class SettingsWindow : Window
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private readonly Updater _updater = Services.Instance.Updater;
    private readonly List<(string Id, string Glyph, string Title, FrameworkElement[] Panes)> _panes;
    private readonly System.Windows.Threading.DispatcherTimer _statusTimer = new() { Interval = TimeSpan.FromSeconds(2) };

    public SettingsWindow()
    {
        InitializeComponent();
        DataContext = Settings.Current;

        _panes =
        [
            ("general", "\uE713", Loc.T("Geral"), [PaneGeneral]),
            ("shortcuts", "\uE765", Loc.T("Atalhos"), [PaneShortcuts]),
            ("home", "\uE80F", Loc.T("Tela inicial"), [PaneHome]),
            ("modules", "\uF0E2", Loc.T("Módulos"), [PaneModules]),
            ("lyrics", "\uE8D6", Loc.T("Letra da música"), [PaneLyrics]),
            ("extension", "\uEA86", Loc.T("Extensão do navegador"), [PaneExtension]),
            ("agents", "\uE99A", Loc.T("Agentes de IA"), [PaneAgents]),
            ("capture", "\uE722", Loc.T("Captura de tela"), [PaneCapture]),
            ("texts", "\uE8A5", Loc.T("Textos"), [PaneTexts]),
            ("timers", "\uE916", Loc.T("Timers"), [PaneTimers]),
            ("about", "\uE946", Loc.T("Sobre"), [PaneAbout]),
        ];
        foreach (var (_, glyph, title, _) in _panes)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            row.Children.Add(new TextBlock
            {
                Text = glyph, FontFamily = (System.Windows.Media.FontFamily)FindResource("Icons"), FontSize = 14,
                Width = 24, VerticalAlignment = VerticalAlignment.Center,
            });
            row.Children.Add(new TextBlock { Text = title, FontSize = 13, VerticalAlignment = VerticalAlignment.Center });
            Sidebar.Items.Add(new ListBoxItem { Content = row });
        }
        Sidebar.SelectedIndex = 0;

        BuildModules();
        BuildChoices();
        BuildHome();
        BuildCustomAgents();
        BuildExtension();
        BuildLyrics();
        Settings.Current.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName?.StartsWith("Home") == true) BuildHome();
            if (e.PropertyName?.StartsWith("Lyrics") == true) UpdateLyricPreview();
        };
        _statusTimer.Tick += (_, _) => UpdateExtensionStatus();
        _statusTimer.Start();
        Closed += (_, _) => _statusTimer.Stop();

        VersionText.Text = Updater.Current;
        using (var key = Registry.CurrentUser.OpenSubKey(RunKey))
        {
            Startup.IsChecked = key?.GetValue("OpenNotch") != null;
        }
        _updater.PropertyChanged += (_, _) => ShowUpdate();
        ShowUpdate();
        SourceInitialized += (_, _) => Native.UseDarkTitleBar(new WindowInteropHelper(this).Handle);
    }

    private void OnPane(object sender, SelectionChangedEventArgs e)
    {
        if (_panes == null) return;
        for (var i = 0; i < _panes.Count; i++)
        {
            foreach (var pane in _panes[i].Panes)
            {
                pane.Visibility = i == Sidebar.SelectedIndex ? Visibility.Visible : Visibility.Collapsed;
            }
        }
    }

    public IEnumerable<string> PaneIds => _panes.Select(p => p.Id);

    /// <summary>Mostra um painel pelo id ("home", "agents"…).</summary>
    public void Select(string id)
    {
        var index = _panes.FindIndex(p => p.Id == id);
        if (index >= 0) Sidebar.SelectedIndex = index;
    }

    // MARK: Tela inicial

    private DockPanel Row(string title, params UIElement[] trailing)
    {
        var row = new DockPanel { Style = (Style)FindResource("Row") };
        foreach (var element in trailing.Reverse())
        {
            DockPanel.SetDock(element, Dock.Right);
            row.Children.Add(element);
        }
        row.Children.Add(new TextBlock { Style = (Style)FindResource("RowLabel"), Text = title, TextTrimming = TextTrimming.CharacterEllipsis });
        return row;
    }

    private Button Small(string text, Action action, string? tip = null)
    {
        var button = new Button { Style = (Style)FindResource("Push"), Content = text, Padding = new Thickness(9, 2, 9, 2), Margin = new Thickness(6, 0, 0, 0), ToolTip = tip };
        button.Click += (_, _) => action();
        return button;
    }

    private void Fill(Panel host, IEnumerable<UIElement> rows)
    {
        host.Children.Clear();
        var first = true;
        foreach (var row in rows)
        {
            if (!first) host.Children.Add(new Border { Style = (Style)FindResource("Divider") });
            host.Children.Add(row);
            first = false;
        }
    }

    private void BuildHome()
    {
        var settings = Settings.Current;
        var blocks = settings.HomeBlocks;
        Fill(BlockRows, blocks.Select((id, index) => (UIElement)Row(HomeBlock.Title(id),
            Small("←", () => Move(index, -1), Loc.T("Mover para a esquerda")),
            Small("→", () => Move(index, 1), Loc.T("Mover para a direita")),
            Small("✕", () => settings.HomeBlocks = blocks.Where(b => b != id).ToList(), Loc.T("Tirar da tela inicial")))));
        if (blocks.Count == 0) BlockRows.Children.Add(Row(Loc.T("A tela inicial está vazia")));

        BlockAdd.Children.Clear();
        foreach (var id in HomeBlock.All.Where(b => !blocks.Contains(b)))
        {
            var add = Small("+ " + HomeBlock.Title(id), () => settings.HomeBlocks = [.. settings.HomeBlocks, id]);
            add.Margin = new Thickness(0, 0, 6, 6);
            BlockAdd.Children.Add(add);
        }

        Fill(AppRows, settings.HomeApps.Select(path => (UIElement)Row(System.IO.Path.GetFileNameWithoutExtension(path),
            Small("✕", () => settings.HomeApps = settings.HomeApps.Where(p => p != path).ToList(), Loc.T("Remover atalho")))));
        GifName.Text = settings.HomeGif.Length == 0 ? Loc.T("Nenhum") : System.IO.Path.GetFileName(settings.HomeGif);
        SlidesCount.Text = settings.HomeSlides.Count == 0 ? Loc.T("Nenhuma") : Loc.T("{0} selecionadas", settings.HomeSlides.Count);
    }

    private static void Move(int index, int offset)
    {
        var blocks = Settings.Current.HomeBlocks.ToList();
        var target = index + offset;
        if (index < 0 || index >= blocks.Count || target < 0 || target >= blocks.Count) return;
        (blocks[index], blocks[target]) = (blocks[target], blocks[index]);
        Settings.Current.HomeBlocks = blocks;
    }

    private void OnAddApp(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = "Apps|*.exe;*.lnk", Multiselect = true };
        if (dialog.ShowDialog(this) != true) return;
        foreach (var file in dialog.FileNames) Settings.Current.AddHomeApp(file);
    }

    private void OnChooseGif(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = "GIF|*.gif" };
        if (dialog.ShowDialog(this) != true) return;
        Settings.Current.HomeGif = dialog.FileName;
        if (!Settings.Current.HomeBlocks.Contains("gif")) Settings.Current.HomeBlocks = [.. Settings.Current.HomeBlocks, "gif"];
    }

    private void OnRemoveGif(object sender, RoutedEventArgs e) => Settings.Current.HomeGif = "";

    private void OnChooseSlides(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = "Imagens|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp", Multiselect = true };
        if (dialog.ShowDialog(this) != true) return;
        Settings.Current.HomeSlides = dialog.FileNames.OrderBy(f => f, StringComparer.CurrentCultureIgnoreCase).ToList();
        if (!Settings.Current.HomeBlocks.Contains("slideshow")) Settings.Current.HomeBlocks = [.. Settings.Current.HomeBlocks, "slideshow"];
    }

    private void OnRemoveSlides(object sender, RoutedEventArgs e) => Settings.Current.HomeSlides = [];

    // MARK: Ferramentas de IA cadastradas

    private void BuildCustomAgents()
    {
        var agents = Settings.Current.CustomAgents;
        Fill(CustomRows, agents.Select((agent, index) =>
        {
            TextBox Field(string value, string tip, double width, Action<string> apply)
            {
                var box = new TextBox
                {
                    Text = value, Width = width, ToolTip = tip, Padding = new Thickness(6, 3, 6, 3), Margin = new Thickness(0, 0, 6, 0),
                    Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0x3A, 0x3A, 0x3C)),
                    Foreground = System.Windows.Media.Brushes.White, CaretBrush = System.Windows.Media.Brushes.White,
                    BorderThickness = new Thickness(0),
                };
                // Grava ao sair do campo, para não reescrever o arquivo a cada tecla.
                box.LostFocus += (_, _) => apply(box.Text);
                return box;
            }
            var row = new DockPanel { Style = (Style)FindResource("Row") };
            var remove = Small("✕", () =>
            {
                Settings.Current.CustomAgents = Settings.Current.CustomAgents.Where((_, i) => i != index).ToList();
                BuildCustomAgents();
            });
            DockPanel.SetDock(remove, Dock.Right);
            row.Children.Add(remove);
            row.Children.Add(Field(agent.Name, Loc.T("Nome"), 150, text => Update(index, a => a.Name = text)));
            row.Children.Add(Field(agent.Match, Loc.T("Trecho do nome do processo (ex.: cursor)"), 230, text => Update(index, a => a.Match = text)));
            return (UIElement)row;
        }));
    }

    private static void Update(int index, Action<CustomAgent> change)
    {
        var agents = Settings.Current.CustomAgents.Select(a => new CustomAgent { Name = a.Name, Match = a.Match }).ToList();
        if (index < 0 || index >= agents.Count) return;
        change(agents[index]);
        Settings.Current.CustomAgents = agents;
    }

    private void OnAddCustom(object sender, RoutedEventArgs e)
    {
        Settings.Current.CustomAgents = [.. Settings.Current.CustomAgents, new CustomAgent()];
        BuildCustomAgents();
    }

    // MARK: Letra da música

    private void BuildLyrics()
    {
        var settings = Settings.Current;
        Choice(LyricFontChoice, settings.LyricsFont, value => settings.LyricsFont = value,
            (Loc.T("Padrão"), "system"), (Loc.T("Arredondada"), "rounded"), (Loc.T("Serifada"), "serif"),
            (Loc.T("Monoespaçada"), "mono"));
        Swatches(LyricColors, () => settings.LyricsColor, value => settings.LyricsColor = value);
        Swatches(LyricOutlineColors, () => settings.LyricsOutlineColor, value => settings.LyricsOutlineColor = value);
        LyricPreview.Text = Loc.T("Um verso de exemplo");
        UpdateLyricPreview();
    }

    private void UpdateLyricPreview() => LyricStyle.Apply(LyricPreview);

    /// <summary>Fileira de cores para escolher; a escolhida fica com o contorno mais grosso.</summary>
    private static void Swatches(Panel host, Func<string> current, Action<string> apply)
    {
        foreach (var hex in LyricStyle.Palette)
        {
            var swatch = new System.Windows.Shapes.Ellipse
            {
                Width = 18, Height = 18, Margin = new Thickness(6, 0, 0, 0), Cursor = System.Windows.Input.Cursors.Hand,
                Fill = LyricStyle.Brush(hex), Stroke = System.Windows.Media.Brushes.White, Tag = hex,
                StrokeThickness = hex == current() ? 2 : 0.5,
            };
            swatch.MouseLeftButtonDown += (_, _) =>
            {
                apply(hex);
                foreach (System.Windows.Shapes.Ellipse other in host.Children)
                {
                    other.StrokeThickness = (string)other.Tag == hex ? 2 : 0.5;
                }
            };
            host.Children.Add(swatch);
        }
    }

    // MARK: Extensão do navegador

    private void BuildExtension()
    {
        string[] steps =
        [
            Loc.T("Clique em “Baixar extensão” e salve o arquivo OpenNotch-Extensao.zip."),
            Loc.T("Clique com o botão direito no .zip e escolha “Extrair tudo”. Vai aparecer a pasta OpenNotch-Extensao."),
            Loc.T("No navegador, abra a página de extensões: brave://extensions, chrome://extensions ou edge://extensions."),
            Loc.T("Ligue o “Modo do desenvolvedor”, no canto superior direito."),
            Loc.T("Clique em “Carregar sem compactação” e escolha a pasta OpenNotch-Extensao."),
            Loc.T("Recarregue a aba onde o som está tocando."),
        ];
        Fill(ExtensionSteps, steps.Select((step, index) =>
        {
            var row = new DockPanel { Style = (Style)FindResource("Row"), LastChildFill = true };
            row.Children.Add(new TextBlock { Text = (index + 1) + ".", Width = 22, FontWeight = FontWeights.SemiBold, Foreground = (System.Windows.Media.Brush)FindResource("Accent") });
            row.Children.Add(new TextBlock { Text = step, TextWrapping = TextWrapping.Wrap, FontSize = 13 });
            return (UIElement)row;
        }));
        UpdateExtensionStatus();
    }

    private void UpdateExtensionStatus()
    {
        var last = Services.Instance.Bridge.LastContact;
        var connected = last is { } at && (DateTime.UtcNow - at).TotalSeconds < 8;
        ExtensionStatus.Text = connected ? Loc.T("Conectada")
            : last == null ? Loc.T("Ainda sem contato com a extensão") : Loc.T("Nenhuma aba tocando som");
    }

    private void OnDownloadExtension(object sender, RoutedEventArgs e)
    {
        var dialog = new SaveFileDialog { FileName = "OpenNotch-Extensao.zip", Filter = "ZIP|*.zip" };
        if (dialog.ShowDialog(this) != true) return;
        ExtensionMessage.Text = BrowserExtension.SaveZip(dialog.FileName)
            ? Loc.T("Extensão salva. Agora siga os passos abaixo.") : Loc.T("Não foi possível salvar o arquivo.");
    }

    /// <summary>Uma linha com interruptor para cada módulo.</summary>
    private void BuildModules()
    {
        (string Title, string Property)[] modules =
        [
            (Loc.T("Música"), nameof(Settings.ModMusic)),
            (Loc.T("Agentes de IA"), nameof(Settings.ModAgents)),
            (Loc.T("Gerenciador de apps abertos"), nameof(Settings.ModApps)),
            (Loc.T("Volume por app"), nameof(Settings.ModMixer)),
            (Loc.T("Captura de tela"), nameof(Settings.ModCapture)),
            (Loc.T("Anotações"), nameof(Settings.ModNotes)),
            (Loc.T("Histórico de textos copiados"), nameof(Settings.ModClipboard)),
            (Loc.T("Bandeja de arquivos"), nameof(Settings.ModTray)),
            (Loc.T("Progresso de downloads"), nameof(Settings.ModDownloads)),
            (Loc.T("Timers"), nameof(Settings.ModTimers)),
            (Loc.T("Monitor do sistema"), nameof(Settings.ModSystem)),
        ];
        for (var i = 0; i < modules.Length; i++)
        {
            if (i > 0) ModuleRows.Children.Add(new Border { Style = (Style)FindResource("Divider") });
            var toggle = new CheckBox { Style = (Style)FindResource("Switch") };
            toggle.SetBinding(System.Windows.Controls.Primitives.ToggleButton.IsCheckedProperty,
                new Binding(modules[i].Property) { Mode = BindingMode.TwoWay });
            DockPanel.SetDock(toggle, Dock.Right);
            var row = new DockPanel { Style = (Style)FindResource("Row") };
            row.Children.Add(toggle);
            row.Children.Add(new TextBlock { Style = (Style)FindResource("RowLabel"), Text = modules[i].Title });
            ModuleRows.Children.Add(row);
        }
    }

    private void BuildChoices()
    {
        var settings = Settings.Current;
        Choice(LanguageChoice, settings.Language, value =>
        {
            settings.Language = value;
            LanguageNote.Visibility = Visibility.Visible;
        }, (Loc.T("Igual ao do sistema"), ""), ("Português", "pt-BR"), ("English", "en"));
        Choice(ClaudeWindowChoice, settings.AgentsClaudeWindow, value => settings.AgentsClaudeWindow = value,
            (Loc.T("200 mil tokens"), 200_000), (Loc.T("1 milhão de tokens"), 1_000_000));
        Choice(HideIdleChoice, settings.AgentsHideIdleHours, value => settings.AgentsHideIdleHours = value,
            (Loc.T("1 hora"), 1), (Loc.T("12 horas"), 12), (Loc.T("24 horas"), 24), (Loc.T("Nunca esconder"), 0));
    }

    /// <summary>Controle segmentado: uma opção marcada por vez, aplicada ao clicar.</summary>
    private void Choice<T>(Panel host, T current, Action<T> apply, params (string Title, T Value)[] options)
    {
        var group = Guid.NewGuid().ToString();
        foreach (var (title, value) in options)
        {
            var option = new RadioButton
            {
                Style = (Style)FindResource("Segment"),
                Content = title,
                GroupName = group,
                IsChecked = EqualityComparer<T>.Default.Equals(value, current),
            };
            option.Checked += (_, _) => { if (IsLoaded) apply(value); };
            host.Children.Add(option);
        }
    }

    private void ShowUpdate()
    {
        UpdateStatus.Text = _updater.Status;
        DownloadButton.Visibility = _updater.Available ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnStartup(object sender, RoutedEventArgs e)
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
        if (key == null) return;
        if (Startup.IsChecked == true && Environment.ProcessPath is { } path) key.SetValue("OpenNotch", $"\"{path}\"");
        else key.DeleteValue("OpenNotch", throwOnMissingValue: false);
    }

    private async void OnCheckUpdate(object sender, RoutedEventArgs e) => await _updater.Check();
    private void OnDownload(object sender, RoutedEventArgs e) => _updater.OpenDownloadPage();

    private void OnExport(object sender, RoutedEventArgs e)
    {
        var dialog = new SaveFileDialog { FileName = "OpenNotch-config.json", Filter = "JSON|*.json" };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            File.WriteAllText(dialog.FileName, Settings.Current.Export());
            TransferMessage.Text = Loc.T("Configurações exportadas.");
        }
        catch
        {
            TransferMessage.Text = Loc.T("Não foi possível salvar o arquivo.");
        }
    }

    private void OnImport(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = "JSON|*.json" };
        if (dialog.ShowDialog(this) != true) return;
        bool ok;
        try { ok = Settings.Current.Import(File.ReadAllText(dialog.FileName)); }
        catch { ok = false; }
        TransferMessage.Text = ok ? Loc.T("Configurações importadas.") : Loc.T("Esse arquivo não é uma exportação do OpenNotch.");
    }

    private void OnWelcome(object sender, RoutedEventArgs e) => new OnboardingWindow().Show();
    private void OnQuit(object sender, RoutedEventArgs e) => Application.Current.Shutdown();
}
