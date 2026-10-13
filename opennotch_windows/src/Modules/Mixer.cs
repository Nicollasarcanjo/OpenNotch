using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Media;
using System.Windows.Threading;

namespace OpenNotch;

public sealed class MixerApp : Observable
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public ImageSource? Icon { get; init; }

    private double _volume = 1;
    /// <summary>0 a 1. Mudar aqui aplica na hora a todas as sessões de áudio do app.</summary>
    public double Volume
    {
        get => _volume;
        set
        {
            if (!Set(ref _volume, Math.Clamp(value, 0, 1))) return;
            Raise(nameof(Percent));
            Changed?.Invoke(this);
        }
    }

    public string Percent => $"{Math.Round(Volume * 100)}%";
    internal Action<MixerApp>? Changed;

    /// <summary>Atualiza o valor mostrado sem reaplicar no sistema (leitura do estado atual).</summary>
    internal void Show(double volume)
    {
        if (Set(ref _volume, volume, nameof(Volume))) Raise(nameof(Percent));
    }
}

public sealed class MixerTab : Observable
{
    public int Id { get; init; }
    public string Title { get; init; } = "";
    public string Site { get; init; } = "";

    private double _volume = 1;
    /// <summary>0 a 1. Aplicado dentro da página pela extensão do navegador.</summary>
    public double Volume
    {
        get => _volume;
        set
        {
            if (!Set(ref _volume, Math.Clamp(value, 0, 1))) return;
            Raise(nameof(Percent));
            Changed?.Invoke(this);
        }
    }

    public string Percent => $"{Math.Round(Volume * 100)}%";
    internal Action<MixerTab>? Changed;
}

