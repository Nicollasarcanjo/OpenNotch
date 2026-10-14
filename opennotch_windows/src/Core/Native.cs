using System.Runtime.InteropServices;

namespace OpenNotch;

/// <summary>Chamadas diretas à API do Windows que o .NET não expõe.</summary>
internal static partial class Native
{
    public const int WM_HOTKEY = 0x0312;
    public const int WM_CLIPBOARDUPDATE = 0x031D;
    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_TOOLWINDOW = 0x00000080;
    public const uint MOD_ALT = 0x0001, MOD_CONTROL = 0x0002, MOD_NOREPEAT = 0x4000;

    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint key);

    [DllImport("user32.dll")]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll")]
    public static extern bool AddClipboardFormatListener(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool RemoveClipboardFormatListener(IntPtr hWnd);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    public static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    public static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int index, IntPtr value);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hWnd, int attribute, ref int value, int size);

    /// <summary>Barra de título escura, para combinar com o conteúdo (Windows 10 2004 ou mais recente).</summary>
    public static void UseDarkTitleBar(IntPtr handle)
    {
        var enabled = 1;
        try { DwmSetWindowAttribute(handle, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, ref enabled, sizeof(int)); }
        catch { /* Windows antigo: a barra fica clara */ }
    }

    public const uint WDA_NONE = 0x0, WDA_EXCLUDEFROMCAPTURE = 0x11;

    /// <summary>Define se a janela aparece em capturas de tela (Windows 10 2004 ou mais recente).</summary>
    [DllImport("user32.dll")]
    public static extern bool SetWindowDisplayAffinity(IntPtr hWnd, uint affinity);

    // MARK: Tela cheia

    public const int WS_EX_TRANSPARENT = 0x00000020, WS_EX_NOACTIVATE = 0x08000000;
    private const uint SWP_NOSIZE = 0x0001, SWP_NOMOVE = 0x0002, SWP_NOACTIVATE = 0x0010, SWP_NOOWNERZORDER = 0x0200;
    private static readonly IntPtr HWND_TOPMOST = new(-1);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder name, int size);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int width, int height, uint flags);

    [DllImport("shell32.dll")]
    private static extern int SHQueryUserNotificationState(out int state);

    /// <summary>
    /// A janela em primeiro plano ocupa a tela inteira (jogo, vídeo, apresentação)? A área de
    /// trabalho e as janelas do próprio OpenNotch não contam.
    /// </summary>
    public static bool IsFullscreenOn(System.Drawing.Rectangle screen)
    {
        var window = GetForegroundWindow();
        if (window == IntPtr.Zero) return false;
        GetWindowThreadProcessId(window, out var pid);
        if (pid == Environment.ProcessId) return false;
        var name = new System.Text.StringBuilder(64);
        GetClassName(window, name, name.Capacity);
        if (name.ToString() is "Progman" or "WorkerW" or "Shell_TrayWnd") return false;
        if (GetWindowRect(window, out var r)
            && r.Left <= screen.Left && r.Top <= screen.Top && r.Right >= screen.Right && r.Bottom >= screen.Bottom)
            return true;
        // Tela cheia exclusiva (Direct3D): o tamanho da janela pode não bater com o da tela.
        return SHQueryUserNotificationState(out var state) == 0 && state == 3 /* QUNS_RUNNING_D3D_FULL_SCREEN */
            && System.Windows.Forms.Screen.FromHandle(window).Bounds == screen;
    }

    /// <summary>Recoloca a janela acima das outras "sempre visíveis" sem tirar o foco do app atual.</summary>
    public static void KeepOnTop(IntPtr handle) =>
        SetWindowPos(handle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);

    [DllImport("kernel32.dll")]
    public static extern bool GetSystemTimes(out long idle, out long kernel, out long user);

    [StructLayout(LayoutKind.Sequential)]
    public struct MemoryStatus
    {
        public uint Length;
        public uint MemoryLoad;
        public ulong TotalPhys, AvailPhys, TotalPageFile, AvailPageFile, TotalVirtual, AvailVirtual, AvailExtendedVirtual;
    }

    [DllImport("kernel32.dll")]
    public static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);

    public static (ulong total, ulong available) Memory()
    {
        var status = new MemoryStatus { Length = (uint)Marshal.SizeOf<MemoryStatus>() };
        return GlobalMemoryStatusEx(ref status) ? (status.TotalPhys, status.AvailPhys) : (1, 0);
    }
}
