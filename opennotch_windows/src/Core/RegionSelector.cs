using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;

namespace OpenNotch;

/// <summary>
/// Seleção de uma área da tela arrastando o mouse. Devolve o retângulo em pixels da tela,
/// ou null se o usuário cancelar com Esc ou soltar sem arrastar.
/// </summary>
public static class RegionSelector
{
    public static System.Drawing.Rectangle? Select()
    {
        var bounds = System.Windows.Forms.SystemInformation.VirtualScreen;
        var window = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = new SolidColorBrush(Color.FromArgb(70, 0, 0, 0)),
            Topmost = true,
            ShowInTaskbar = false,
            ResizeMode = ResizeMode.NoResize,
            Cursor = Cursors.Cross,
            WindowStartupLocation = WindowStartupLocation.Manual,
        };
        var canvas = new Canvas();
        var box = new Rectangle { Stroke = Brushes.White, StrokeThickness = 1, Fill = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)), Visibility = Visibility.Collapsed };
        canvas.Children.Add(box);
        window.Content = canvas;

        // A janela cobre todas as telas; o WPF trabalha em unidades independentes de DPI.
        window.SourceInitialized += (_, _) =>
        {
            var scale = PresentationSource.FromVisual(window)?.CompositionTarget?.TransformToDevice.M11 ?? 1;
            window.Left = bounds.Left / scale;
            window.Top = bounds.Top / scale;
            window.Width = bounds.Width / scale;
            window.Height = bounds.Height / scale;
        };

        Point? start = null;
        System.Drawing.Rectangle? result = null;
        window.MouseLeftButtonDown += (_, e) =>
        {
            start = e.GetPosition(canvas);
            box.Visibility = Visibility.Visible;
            window.CaptureMouse();
        };
        window.MouseMove += (_, e) =>
        {
            if (start is not { } origin) return;
            var point = e.GetPosition(canvas);
            Canvas.SetLeft(box, Math.Min(origin.X, point.X));
            Canvas.SetTop(box, Math.Min(origin.Y, point.Y));
            box.Width = Math.Abs(point.X - origin.X);
            box.Height = Math.Abs(point.Y - origin.Y);
        };
        window.MouseLeftButtonUp += (_, e) =>
        {
            if (start is { } origin)
            {
                var point = e.GetPosition(canvas);
                var scale = PresentationSource.FromVisual(window)?.CompositionTarget?.TransformToDevice.M11 ?? 1;
                var width = Math.Abs(point.X - origin.X) * scale;
                var height = Math.Abs(point.Y - origin.Y) * scale;
                if (width >= 8 && height >= 8)
                {
                    result = new System.Drawing.Rectangle(
                        (int)(bounds.Left + Math.Min(origin.X, point.X) * scale),
                        (int)(bounds.Top + Math.Min(origin.Y, point.Y) * scale), (int)width, (int)height);
                }
            }
            window.ReleaseMouseCapture();
            window.Close();
        };
        window.KeyDown += (_, e) => { if (e.Key == Key.Escape) window.Close(); };
        window.ShowDialog();
        return result;
    }
}
