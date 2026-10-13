using System.Windows;
using Microsoft.Win32;

namespace OpenNotch;

/// <summary>
/// Boas-vindas da primeira execução. No macOS essa tela pede as permissões do sistema;
/// no Windows não há permissões a pedir, então ela explica isso e mostra as escolhas iniciais.
/// </summary>
public partial class OnboardingWindow : Window
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

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
        using var key = Registry.CurrentUser.OpenSubKey(RunKey);
        Startup.IsChecked = key?.GetValue("OpenNotch") != null;
        SourceInitialized += (_, _) =>
            Native.UseDarkTitleBar(new System.Windows.Interop.WindowInteropHelper(this).Handle);
    }

    private void OnDone(object sender, RoutedEventArgs e)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
            if (key != null)
            {
                if (Startup.IsChecked == true && Environment.ProcessPath is { } path) key.SetValue("OpenNotch", $"\"{path}\"");
                else key.DeleteValue("OpenNotch", throwOnMissingValue: false);
            }
        }
        catch
        {
            // sem acesso ao registro: a opção pode ser mudada depois nas configurações
        }
        Settings.Current.OnboardingDone = true;
        Close();
    }
}
