using System.Globalization;
using System.Net.Http;
using System.Text.Json;
using System.Windows.Threading;

namespace OpenNotch;

/// <summary>
/// Letra sincronizada da música que está tocando, mostrada verso a verso no notch fechado.
/// Mesma lógica da versão macOS (Lyrics.swift): a letra vem do LRCLIB (lrclib.net), para onde
/// vão o título, o artista e o álbum da faixa. Nada é guardado em disco.
/// </summary>
public sealed class LyricsManager : Observable
{
    private string _line = "";
    /// <summary>Verso atual; vazio quando não há letra, a música está parada ou o recurso está desligado.</summary>
    public string Line { get => _line; private set => Set(ref _line, value); }

    private readonly MusicManager _music;
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(350) };
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(12) };
    private List<(double Time, string Text)> _lines = [];
    private string _trackKey = "";

    public LyricsManager(MusicManager music)
    {
        _music = music;
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("OpenNotch (https://github.com/Nicollasarcanjo/OpenNotch)");
        _timer.Tick += (_, _) => Tick();
        _timer.Start();
    }

    private static bool Enabled => Settings.Current.ModMusic && Settings.Current.LyricsEnabled;

    private void Tick()
    {
        var key = $"{_music.Title}|{_music.Artist}|{_music.Album}";
        if (key != _trackKey)
        {
            _trackKey = key;
            _lines = [];
            Line = "";
            if (Enabled && _music.Title.Length > 0) _ = Fetch(_music.Title, _music.Artist, _music.Album, key);
        }
        if (!Enabled || !_music.IsPlaying || _lines.Count == 0 || _music.CurrentPosition is not { } position)
        {
            Line = "";
            return;
        }
        var current = "";
        foreach (var (time, text) in _lines)
        {
            if (time > position + 0.15) break;
            current = text;
        }
        Line = current;
    }

    private async Task Fetch(string title, string artist, string album, string key)
    {
        try
        {
            // Primeiro a faixa exata; se não houver, a busca aberta por título e artista.
            var synced = await Synced($"get?track_name={Uri.EscapeDataString(title)}&artist_name={Uri.EscapeDataString(artist)}"
                + (album.Length > 0 ? $"&album_name={Uri.EscapeDataString(album)}" : ""), single: true)
                ?? await Synced($"search?track_name={Uri.EscapeDataString(title)}&artist_name={Uri.EscapeDataString(artist)}", single: false);
            if (synced != null && _trackKey == key) _lines = Parse(synced);   // a faixa pode ter mudado
        }
        catch
        {
            // sem internet ou serviço fora do ar: a música segue sem letra
        }
    }

    private async Task<string?> Synced(string query, bool single)
    {
        using var response = await _http.GetAsync("https://lrclib.net/api/" + query);
        if (!response.IsSuccessStatusCode) return null;
        var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;
        if (single) return NonEmpty(json.Str("syncedLyrics"));
        if (json.ValueKind != JsonValueKind.Array) return null;
        foreach (var item in json.EnumerateArray())
        {
            if (NonEmpty(item.Str("syncedLyrics")) is { } found) return found;
        }
        return null;
    }

    private static string? NonEmpty(string value) => value.Length > 0 ? value : null;

    /// <summary>Formato LRC: "[mm:ss.xx] verso", com uma ou mais marcações de tempo por linha.</summary>
    public static List<(double Time, string Text)> Parse(string lrc)
    {
        var result = new List<(double, string)>();
        foreach (var raw in lrc.Split('\n'))
        {
            var rest = raw.Trim();
            var times = new List<double>();
            while (rest.StartsWith('[') && rest.IndexOf(']') is var close and > 0)
            {
                var stamp = rest[1..close].Split(':');
                if (stamp.Length == 2
                    && double.TryParse(stamp[0], NumberStyles.Float, CultureInfo.InvariantCulture, out var minutes)
                    && double.TryParse(stamp[1], NumberStyles.Float, CultureInfo.InvariantCulture, out var seconds))
                {
                    times.Add(minutes * 60 + seconds);
                }
                rest = rest[(close + 1)..];
            }
            var text = rest.Trim();
            foreach (var time in times) result.Add((time, text));
        }
        return result.OrderBy(l => l.Item1).ToList();
    }
}
