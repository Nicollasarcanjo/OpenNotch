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
    private readonly List<(string Glyph, string Title, FrameworkElement Pane)> _panes;

    public SettingsWindow()
    {
        InitializeComponent();
        DataContext = Settings.Current;

        _panes =
        [
            ("", Loc.T("Geral"), PaneGeneral),
            ("", Loc.T("Atalhos"), PaneShortcuts),
            ("", Loc.T("Módulos"), PaneModules),
            ("", Loc.T("Agentes de IA"), PaneAgents),
            ("", Loc.T("Captura de tela"), PaneCapture),
            ("", Loc.T("Textos"), PaneTexts),
            ("", Loc.T("Timers"), PaneTimers),
            ("", Loc.T("Sobre"), PaneAbout),
        ];
        foreach (var (glyph, title, _) in _panes)
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
            _panes[i].Pane.Visibility = i == Sidebar.SelectedIndex ? Visibility.Visible : Visibility.Collapsed;
        }
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
