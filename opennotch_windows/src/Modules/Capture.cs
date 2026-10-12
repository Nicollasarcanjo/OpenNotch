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
}

/// <summary>
/// Prints da tela (toda ou uma área) e galeria das últimas capturas, incluindo as feitas
/// pelo Windows com Win + PrtScn. Gravação de tela ainda não existe nesta versão.
/// </summary>
public sealed class CaptureManager : Observable
{
    public ObservableCollection<CaptureItem> Items { get; } = [];
    public event Action? BeforeCapture;
    public event Action<string>? Captured;

    private readonly List<FileSystemWatcher> _watchers = [];
    private static readonly string[] Extensions = [".png", ".jpg", ".jpeg"];

    public CaptureManager()
    {
        Watch(Paths.Captures, announce: false);
        Watch(Paths.SystemScreenshots, announce: true);
        Reload();
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
            Items.Add(new CaptureItem { Path = file.FullName, Thumbnail = Thumbnail(file.FullName) });
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

    /// <summary>Copia a imagem e também o arquivo, para colar tanto em editores quanto em pastas.</summary>
    public void Copy(string path)
    {
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
