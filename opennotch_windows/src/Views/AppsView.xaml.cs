using System.Windows;
using System.Windows.Controls;

namespace OpenNotch;

/// <summary>Gerenciador de apps abertos, com CPU, GPU e memória.</summary>
public partial class AppsView : UserControl
{
    private readonly AppMonitor _monitor = Services.Instance.Apps;

    public AppsView()
    {
        InitializeComponent();
        DataContext = _monitor;
    }

    private static T? Item<T>(object sender) where T : class => (sender as FrameworkElement)?.DataContext as T;

    private void OnSort(object sender, RoutedEventArgs e) => _monitor.Sort = (string)((Button)sender).Tag;

    private void OnToggle(object sender, RoutedEventArgs e)
    {
        if (Item<AppRow>(sender) is { HasChildren: true } app) app.Expanded = !app.Expanded;
    }

    private void OnQuit(object sender, RoutedEventArgs e)
    {
        if (Item<AppRow>(sender) is { } app) _monitor.Quit(app);
    }

    private void OnForceQuit(object sender, RoutedEventArgs e)
    {
        if (Item<AppRow>(sender) is { } app) _monitor.Quit(app, force: true);
    }

    private void OnKill(object sender, RoutedEventArgs e)
    {
        if (Item<ProcessRow>(sender) is { } process) _monitor.Kill(process);
    }
}
