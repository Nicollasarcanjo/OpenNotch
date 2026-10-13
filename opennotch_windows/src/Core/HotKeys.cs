using System.Windows.Input;
using System.Windows.Interop;

namespace OpenNotch;

public enum Shortcut { ToggleNotch = 1, Texts, Capture, RecordRegion }

/// <summary>Atalhos globais. As mesmas combinações da versão macOS, com Ctrl + Alt no lugar de ⌃⌥.</summary>
public sealed class HotKeys
{
    public event Action<Shortcut>? Pressed;
    private readonly IntPtr _handle;
    private bool _registered;

    private static readonly Dictionary<Shortcut, Key> Keys = new()
    {
        [Shortcut.ToggleNotch] = Key.N,
        [Shortcut.Texts] = Key.V,
        [Shortcut.Capture] = Key.S,
        [Shortcut.RecordRegion] = Key.R,
    };

    public HotKeys(HwndSource source)
    {
        _handle = source.Handle;
        source.AddHook(Hook);
    }

    public void SetEnabled(bool enabled)
    {
        if (enabled == _registered) return;
        foreach (var (shortcut, key) in Keys)
        {
            if (enabled)
            {
                Native.RegisterHotKey(_handle, (int)shortcut, Native.MOD_CONTROL | Native.MOD_ALT | Native.MOD_NOREPEAT,
                    (uint)KeyInterop.VirtualKeyFromKey(key));
            }
            else
            {
                Native.UnregisterHotKey(_handle, (int)shortcut);
            }
        }
        _registered = enabled;
    }

    private IntPtr Hook(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == Native.WM_HOTKEY && Enum.IsDefined(typeof(Shortcut), wParam.ToInt32()))
        {
            Pressed?.Invoke((Shortcut)wParam.ToInt32());
            handled = true;
        }
        return IntPtr.Zero;
    }
}
