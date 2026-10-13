using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Interop;

namespace OpenNotch;

public sealed class Note : Observable
{
    public Guid Id { get; set; } = Guid.NewGuid();
    private string _text = "";
    public string Text { get => _text; set { if (Set(ref _text, value)) Raise(nameof(Title)); } }
    public DateTime Updated { get; set; } = DateTime.Now;

    /// <summary>Primeira linha não vazia, usada como título na lista.</summary>
    [System.Text.Json.Serialization.JsonIgnore]
    public string Title
    {
        get
        {
            var line = Text.Split('\n').Select(l => l.Trim()).FirstOrDefault(l => l.Length > 0);
            return line ?? Loc.T("Anotação vazia");
        }
    }

    [System.Text.Json.Serialization.JsonIgnore]
    public string DateText => Updated.ToString("dd MMM");
}

/// <summary>Anotações do usuário, salvas em %APPDATA%\OpenNotch\notes.json.</summary>
public sealed class NotesStore
{
    public ObservableCollection<Note> Notes { get; } = [];
    private static string FilePath => Path.Combine(Settings.Folder, "notes.json");

    public NotesStore()
    {
        if (Demo.Enabled)
        {
            foreach (var note in Demo.Notes()) Notes.Add(note);
            return;
        }
        try
        {
            if (File.Exists(FilePath))
            {
                foreach (var note in JsonSerializer.Deserialize<List<Note>>(File.ReadAllText(FilePath)) ?? []) Notes.Add(note);
            }
        }
        catch
        {
            // arquivo corrompido: começa vazio, sem apagar o arquivo antigo até a próxima gravação
        }
    }

    public Note Add(string text = "")
    {
        var note = new Note { Text = text };
        Notes.Insert(0, note);
        Save();
        return note;
    }

    public void Delete(Note note)
    {
        Notes.Remove(note);
        Save();
    }

    public void Save()
    {
        if (Demo.Enabled) return;
        try { File.WriteAllText(FilePath, JsonSerializer.Serialize(Notes.ToList())); }
        catch { }
    }
}

public sealed class ClipItem
{
    public string Text { get; set; } = "";
    public DateTime Date { get; set; } = DateTime.Now;

    [System.Text.Json.Serialization.JsonIgnore]
    public string Preview => Text.Trim().ReplaceLineEndings(" ");
    [System.Text.Json.Serialization.JsonIgnore]
    public string Time => Date.ToString("HH:mm");
}

/// <summary>Histórico de textos copiados. Ignora o que os gerenciadores de senha marcam como confidencial.</summary>
public sealed class ClipboardManager
{
    public ObservableCollection<ClipItem> Items { get; } = [];
    private static string FilePath => Path.Combine(Settings.Folder, "clipboard.json");
    private HwndSource? _source;
    private bool _ignoreNext;

    public ClipboardManager()
    {
        if (Demo.Enabled)
        {
            foreach (var item in Demo.Copied()) Items.Add(item);
            return;
        }
        if (!Settings.Current.ClipPersist) return;
        try
        {
            if (File.Exists(FilePath))
            {
                foreach (var item in JsonSerializer.Deserialize<List<ClipItem>>(File.ReadAllText(FilePath)) ?? []) Items.Add(item);
            }
        }
        catch { }
    }

    /// <summary>Passa a ouvir a área de transferência usando a janela indicada.</summary>
    public void Attach(HwndSource source)
    {
        if (_source != null) return;
        _source = source;
        Native.AddClipboardFormatListener(source.Handle);
        source.AddHook(Hook);
    }

    private IntPtr Hook(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == Native.WM_CLIPBOARDUPDATE) Changed();
        return IntPtr.Zero;
    }

    private void Changed()
    {
        if (_ignoreNext)
        {
            _ignoreNext = false;
            return;
        }
        if (!Settings.Current.ModClipboard) return;
        try
        {
            var data = Clipboard.GetDataObject();
            // Formato que os gerenciadores de senha usam para pedir que o conteúdo não entre em históricos.
            if (data == null || data.GetDataPresent("ExcludeClipboardContentFromMonitorProcessing")) return;
            if (!data.GetDataPresent(DataFormats.UnicodeText)) return;
            var text = data.GetData(DataFormats.UnicodeText) as string;
            if (string.IsNullOrWhiteSpace(text)) return;
            for (var i = Items.Count - 1; i >= 0; i--) if (Items[i].Text == text) Items.RemoveAt(i);
            Items.Insert(0, new ClipItem { Text = text });
            var limit = Math.Max(Settings.Current.ClipLimit, 1);
            while (Items.Count > limit) Items.RemoveAt(Items.Count - 1);
            Save();
        }
        catch
        {
            // outro app está com a área de transferência aberta; o próximo aviso resolve
        }
    }

    public void Copy(ClipItem item)
    {
        try
        {
            _ignoreNext = true;
            Clipboard.SetText(item.Text);
        }
        catch
        {
            _ignoreNext = false;
        }
    }

    public void Remove(ClipItem item)
    {
        Items.Remove(item);
        Save();
    }

    public void Clear()
    {
        Items.Clear();
        Save();
    }

    public void Save()
    {
        if (Demo.Enabled) return;
        try
        {
            if (Settings.Current.ClipPersist) File.WriteAllText(FilePath, JsonSerializer.Serialize(Items.ToList()));
            else if (File.Exists(FilePath)) File.Delete(FilePath);
        }
        catch { }
    }
}
