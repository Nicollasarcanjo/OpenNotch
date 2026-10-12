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
        using var key = Registry.CurrentUser.OpenSubKey(RunKey);
        Startup.IsChecked = key?.GetValue("OpenNotch") != null;
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