/// <summary>
/// Volume por app, sem mexer no volume geral: usa as sessões de áudio do Windows,
/// as mesmas do "Mixer de volume" do sistema. Na versão macOS isso é feito em Mixer.swift.
/// O volume por aba do navegador depende da extensão (BrowserBridge).
/// </summary>
public sealed class AudioMixer
{
    public ObservableCollection<MixerApp> Apps { get; } = [];
    public ObservableCollection<MixerTab> Tabs { get; } = [];
    public bool Active { get; set; }

    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(1.5) };
    private readonly Dictionary<string, ImageSource?> _icons = [];
    private DateTime _lastChange = DateTime.MinValue;

    public AudioMixer()
    {
        _timer.Tick += (_, _) => Refresh();
        _timer.Start();
    }

    private sealed record Session(int Pid, string Name, string Path, float Volume, bool Playing);

    public void Refresh()
    {
        if (!Active || !Settings.Current.ModMixer) return;
        // Logo depois de o usuário mexer no controle, não sobrescreve o valor com uma leitura atrasada.
        if ((DateTime.UtcNow - _lastChange).TotalSeconds < 1) return;

        var groups = new Dictionary<string, List<Session>>(StringComparer.OrdinalIgnoreCase);
        ForEachSession((pid, volume, playing) =>
        {
            if (pid == 0 || pid == Environment.ProcessId) return;
            try
            {
                using var process = Process.GetProcessById(pid);
                var path = "";
                try { path = process.MainModule?.FileName ?? ""; } catch { }
                float level = 1;
                volume.GetMasterVolume(out level);
                var session = new Session(pid, process.ProcessName, path, level, playing);
                if (!groups.TryGetValue(process.ProcessName, out var list)) groups[process.ProcessName] = list = [];
                list.Add(session);
            }
            catch
            {
                // processo fechou entre a listagem e a leitura
            }
        });

        RefreshTabs();

        // Aparece quem está tocando agora ou quem está com o volume alterado.
        var wanted = groups
            .Where(g => g.Value.Any(s => s.Playing) || g.Value.Any(s => s.Volume < 0.995f))
            .OrderBy(g => g.Key, StringComparer.CurrentCultureIgnoreCase).ToList();

        for (var i = Apps.Count - 1; i >= 0; i--)
        {
            if (wanted.All(g => !g.Key.Equals(Apps[i].Id, StringComparison.OrdinalIgnoreCase))) Apps.RemoveAt(i);
        }
        foreach (var (name, sessions) in wanted)
        {
            var level = sessions.Min(s => s.Volume);
            if (Apps.FirstOrDefault(a => a.Id.Equals(name, StringComparison.OrdinalIgnoreCase)) is { } existing)
            {
                existing.Show(level);
                continue;
            }
            var path = sessions.Select(s => s.Path).FirstOrDefault(p => p.Length > 0) ?? "";
            var app = new MixerApp { Id = name, Name = DisplayName(path, name), Icon = IconFor(path), Changed = Apply };
            app.Show(level);
            Apps.Add(app);
        }
    }

    private void RefreshTabs()
    {
        var bridge = Services.Instance.Bridge;
        var seen = bridge.ActiveTabs();
        for (var i = Tabs.Count - 1; i >= 0; i--)
        {
            if (seen.All(t => t.Id != Tabs[i].Id)) Tabs.RemoveAt(i);
        }
        foreach (var tab in seen)
        {
            if (Tabs.Any(t => t.Id == tab.Id)) continue;
            var item = new MixerTab { Id = tab.Id, Title = tab.Title, Site = tab.Site };
            item.Volume = bridge.VolumeOf(tab.Id);
            item.Changed = changed => bridge.SetVolume(changed.Id, changed.Volume);
            Tabs.Add(item);
        }
    }

    private void Apply(MixerApp app)
    {
        _lastChange = DateTime.UtcNow;
        var context = Guid.Empty;
        ForEachSession((pid, volume, _) =>
        {
            try
            {
                using var process = Process.GetProcessById(pid);
                if (process.ProcessName.Equals(app.Id, StringComparison.OrdinalIgnoreCase))
                {
                    volume.SetMasterVolume((float)app.Volume, ref context);
                }
            }
            catch
            {
                // processo fechou
            }
        });
    }

    private static string DisplayName(string path, string fallback)
    {
        try
        {
            var description = path.Length > 0 ? FileVersionInfo.GetVersionInfo(path).FileDescription : null;
            return string.IsNullOrWhiteSpace(description) ? fallback : description;
        }
        catch
        {
            return fallback;
        }
    }

    private ImageSource? IconFor(string path)
    {
        if (path.Length == 0) return null;
        if (_icons.TryGetValue(path, out var cached)) return cached;
        ImageSource? image = null;
        try
        {
            using var icon = System.Drawing.Icon.ExtractAssociatedIcon(path);
            if (icon != null)
            {
                image = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(icon.Handle,
                    System.Windows.Int32Rect.Empty, System.Windows.Media.Imaging.BitmapSizeOptions.FromEmptyOptions());
                image.Freeze();
            }
        }
        catch
        {
            // sem ícone: a linha aparece só com o nome
        }
        return _icons[path] = image;
    }

    /// <summary>Percorre as sessões de áudio da saída padrão. Falhas de COM só deixam a lista vazia.</summary>
    private static void ForEachSession(Action<int, ISimpleAudioVolume, bool> action)
    {
        IMMDeviceEnumerator? enumerator = null;
        IMMDevice? device = null;
        IAudioSessionManager2? manager = null;
        IAudioSessionEnumerator? sessions = null;
        try
        {
            enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
            if (enumerator.GetDefaultAudioEndpoint(0 /* saída */, 1 /* multimídia */, out device) != 0 || device == null) return;
            var iid = typeof(IAudioSessionManager2).GUID;
            if (device.Activate(ref iid, 23 /* CLSCTX_ALL */, IntPtr.Zero, out var raw) != 0) return;
            manager = (IAudioSessionManager2)raw;
            if (manager.GetSessionEnumerator(out sessions) != 0 || sessions == null) return;
            sessions.GetCount(out var count);
            for (var i = 0; i < count; i++)
            {
                if (sessions.GetSession(i, out var control) != 0 || control == null) continue;
                try
                {
                    control.GetProcessId(out var pid);
                    control.GetState(out var state);
                    if (control is ISimpleAudioVolume volume) action((int)pid, volume, state == 1 /* ativa */);
                }
                finally
                {
                    Marshal.ReleaseComObject(control);
                }
            }
        }
        catch
        {
            // sem dispositivo de áudio ou API indisponível
        }
        finally
        {
            if (sessions != null) Marshal.ReleaseComObject(sessions);
            if (manager != null) Marshal.ReleaseComObject(manager);
            if (device != null) Marshal.ReleaseComObject(device);
            if (enumerator != null) Marshal.ReleaseComObject(enumerator);
        }
    }

    // Interfaces COM da API de áudio do Windows (Core Audio). Só os métodos usados têm assinatura
    // de verdade; os demais existem para manter a ordem da tabela de métodos.

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    private class MMDeviceEnumerator;

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice? device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int context, IntPtr activationParams,
                                   [MarshalAs(UnmanagedType.IUnknown)] out object instance);
    }

    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionManager2
    {
        [PreserveSig] int GetAudioSessionControl(IntPtr sessionGuid, int flags, out IntPtr control);
        [PreserveSig] int GetSimpleAudioVolume(IntPtr sessionGuid, int flags, out IntPtr volume);
        [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator? enumerator);
    }

    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionEnumerator
    {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int GetSession(int index, out IAudioSessionControl2? session);
    }

    [ComImport, Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionControl2
    {
        // IAudioSessionControl
        [PreserveSig] int GetState(out int state);
        [PreserveSig] int GetDisplayName(out IntPtr name);
        [PreserveSig] int SetDisplayName(IntPtr name, IntPtr context);
        [PreserveSig] int GetIconPath(out IntPtr path);
        [PreserveSig] int SetIconPath(IntPtr path, IntPtr context);
        [PreserveSig] int GetGroupingParam(out Guid grouping);
        [PreserveSig] int SetGroupingParam(IntPtr grouping, IntPtr context);
        [PreserveSig] int RegisterAudioSessionNotification(IntPtr client);
        [PreserveSig] int UnregisterAudioSessionNotification(IntPtr client);
        // IAudioSessionControl2
        [PreserveSig] int GetSessionIdentifier(out IntPtr id);
        [PreserveSig] int GetSessionInstanceIdentifier(out IntPtr id);
        [PreserveSig] int GetProcessId(out uint pid);
    }

    [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ISimpleAudioVolume
    {
        [PreserveSig] int SetMasterVolume(float level, ref Guid context);
        [PreserveSig] int GetMasterVolume(out float level);
        [PreserveSig] int SetMute(bool mute, ref Guid context);
        [PreserveSig] int GetMute(out bool mute);
    }
}
