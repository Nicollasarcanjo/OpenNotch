using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows.Media;
using System.Windows.Threading;

namespace OpenNotch;

public sealed class TrayFile
{
    public string Path { get; init; } = "";
    public string Name => System.IO.Path.GetFileName(Path);
    public ImageSource? Icon { get; init; }
}

/// <summary>Bandeja de arquivos: solte arquivos no notch para guardar e arraste para fora depois.</summary>
public sealed class TrayStore
{
    public ObservableCollection<TrayFile> Items { get; } = [];
    private static string FilePath => Path.Combine(Settings.Folder, "tray.json");

    public TrayStore()
    {
        try
        {
            if (!File.Exists(FilePath)) return;
            foreach (var path in JsonSerializer.Deserialize<List<string>>(File.ReadAllText(FilePath)) ?? [])
            {
                if (File.Exists(path) || Directory.Exists(path)) Items.Add(Make(path));
            }
        }
        catch { }
    }

    private static TrayFile Make(string path)
    {
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
            // pastas e alguns tipos não têm ícone associado
        }
        return new TrayFile { Path = path, Icon = image };
    }

    public void Add(IEnumerable<string> paths)
    {
        foreach (var path in paths)
        {
            if (Items.Any(i => string.Equals(i.Path, path, StringComparison.OrdinalIgnoreCase))) continue;
            Items.Add(Make(path));
        }
        Save();
    }

    public void Remove(TrayFile file)
    {
        Items.Remove(file);
        Save();
    }

    public void Clear()
    {
        Items.Clear();
        Save();
    }

    private void Save()
    {
        try { File.WriteAllText(FilePath, JsonSerializer.Serialize(Items.Select(i => i.Path).ToList())); }
        catch { }
    }
}

public sealed class DownloadItem
{
    public string Name { get; init; } = "";
    public string Path { get; init; } = "";
    public long Bytes { get; init; }
    public bool Finished { get; init; }
    public string Detail => Finished ? Loc.T("Concluído") : Paths.FormatBytes(Bytes);
}

/// <summary>
/// Downloads em andamento, pelos arquivos temporários que os navegadores criam na pasta Downloads.
/// O Windows não informa o tamanho total, então aparece o quanto já foi baixado, sem porcentagem.
/// </summary>
public sealed class DownloadsMonitor : Observable
{
    public ObservableCollection<DownloadItem> Items { get; } = [];
    public event Action<DownloadItem>? Finished;

    private bool _downloading;
    public bool Downloading { get => _downloading; private set => Set(ref _downloading, value); }

    private static readonly string[] TempExtensions = [".crdownload", ".part", ".opdownload", ".download"];
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(1) };
    private HashSet<string> _active = [];
    private readonly List<DownloadItem> _recent = [];

    public DownloadsMonitor()
    {
        _timer.Tick += (_, _) => Poll();
        _timer.Start();
    }

    private void Poll()
    {
        if (!Settings.Current.ModDownloads || !Directory.Exists(Paths.Downloads))
        {
            if (Items.Count > 0) Items.Clear();
            Downloading = false;
            return;
        }
        var current = new List<DownloadItem>();
        try
        {
            foreach (var file in new DirectoryInfo(Paths.Downloads).EnumerateFiles())
            {
                var extension = file.Extension.ToLowerInvariant();
                if (!TempExtensions.Contains(extension)) continue;
                current.Add(new DownloadItem
                {
                    // "arquivo.zip.crdownload" aparece como "arquivo.zip"
                    Name = System.IO.Path.GetFileNameWithoutExtension(file.Name),
                    Path = file.FullName,
                    Bytes = file.Length,
                });
            }
        }
        catch
        {
            return;
        }

        var names = current.Select(c => c.Path).ToHashSet();
        foreach (var gone in _active.Where(path => !names.Contains(path)))
        {
            // O temporário sumiu: se o arquivo final existe, terminou; senão foi cancelado.
            var final = System.IO.Path.Combine(Paths.Downloads, System.IO.Path.GetFileNameWithoutExtension(gone));
            if (!File.Exists(final)) continue;
            var done = new DownloadItem { Name = System.IO.Path.GetFileName(final), Path = final, Finished = true };
            _recent.Insert(0, done);
            if (_recent.Count > 5) _recent.RemoveAt(_recent.Count - 1);
            Finished?.Invoke(done);
        }
        _active = names;
        Downloading = current.Count > 0;

        Items.Clear();
        foreach (var item in current.Concat(_recent)) Items.Add(item);
    }

    public void ClearFinished()
    {
        _recent.Clear();
        Poll();
    }

    public void Reveal(DownloadItem item)
    {
        try
        {
            var target = File.Exists(item.Path) ? $"/select,\"{item.Path}\"" : $"\"{Paths.Downloads}\"";
            Process.Start("explorer.exe", target);
        }
        catch { }
    }
}
