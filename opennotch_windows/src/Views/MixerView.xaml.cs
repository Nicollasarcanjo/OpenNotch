using System.Windows;
using System.Windows.Controls;

namespace OpenNotch;

/// <summary>Volume de cada app com áudio.</summary>
public partial class MixerView : UserControl
{
    private readonly AudioMixer _mixer = Services.Instance.Mixer;

    public MixerView()
    {
        InitializeComponent();
        DataContext = _mixer;
        _mixer.Apps.CollectionChanged += (_, _) => UpdateEmpty();
        // Só consulta as sessões de áudio enquanto a aba está na tela.
        Loaded += (_, _) => { _mixer.Active = true; _mixer.Refresh(); UpdateEmpty(); };
        Unloaded += (_, _) => _mixer.Active = false;
        UpdateEmpty();
    }

    private void UpdateEmpty() =>
        Empty.Visibility = _mixer.Apps.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
}
