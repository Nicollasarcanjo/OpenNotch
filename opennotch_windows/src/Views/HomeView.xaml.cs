using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;

namespace OpenNotch;

/// <summary>Tela inicial: música tocando e relógio.</summary>
public partial class HomeView : UserControl
{
    private readonly MusicManager _music = Services.Instance.Music;
    private readonly DispatcherTimer _clock = new() { Interval = TimeSpan.FromSeconds(1) };

    public HomeView()
    {
        InitializeComponent();
        MusicPanel.DataContext = _music;
        MusicPanel.Visibility = Settings.Current.ModMusic ? Visibility.Visible : Visibility.Collapsed;
        _music.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(MusicManager.IsPlaying)) UpdateGlyph(); };
        _clock.Tick += (_, _) => UpdateClock();
        Loaded += (_, _) => { UpdateClock(); UpdateGlyph(); _clock.Start(); };
        Unloaded += (_, _) => _clock.Stop();
    }

    private void UpdateGlyph() => PlayGlyph.Text = _music.IsPlaying ? "" : "";

    private void UpdateClock()
    {
        var now = DateTime.Now;
        ClockTime.Text = now.ToString("HH:mm");
        ClockDate.Text = now.ToString("ddd, d MMM");
    }

    private void OnPlayPause(object sender, RoutedEventArgs e) => _music.PlayPause();
    private void OnNext(object sender, RoutedEventArgs e) => _music.Next();
    private void OnPrevious(object sender, RoutedEventArgs e) => _music.Previous();
}
