using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace OpenNotch;

/// <summary>Aba Arquivos: bandeja à esquerda e downloads à direita.</summary>
public partial class FilesView : UserControl
{
    private readonly TrayStore _tray = Services.Instance.Tray;
    private readonly DownloadsMonitor _downloads = Services.Instance.Downloads;
    private Point _dragStart;

    public FilesView()
    {
        InitializeComponent();
        var settings = Settings.Current;
        TrayPanel.DataContext = _tray;
        DownloadItems.ItemsSource = _downloads.Items;
        if (!settings.ModTray)
        {
            TrayPanel.Visibility = Visibility.Collapsed;
            TrayColumn.Width = new GridLength(0);
            DownloadsColumn.Width = new GridLength(1, GridUnitType.Star);
        }
        if (!settings.ModDownloads)
        {
            DownloadsPanel.Visibility = Visibility.Collapsed;
            DownloadsColumn.Width = new GridLength(0);
        }
        _tray.Items.CollectionChanged += (_, _) => UpdateEmpty();
        _downloads.Items.CollectionChanged += (_, _) => UpdateEmpty();
        UpdateEmpty();
    }

    private void UpdateEmpty()
    {
        var hasFiles = _tray.Items.Count > 0;
        TrayEmpty.Visibility = hasFiles ? Visibility.Collapsed : Visibility.Visible;
        ClearTray.Visibility = hasFiles ? Visibility.Visible : Visibility.Collapsed;
        DownloadsEmpty.Visibility = _downloads.Items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private static T? Item<T>(object sender) where T : class
    {
        if (sender is MenuItem { Parent: ContextMenu { PlacementTarget: FrameworkElement target } }) return target.DataContext as T;
        return (sender as FrameworkElement)?.DataContext as T;
    }

    private void OnFileDown(object sender, MouseButtonEventArgs e)
    {
        _dragStart = e.GetPosition(this);
        if (e.ClickCount == 2 && Item<TrayFile>(sender) is { } file) Open(file.Path);
    }

    /// <summary>Arrastar o arquivo para fora do notch, para outra pasta ou app.</summary>
    private void OnDragOut(object sender, MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed || Item<TrayFile>(sender) is not { } file) return;
        var moved = e.GetPosition(this) - _dragStart;
        if (Math.Abs(moved.X) < SystemParameters.MinimumHorizontalDragDistance
            && Math.Abs(moved.Y) < SystemParameters.MinimumVerticalDragDistance) return;
        var data = new DataObject(DataFormats.FileDrop, new[] { file.Path });
        DragDrop.DoDragDrop((DependencyObject)sender, data, DragDropEffects.Copy | DragDropEffects.Move);
    }

    private static void Open(string path)
    {
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
        catch { }
    }

    private void OnOpenFile(object sender, RoutedEventArgs e)
    {
        if (Item<TrayFile>(sender) is { } file) Open(file.Path);
    }

    private void OnRemoveFile(object sender, RoutedEventArgs e)
    {
        if (Item<TrayFile>(sender) is { } file) _tray.Remove(file);
    }

    private void OnClearTray(object sender, RoutedEventArgs e) => _tray.Clear();
    private void OnClearDownloads(object sender, RoutedEventArgs e) => _downloads.ClearFinished();

    private void OnReveal(object sender, RoutedEventArgs e)
    {
        if (Item<DownloadItem>(sender) is { } item) _downloads.Reveal(item);
    }
}
