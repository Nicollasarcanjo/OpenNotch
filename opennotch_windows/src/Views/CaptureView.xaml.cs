using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace OpenNotch;

/// <summary>Botões de print e gravação, e a galeria das últimas capturas.</summary>
public partial class CaptureView : UserControl
{
    private readonly CaptureManager _capture = Services.Instance.Capture;

    public CaptureView()
    {
        InitializeComponent();
        DataContext = _capture;
        _capture.Items.CollectionChanged += (_, _) => UpdateEmpty();
        _capture.Recorder.PropertyChanged += (_, _) => UpdateRecording();
        UpdateEmpty();
        UpdateRecording();
    }

    private void UpdateEmpty() =>
        Empty.Visibility = _capture.Items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

    /// <summary>Gravando: o botão vira "Parar" com o tempo. Montando o vídeo: tudo fica desabilitado.</summary>
    private void UpdateRecording()
    {
        var recorder = _capture.Recorder;
        RecordButton.Content = recorder.IsRecording ? $"■  {Loc.T("Parar")}  {recorder.Elapsed}"
            : recorder.IsEncoding ? Loc.T("Processando vídeo…") : Loc.T("Gravar tela");
        RecordButton.IsEnabled = !recorder.IsEncoding;
        RecordRegionButton.Visibility = recorder.IsBusy ? Visibility.Collapsed : Visibility.Visible;
        FullButton.IsEnabled = RegionButton.IsEnabled = !recorder.IsBusy;
    }

    private static CaptureItem? Item(object sender) => (sender as FrameworkElement)?.DataContext as CaptureItem;

    private void OnFull(object sender, RoutedEventArgs e) => _capture.Screenshot(region: false);
    private void OnRegion(object sender, RoutedEventArgs e) => _capture.Screenshot(region: true);
    private void OnRecord(object sender, RoutedEventArgs e) => _capture.ToggleRecording(region: false);
    private void OnRecordRegion(object sender, RoutedEventArgs e) => _capture.ToggleRecording(region: true);
    private void OnFolder(object sender, RoutedEventArgs e) => _capture.OpenFolder();

    private void OnCopy(object sender, MouseButtonEventArgs e)
    {
        if (Item(sender) is { } item) _capture.Copy(item.Path);
    }

    private void OnOpen(object sender, MouseButtonEventArgs e)
    {
        if (Item(sender) is { } item) _capture.Open(item.Path);
    }

    private void OnAnnotate(object sender, RoutedEventArgs e)
    {
        e.Handled = true;   // não deixa o clique chegar à miniatura e copiar
        if (Item(sender) is { } item) _capture.Annotate(item.Path);
    }
}
