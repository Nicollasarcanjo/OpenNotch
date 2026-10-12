using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace OpenNotch;

/// <summary>Botões de print e galeria das últimas capturas.</summary>
public partial class CaptureView : UserControl
{
    private readonly CaptureManager _capture = Services.Instance.Capture;

    public CaptureView()
    {
        InitializeComponent();
        DataContext = _capture;
        _capture.Items.CollectionChanged += (_, _) => UpdateEmpty();
        UpdateEmpty();
    }

    private void UpdateEmpty() =>
        Empty.Visibility = _capture.Items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

    private static CaptureItem? Item(object sender) => (sender as FrameworkElement)?.DataContext as CaptureItem;

    private void OnFull(object sender, RoutedEventArgs e) => _capture.Screenshot(region: false);
    private void OnRegion(object sender, RoutedEventArgs e) => _capture.Screenshot(region: true);
    private void OnFolder(object sender, RoutedEventArgs e) => _capture.OpenFolder();

    private void OnCopy(object sender, MouseButtonEventArgs e)
    {
        if (Item(sender) is { } item) _capture.Copy(item.Path);
    }

    private void OnOpen(object sender, MouseButtonEventArgs e)
    {
        if (Item(sender) is { } item) _capture.Open(item.Path);
    }
}
