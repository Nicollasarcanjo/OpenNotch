using System.IO;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;

namespace OpenNotch;

/// <summary>Janela de configurações. Tudo é ligado direto às preferências (Settings).</summary>
public partial class SettingsWindow : Window
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private readonly Updater _updater = Services.Instance.Updater;

    public SettingsWindow()
    {
        InitializeComponent();
        DataContext = Settings.Current;
        VersionText.Text = "OpenNotch " + Updater.Current;
        using (var key = Registry.CurrentUser.OpenSubKey(RunKey))
        {
            Startup.IsChecked = key?.GetValue("OpenNotch") != null;
        }
        foreach (ComboBoxItem item in Language.Items)
        {
            if ((string)item.Tag == Settings.Current.Language) Language.SelectedItem = item;
        }
        LanguageNote.Visibility = Visibility.Collapsed;
        _updater.PropertyChanged += (_, _) => ShowUpdate();
        ShowUpdate();
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

    private void OnLanguage(object sender, SelectionChangedEventArgs e)
    {
        if (Language.SelectedItem is not ComboBoxItem item || !IsLoaded) return;
        Settings.Current.Language = (string)item.Tag;
        LanguageNote.Visibility = Visibility.Visible;
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

    private void OnQuit(object sender, RoutedEventArgs e) => Application.Current.Shutdown();
}
