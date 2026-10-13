using System.Windows;
using System.Windows.Controls;

namespace OpenNotch;

/// <summary>Bloco de música da tela inicial: capa, faixa e controles.</summary>
public partial class MusicBlock : UserControl
{
    private readonly MusicManager _music = Services.Instance.Music;

    public MusicBlock()
    {
        InitializeComponent();
        DataContext = _music;
        _music.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(MusicManager.IsPlaying)) UpdateGlyph(); };
        Loaded += (_, _) => UpdateGlyph();
    }

    private void UpdateGlyph() => PlayGlyph.Text = _music.IsPlaying ? "" : "";

    private void OnPlayPause(object sender, RoutedEventArgs e) => _music.PlayPause();
    private void OnNext(object sender, RoutedEventArgs e) => _music.Next();
    private void OnPrevious(object sender, RoutedEventArgs e) => _music.Previous();
}
