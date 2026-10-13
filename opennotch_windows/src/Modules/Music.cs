using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Windows.Media.Control;

namespace OpenNotch;

/// <summary>
/// Música tocando no Windows, pela API de controles de mídia do sistema. Ela cobre de uma vez
/// Spotify, navegadores e qualquer player que apareça no controle de mídia do Windows,
/// por isso aqui não é preciso a extensão de navegador que a versão macOS usa.
/// </summary>
public sealed class MusicManager : Observable
{
    private string _title = "", _artist = "", _album = "", _source = "";
    private bool _isPlaying, _hasSession;
    private ImageSource? _artwork;
    private GlobalSystemMediaTransportControlsSessionManager? _manager;
    private GlobalSystemMediaTransportControlsSession? _session;
    private string _artworkKey = "";
    private bool _busy;
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(1) };

    public string Title { get => _title; private set => Set(ref _title, value); }
    public string Artist { get => _artist; private set => Set(ref _artist, value); }
    public string Album { get => _album; private set => Set(ref _album, value); }
    public string Source { get => _source; private set => Set(ref _source, value); }
    public bool IsPlaying { get => _isPlaying; private set => Set(ref _isPlaying, value); }
    public bool HasSession { get => _hasSession; private set => Set(ref _hasSession, value); }
    public ImageSource? Artwork { get => _artwork; private set => Set(ref _artwork, value); }

    private (TimeSpan position, DateTimeOffset at)? _timeline;

    /// <summary>
    /// Posição atual da faixa, em segundos (nil se o player não informar). O Windows só atualiza
    /// a posição de vez em quando, então entre uma atualização e outra ela é estimada pelo relógio.
    /// </summary>
    public double? CurrentPosition
    {
        get
        {
            if (_timeline is not { } timeline) return null;
            var seconds = timeline.position.TotalSeconds;
            if (IsPlaying) seconds += (DateTimeOffset.Now - timeline.at).TotalSeconds;
            return seconds;
        }
    }

    public MusicManager()
    {
        if (Demo.Enabled)
        {
            _hasSession = _isPlaying = true;
            _title = "Manhã de Sol";
            _artist = "Banda Exemplo";
            _album = "Álbum de Demonstração";
            _source = "Player";
            _artwork = Demo.Artwork();
            return;
        }
        _timer.Tick += async (_, _) => await Refresh();
        _timer.Start();
    }

    private async Task Refresh()
    {
        if (_busy || !Settings.Current.ModMusic) return;
        _busy = true;
        try
        {
            _manager ??= await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            _session = _manager.GetCurrentSession();
            if (_session == null)
            {
                HasSession = false;
                IsPlaying = false;
                return;
            }
            var properties = await _session.TryGetMediaPropertiesAsync();
            var playback = _session.GetPlaybackInfo();
            HasSession = true;
            Title = properties.Title ?? "";
            Artist = properties.Artist ?? "";
            Album = properties.AlbumTitle ?? "";
            Source = FriendlyName(_session.SourceAppUserModelId);
            IsPlaying = playback?.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
            var timeline = _session.GetTimelineProperties();
            // Players que não informam a posição devolvem tudo zerado.
            _timeline = timeline != null && timeline.EndTime > TimeSpan.Zero
                ? (timeline.Position, timeline.LastUpdatedTime) : null;

            var key = $"{Title}|{Artist}|{Album}";
            if (key != _artworkKey)
            {
                _artworkKey = key;
                Artwork = await LoadArtwork(properties);
            }
        }
        catch
        {
            // A API de mídia falha de vez em quando ao trocar de player; tenta de novo no próximo ciclo.
        }
        finally
        {
            _busy = false;
        }
    }

    private static async Task<ImageSource?> LoadArtwork(GlobalSystemMediaTransportControlsSessionMediaProperties properties)
    {
        if (properties.Thumbnail == null) return null;
        try
        {
            using var stream = await properties.Thumbnail.OpenReadAsync();
            using var managed = stream.AsStreamForRead();
            var memory = new MemoryStream();
            await managed.CopyToAsync(memory);
            memory.Position = 0;
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.StreamSource = memory;
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>"Spotify.exe" ou "SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify" viram "Spotify".</summary>
    private static string FriendlyName(string id)
    {
        if (string.IsNullOrEmpty(id)) return "";
        var name = id.Contains('!') ? id[(id.LastIndexOf('!') + 1)..] : Path.GetFileNameWithoutExtension(id);
        return name.Length == 0 ? "" : char.ToUpper(name[0]) + name[1..];
    }

    public async void PlayPause()
    {
        try { if (_session != null) await _session.TryTogglePlayPauseAsync(); } catch { }
        await Refresh();
    }

    public async void Next()
    {
        try { if (_session != null) await _session.TrySkipNextAsync(); } catch { }
    }

    public async void Previous()
    {
        try { if (_session != null) await _session.TrySkipPreviousAsync(); } catch { }
    }
}
