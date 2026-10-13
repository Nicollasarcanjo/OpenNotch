using System.Runtime.InteropServices;
using Microsoft.Win32;
using Windows.ApplicationModel;

namespace OpenNotch;

/// <summary>
/// O app roda de dois jeitos: avulso (o .exe baixado do GitHub) ou empacotado (MSIX, pela
/// Microsoft Store). O que muda entre os dois fica concentrado aqui.
/// </summary>
internal static class Packaged
{
    private const int NoPackage = 15700;   // APPMODEL_ERROR_NO_PACKAGE

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetCurrentPackageFullName(ref int length, System.Text.StringBuilder? name);

    /// <summary>true quando o app foi instalado como pacote MSIX.</summary>
    public static bool IsPackaged { get; } = Check();

    private static bool Check()
    {
        try
        {
            var length = 0;
            return GetCurrentPackageFullName(ref length, null) != NoPackage;
        }
        catch
        {
            return false;
        }
    }
}

/// <summary>
/// Abrir junto com o Windows. Avulso, é uma entrada no registro do usuário; empacotado, é a
/// tarefa de inicialização declarada no manifesto (AppxManifest.xml).
/// </summary>
internal static class AutoStart
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string TaskId = "OpenNotchStartup";

    public static async Task<bool> IsEnabled()
    {
        try
        {
            if (Packaged.IsPackaged)
            {
                var task = await StartupTask.GetAsync(TaskId);
                return task.State is StartupTaskState.Enabled or StartupTaskState.EnabledByPolicy;
            }
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue("OpenNotch") != null;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Liga ou desliga. Devolve o estado final, que pode ser diferente do pedido: se o usuário
    /// desligou o app no Gerenciador de Tarefas, o Windows não deixa o app religar sozinho.
    /// </summary>
    public static async Task<bool> Set(bool enabled)
    {
        try
        {
            if (Packaged.IsPackaged)
            {
                var task = await StartupTask.GetAsync(TaskId);
                if (enabled) await task.RequestEnableAsync(); else task.Disable();
                return await IsEnabled();
            }
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
            if (key == null) return false;
            if (enabled && Environment.ProcessPath is { } path) key.SetValue("OpenNotch", $"\"{path}\"");
            else key.DeleteValue("OpenNotch", throwOnMissingValue: false);
            return enabled;
        }
        catch
        {
            return await IsEnabled();   // sem acesso: mostra o estado real
        }
    }
}
