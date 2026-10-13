using System.Globalization;
using System.Windows;
using System.Windows.Media;

namespace OpenNotch;

/// <summary>
/// Texto de uma linha com borda opcional, usado para o verso da música.
/// O WPF não tem contorno de texto pronto, então o texto vira um desenho com preenchimento e traço.
/// </summary>
public sealed class OutlinedText : FrameworkElement
{
    private string _text = "";
    private Geometry? _geometry;
    private Size _size;

    public FontFamily Family { get; set; } = new("Segoe UI");
    public double Size { get; set; } = 12;
    public bool Bold { get; set; } = true;
    public Brush Fill { get; set; } = Brushes.White;
    public Brush? Stroke { get; set; }
    public double StrokeWidth { get; set; }

    public string Text
    {
        get => _text;
        set
        {
            if (_text == value) return;
            _text = value;
            Refresh();
        }
    }

    /// <summary>Refaz o desenho depois de mudar o texto ou a aparência.</summary>
    public void Refresh()
    {
        var formatted = new FormattedText(_text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface(Family, FontStyles.Normal, Bold ? FontWeights.SemiBold : FontWeights.Normal, FontStretches.Normal),
            Size, Brushes.White, VisualTreeHelper.GetDpi(this).PixelsPerDip);
        _size = new Size(formatted.WidthIncludingTrailingWhitespace, formatted.Height);
        _geometry = formatted.BuildGeometry(new Point(0, 0));
        _geometry.Freeze();
        InvalidateMeasure();
        InvalidateVisual();
    }

    /// <summary>Largura que o texto ocupa, para o notch saber o quanto crescer.</summary>
    public double TextWidth => _size.Width;

    protected override Size MeasureOverride(Size availableSize) => _size;

    protected override void OnRender(DrawingContext context)
    {
        if (_geometry == null) return;
        if (Stroke != null && StrokeWidth > 0)
        {
            // A borda é desenhada antes e com o dobro da espessura; o preenchimento cobre a metade de dentro.
            context.DrawGeometry(null, new Pen(Stroke, StrokeWidth * 2) { LineJoin = PenLineJoin.Round }, _geometry);
        }
        context.DrawGeometry(Fill, null, _geometry);
    }
}

/// <summary>Aparência do verso, escolhida nas configurações. Mesmas opções da versão macOS.</summary>
public static class LyricStyle
{
    public static readonly string[] Palette =
        ["#FFFFFF", "#FFD60A", "#FF9F0A", "#FF453A", "#FF375F", "#BF5AF2", "#0A84FF", "#64D2FF", "#30D158", "#000000"];

    public static Brush Brush(string hex)
    {
        try
        {
            var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
            brush.Freeze();
            return brush;
        }
        catch
        {
            return Brushes.White;
        }
    }

    public static FontFamily Font(string id) => new(id switch
    {
        "rounded" => "Segoe UI Variable Display, Segoe UI",
        "serif" => "Georgia, Times New Roman",
        "mono" => "Cascadia Mono, Consolas",
        _ => "Segoe UI Variable Text, Segoe UI",
    });

    public static void Apply(OutlinedText target)
    {
        var settings = Settings.Current;
        target.Family = Font(settings.LyricsFont);
        target.Size = Math.Clamp(settings.LyricsSize, 8, 24);
        target.Bold = settings.LyricsBold;
        target.Fill = Brush(settings.LyricsColor);
        target.Stroke = settings.LyricsOutline ? Brush(settings.LyricsOutlineColor) : null;
        target.StrokeWidth = settings.LyricsOutline ? settings.LyricsOutlineWidth : 0;
        target.Refresh();
    }
}
