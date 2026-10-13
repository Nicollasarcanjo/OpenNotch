using System.IO;
using System.Windows;
using System.Windows.Threading;
using Windows.Media.Editing;
using Windows.Media.MediaProperties;
using Windows.Media.Transcoding;
using Windows.Storage;

namespace OpenNotch;

/// <summary>
/// Gravação de tela. Captura um quadro por vez, como os prints, e ao parar junta tudo num MP4
/// com o montador de vídeo do Windows. É simples e não depende de nada externo, mas tem limites:
/// cerca de 8 quadros por segundo, sem áudio e no máximo 3 minutos por gravação.
/// </summary>
public sealed class ScreenRecorder : Observable
{
    private const int IntervalMs = 125;                       // ~8 quadros por segundo
    private static readonly TimeSpan Limit = TimeSpan.FromMinutes(3);
    private const int MaxWidth = 1920;

    private bool _isRecording, _isEncoding;
    private DateTime _started;
    private string _folder = "";
    private CancellationTokenSource? _cancel;
    private Task<int>? _capture;
    private readonly DispatcherTimer _clock = new() { Interval = TimeSpan.FromSeconds(1) };

    public bool IsRecording { get => _isRecording; private set { if (Set(ref _isRecording, value)) Raise(nameof(IsBusy)); } }
    public bool IsEncoding { get => _isEncoding; private set { if (Set(ref _isEncoding, value)) Raise(nameof(IsBusy)); } }
    public bool IsBusy => IsRecording || IsEncoding;
    public string Elapsed => IsRecording ? (DateTime.Now - _started).ToString(@"mm\:ss") : "";

    /// <summary>Caminho do vídeo pronto, ou null se a montagem falhou.</summary>
    public event Action<string?>? Finished;

    public ScreenRecorder()
    {
        _clock.Tick += (_, _) =>
        {
            Raise(nameof(Elapsed));
            if (IsRecording && DateTime.Now - _started >= Limit) Stop();
        };
    }

    public void Start(System.Drawing.Rectangle bounds)
    {
        if (IsBusy) return;
        // Largura e altura pares (exigência do codificador) e reduzidas se a tela for muito grande.
        var scale = Math.Min(1.0, MaxWidth / (double)bounds.Width);
        var size = new System.Drawing.Size((int)(bounds.Width * scale) / 2 * 2, (int)(bounds.Height * scale) / 2 * 2);
        if (size.Width < 16 || size.Height < 16) return;

        _folder = Path.Combine(Path.GetTempPath(), "OpenNotchRec-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_folder);
        _cancel = new CancellationTokenSource();
        var token = _cancel.Token;
        var folder = _folder;
        _capture = Task.Run(() => CaptureLoop(bounds, size, folder, token));
        _started = DateTime.Now;
        IsRecording = true;
        Raise(nameof(Elapsed));
        _clock.Start();
    }

    private static int CaptureLoop(System.Drawing.Rectangle bounds, System.Drawing.Size size, string folder, CancellationToken token)
    {
        var encoder = System.Drawing.Imaging.ImageCodecInfo.GetImageEncoders().First(c => c.FormatID == System.Drawing.Imaging.ImageFormat.Jpeg.Guid);
        using var quality = new System.Drawing.Imaging.EncoderParameters(1);
        quality.Param[0] = new System.Drawing.Imaging.EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 82L);
        using var screen = new System.Drawing.Bitmap(bounds.Width, bounds.Height);
        using var frame = new System.Drawing.Bitmap(size.Width, size.Height);
        using var fromScreen = System.Drawing.Graphics.FromImage(screen);
        using var toFrame = System.Drawing.Graphics.FromImage(frame);
        var count = 0;
        var next = DateTime.UtcNow;
        while (!token.IsCancellationRequested)
        {
            try
            {
                fromScreen.CopyFromScreen(bounds.Left, bounds.Top, 0, 0, bounds.Size);
                // A captura não inclui o ponteiro do mouse; ele é desenhado por cima.
                var cursor = System.Windows.Forms.Cursor.Position;
                System.Windows.Forms.Cursors.Default.Draw(fromScreen,
                    new System.Drawing.Rectangle(cursor.X - bounds.Left, cursor.Y - bounds.Top, 32, 32));
                toFrame.DrawImage(screen, 0, 0, size.Width, size.Height);
                frame.Save(Path.Combine(folder, $"{count:000000}.jpg"), encoder, quality);
                count++;
            }
            catch
            {
                // um quadro perdido (ex.: tela bloqueada) não interrompe a gravação
            }
            next = next.AddMilliseconds(IntervalMs);
            var wait = next - DateTime.UtcNow;
            if (wait > TimeSpan.Zero) Thread.Sleep(wait); else next = DateTime.UtcNow;
        }
        return count;
    }

    public async void Stop()
    {
        if (!IsRecording || _capture == null) return;
        _clock.Stop();
        _cancel?.Cancel();
        IsRecording = false;
        IsEncoding = true;
        string? result = null;
        try
        {
            var frames = await _capture;
            if (frames > 0) result = await Encode(_folder, frames);
        }
        catch
        {
            result = null;   // sem o montador de vídeo do Windows, a gravação não pode ser salva
        }
        finally
        {
            try { Directory.Delete(_folder, true); } catch { }
            IsEncoding = false;
        }
        Finished?.Invoke(result);
    }

    private static async Task<string?> Encode(string folder, int frames)
    {
        var composition = new MediaComposition();
        var duration = TimeSpan.FromMilliseconds(IntervalMs);
        uint width = 0, height = 0;
        for (var i = 0; i < frames; i++)
        {
            var path = Path.Combine(folder, $"{i:000000}.jpg");
            if (!File.Exists(path)) continue;
            var file = await StorageFile.GetFileFromPathAsync(path);
            if (width == 0)
            {
                var properties = await file.Properties.GetImagePropertiesAsync();
                width = properties.Width;
                height = properties.Height;
            }
            composition.Clips.Add(await MediaClip.CreateFromImageFileAsync(file, duration));
        }
        if (composition.Clips.Count == 0 || width == 0) return null;

        var target = await StorageFolder.GetFolderFromPathAsync(Paths.Captures);
        var name = $"{Loc.T("Gravação")} {DateTime.Now:yyyy-MM-dd HH.mm.ss}.mp4";
        var output = await target.CreateFileAsync(name, CreationCollisionOption.GenerateUniqueName);
        var profile = MediaEncodingProfile.CreateMp4(VideoEncodingQuality.HD1080p);
        profile.Audio = null;
        profile.Video.Width = width;
        profile.Video.Height = height;
        profile.Video.FrameRate.Numerator = 1000 / IntervalMs;
        profile.Video.FrameRate.Denominator = 1;
        var status = await composition.RenderToFileAsync(output, MediaTrimmingPreference.Fast, profile);
        return status == TranscodeFailureReason.None ? output.Path : null;
    }
}
