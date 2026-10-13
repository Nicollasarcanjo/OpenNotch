using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace OpenNotch;

/// <summary>Blocos que podem compor a tela inicial. Os mesmos ids da versão macOS (HomeBlock em Home.swift).</summary>
public static class HomeBlock
{
    public static readonly string[] All = ["music", "calendar", "apps", "gif", "slideshow", "clock", "system", "timer"];

    public static string Title(string id) => id switch
    {
        "music" => Loc.T("Música"),
        "calendar" => Loc.T("Calendário"),
        "apps" => Loc.T("Atalhos de apps"),
        "gif" => "GIF",
        "slideshow" => Loc.T("Sequência de imagens"),
        "clock" => Loc.T("Relógio"),
        "system" => Loc.T("Sistema (resumo)"),
        "timer" => Loc.T("Timer (resumo)"),
        _ => id,
    };
}

/// <summary>
/// Lê um GIF animado e devolve os quadros já montados. Os GIFs costumam guardar só a parte que
/// mudou em cada quadro, então cada um é desenhado por cima do anterior antes de ser mostrado.
/// </summary>
public static class GifFrames
{
    public sealed record Animation(List<BitmapSource> Frames, List<int> DelaysMs);

    private const long PixelBudget = 36_000_000;   // limite de memória: quadros × largura × altura

    public static Animation? Load(string path)
    {
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            var decoder = new GifBitmapDecoder(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
            if (decoder.Frames.Count == 0) return null;
            var first = decoder.Frames[0];
            var width = Query(decoder.Metadata, "/logscrdesc/Width") ?? first.PixelWidth;
            var height = Query(decoder.Metadata, "/logscrdesc/Height") ?? first.PixelHeight;
            if (width <= 0 || height <= 0) return null;

            // GIFs muito grandes ou longos: pula quadros para caber no limite.
            var step = (int)Math.Max(1, Math.Ceiling(decoder.Frames.Count * (double)width * height / PixelBudget));
            var frames = new List<BitmapSource>();
            var delays = new List<int>();
            BitmapSource? canvas = null;
            var pending = 0;
            for (var i = 0; i < decoder.Frames.Count; i++)
            {
                var frame = decoder.Frames[i];
                var meta = frame.Metadata as BitmapMetadata;
                var left = Query(meta, "/imgdesc/Left") ?? 0;
                var top = Query(meta, "/imgdesc/Top") ?? 0;
                var delay = Math.Max((Query(meta, "/grctlext/Delay") ?? 10) * 10, 20);
                var disposal = Query(meta, "/grctlext/Disposal") ?? 0;

                var visual = new DrawingVisual();
                using (var context = visual.RenderOpen())
                {
                    if (canvas != null) context.DrawImage(canvas, new Rect(0, 0, width, height));
                    context.DrawImage(frame, new Rect(left, top, frame.PixelWidth, frame.PixelHeight));
                }
                var composed = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
                composed.Render(visual);
                composed.Freeze();

                pending += delay;
                if (i % step == 0)
                {
                    frames.Add(composed);
                    delays.Add(pending);
                    pending = 0;
                }
                // Descarte 2 ou 3: o próximo quadro parte do estado de antes deste.
                if (disposal < 2) canvas = composed;
            }
            return frames.Count == 0 ? null : new Animation(frames, delays);
        }
        catch
        {
            return null;   // arquivo inválido ou que não é GIF: o bloco mostra o aviso de "escolha um GIF"
        }
    }

    private static int? Query(ImageMetadata? metadata, string query)
    {
        try
        {
            return metadata is BitmapMetadata bitmap && bitmap.ContainsQuery(query)
                ? Convert.ToInt32(bitmap.GetQuery(query)) : null;
        }
        catch
        {
            return null;
        }
    }
}
