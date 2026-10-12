using System.Windows;
using System.Windows.Media;

namespace OpenNotch;

/// <summary>Anel de progresso, igual aos indicadores da aba Sistema na versão macOS.</summary>
public sealed class RingGauge : FrameworkElement
{
    public static readonly DependencyProperty ValueProperty = DependencyProperty.Register(
        nameof(Value), typeof(double), typeof(RingGauge),
        new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty StrokeProperty = DependencyProperty.Register(
        nameof(Stroke), typeof(Brush), typeof(RingGauge),
        new FrameworkPropertyMetadata(Brushes.White, FrameworkPropertyMetadataOptions.AffectsRender));

    /// <summary>De 0 a 1.</summary>
    public double Value { get => (double)GetValue(ValueProperty); set => SetValue(ValueProperty, value); }
    public Brush Stroke { get => (Brush)GetValue(StrokeProperty); set => SetValue(StrokeProperty, value); }

    private const double Thickness = 6;
    private static readonly Pen TrackPen = Frozen(new Pen(new SolidColorBrush(Color.FromArgb(0x1F, 255, 255, 255)), Thickness));

    private static Pen Frozen(Pen pen)
    {
        pen.Freeze();
        return pen;
    }

    protected override void OnRender(DrawingContext context)
    {
        var radius = Math.Min(ActualWidth, ActualHeight) / 2 - Thickness / 2;
        if (radius <= 0) return;
        var center = new Point(ActualWidth / 2, ActualHeight / 2);
        context.DrawEllipse(null, TrackPen, center, radius, radius);

        var value = Math.Clamp(double.IsNaN(Value) ? 0 : Value, 0, 1);
        if (value <= 0.001) return;
        var pen = new Pen(Stroke, Thickness) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        if (value >= 0.999)
        {
            context.DrawEllipse(null, pen, center, radius, radius);
            return;
        }
        // Arco a partir do topo, no sentido horário.
        var angle = value * 2 * Math.PI;
        var start = new Point(center.X, center.Y - radius);
        var end = new Point(center.X + radius * Math.Sin(angle), center.Y - radius * Math.Cos(angle));
        var geometry = new StreamGeometry();
        using (var path = geometry.Open())
        {
            path.BeginFigure(start, false, false);
            path.ArcTo(end, new Size(radius, radius), 0, value > 0.5, SweepDirection.Clockwise, true, false);
        }
        geometry.Freeze();
        context.DrawGeometry(null, pen, geometry);
    }
}
