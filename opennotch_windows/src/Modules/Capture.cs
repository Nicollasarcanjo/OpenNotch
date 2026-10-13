using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace OpenNotch;

public sealed class CaptureItem
{
    public string Path { get; init; } = "";
    public ImageSource? Thumbnail { get; init; }
    public string Name => System.IO.Path.GetFileName(Path);
    public bool IsVideo => System.IO.Path.GetExtension(Path).Equals(".mp4", StringComparison.OrdinalIgnoreCase);
    public bool IsImage => !IsVideo;
}

/// <summary>
/// Prints da tela (toda ou uma área) e galeria das últimas capturas, incluindo as feitas
/// pelo Windows com Win + PrtScn. A gravação em si fica em ScreenRecorder.
/// </summary>
public sealed class CaptureManager : Observable
{
    public ObservableCollection<CaptureItem> Items { get; } = [];
    public event Action? BeforeCapture;
    public event Action<string>? Captured;

    private readonly List<FileSystemWatcher> _watchers = [];
    private static readonly string[] Extensions = [".png", ".jpg", ".jpeg", ".mp4"];
    public ScreenRecorder Recorder { get; } = new();

    public CaptureManager()
    {
        Watch(Paths.Captures, announce: false);
        Watch(Paths.SystemScreenshots, announce: true);
        Reload();
        Recorder.Finished += path =>
        {
            Reload();
            if (path == null) return;
            if (Settings.Current.CaptureAutoCopy) Copy(path);
            Captured?.Invoke(path);
        };
    }

    private void Watch(string folder, bool announce)
    {
        if (!Directory.Exists(folder)) return;
        try
        {
            var watcher = new FileSystemWatcher(folder) { EnableRaisingEvents = true };
            watcher.Created += (_, e) => Application.Current?.Dispatcher.BeginInvoke(async () =>
            {
                await Task.Delay(700);   // espera o arquivo terminar de ser gravado
                Reload();
                if (announce && Settings.Current.ModCapture && IsImage(e.FullPath)) Captured?.Invoke(e.FullPath);
            });
            watcher.Deleted += (_, _) => Application.Current?.Dispatcher.BeginInvoke(Reload);
            _watchers.Add(watcher);
        }
        catch
        {
            // pasta sem permissão de leitura: a galeria só não se atualiza sozinha
        }
    }

    private static bool IsImage(string path) =>
        Extensions.Contains(System.IO.Path.GetExtension(path).ToLowerInvariant());

    public void Reload()
    {
        var files = new List<FileInfo>();
        foreach (var folder in new[] { Paths.Captures, Paths.SystemScreenshots })
        {
            if (!Directory.Exists(folder)) continue;
            try { files.AddRange(new DirectoryInfo(folder).EnumerateFiles().Where(f => IsImage(f.FullName))); }
            catch { }
        }
        Items.Clear();
        foreach (var file in files.OrderByDescending(f => f.LastWriteTimeUtc)
                     .Take(Math.Max(Settings.Current.CaptureGalleryCount, 1)))
        {
            var video = file.Extension.Equals(".mp4", StringComparison.OrdinalIgnoreCase);
            Items.Add(new CaptureItem { Path = file.FullName, Thumbnail = video ? null : Thumbnail(file.FullName) });
        }
    }

    private static ImageSource? Thumbnail(string path)
    {
        try
        {
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;   // não deixa o arquivo travado
            image.DecodePixelWidth = 300;
            image.UriSource = new Uri(path);
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch
        {
            return null;
        }
    }

    public async void Screenshot(bool region)
    {
        BeforeCapture?.Invoke();
        await Task.Delay(350);   // espera o notch fechar para não sair no print
        System.Drawing.Rectangle bounds = System.Windows.Forms.SystemInformation.VirtualScreen;
        if (region)
        {
            var selected = RegionSelector.Select();
            if (selected is not { } area) return;
            bounds = area;
            await Task.Delay(120);   // espera a tela de seleção sumir
        }
        try
        {
            using var bitmap = new System.Drawing.Bitmap(bounds.Width, bounds.Height);
            using (var graphics = System.Drawing.Graphics.FromImage(bitmap))
            {
                graphics.CopyFromScreen(bounds.Left, bounds.Top, 0, 0, bounds.Size);
            }
            var path = System.IO.Path.Combine(Paths.Captures,
                $"{Loc.T("Captura")} {DateTime.Now:yyyy-MM-dd HH.mm.ss}.png");
            bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
            Reload();
            if (Settings.Current.CaptureAutoCopy) Copy(path);
            Captured?.Invoke(path);
        }
        catch
        {
            // captura bloqueada (ex.: tela protegida): nada é salvo
        }
    }

    /// <summary>Começa a gravar a tela toda ou uma área; se já estiver gravando, para.</summary>
    public async void ToggleRecording(bool region)
    {
        if (Recorder.IsRecording)
        {
            Recorder.Stop();
            return;
        }
        if (Recorder.IsBusy) return;
        BeforeCapture?.Invoke();
        await Task.Delay(350);
        System.Drawing.Rectangle bounds = System.Windows.Forms.Screen.PrimaryScreen?.Bounds
            ?? System.Windows.Forms.SystemInformation.VirtualScreen;
        if (region)
        {
            if (RegionSelector.Select() is not { } area) return;
            bounds = area;
            await Task.Delay(120);
        }
        Recorder.Start(bounds);
    }

    /// <summary>Abre o editor de marcações; o resultado entra na galeria e já vai copiado.</summary>
    public void Annotate(string path)
    {
        try
        {
            var editor = new AnnotateWindow(path);
            editor.Saved += saved =>
            {
                Reload();
                Copy(saved);
            };
            editor.Show();
            editor.Activate();
        }
        catch
        {
            // arquivo apagado ou ilegível: nada abre
        }
    }

    /// <summary>Copia a imagem e também o arquivo, para colar tanto em editores quanto em pastas.</summary>
    public void Copy(string path)
    {
        if (System.IO.Path.GetExtension(path).Equals(".mp4", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var files = new DataObject();
                files.SetFileDropList([path]);
                Clipboard.SetDataObject(files, true);
            }
            catch { }
            return;
        }
        try
        {
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.UriSource = new Uri(path);
            image.EndInit();
            var data = new DataObject();
            data.SetImage(image);
            data.SetFileDropList([path]);
            Clipboard.SetDataObject(data, true);
        }
        catch
        {
            // área de transferência ocupada por outro app
        }
    }

    public void Open(string path)
    {
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
        catch { }
    }

    public void OpenFolder() => Open(Paths.Captures);
}
