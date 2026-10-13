using System.Windows;

namespace OpenNotch;

/// <summary>
/// Boas-vindas da primeira execução. No macOS essa tela pede as permissões do sistema;
/// no Windows não há permissões a pedir, então ela explica isso e mostra as escolhas iniciais.
/// </summary>
public partial class OnboardingWindow : Window
{
    public OnboardingWindow()
    {
        InitializeComponent();
        DataContext = Settings.Current;
        try
        {
            // O .ico tem vários tamanhos; sem escolher, o WPF pega o menor e amplia.
            var resource = Application.GetResourceStream(new Uri("pack://application:,,,/Resources/AppIcon.ico"));
            if (resource != null)
            {
                var decoder = new System.Windows.Media.Imaging.IconBitmapDecoder(resource.Stream,
                    System.Windows.Media.Imaging.BitmapCreateOptions.None, System.Windows.Media.Imaging.BitmapCacheOption.OnLoad);
                Logo.Source = decoder.Frames.OrderByDescending(f => f.PixelWidth).First();
            }
        }
        catch
        {
            // sem o ícone, a tela abre só com o texto
        }
        LoadStartup();
        SourceInitialized += (_, _) =>
            Native.UseDarkTitleBar(new System.Windows.Interop.WindowInteropHelper(this).Handle);
    }

    private async void LoadStartup() => Startup.IsChecked = await AutoStart.IsEnabled();

    private async void OnDone(object sender, RoutedEventArgs e)
    {
        await AutoStart.Set(Startup.IsChecked == true);
        Settings.Current.OnboardingDone = true;
        Close();
    }
}
