using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;

namespace OpenNotch;

/// <summary>
/// Editor de marcações de um print: seta, retângulo, texto e borrar. Salva uma cópia
/// ("… anotado.png") ao lado do original. Equivale a Annotate.swift na versão macOS.
/// </summary>
public partial class AnnotateWindow : Window
{
    private enum Tool { Arrow, Rect, Text, Blur }

    private readonly string _path;
    private readonly BitmapSource _image;
    private readonly BitmapSource _pixelated;
    private readonly double _stroke;
    private Tool _tool = Tool.Arrow;
    private Color _color = Color.FromRgb(0xFF, 0x45, 0x3A);
    private Point? _start;
    private UIElement? _draft;

    /// <summary>Chamado com o caminho do arquivo salvo.</summary>
    public event Action<string>? Saved;

    public AnnotateWindow(string path)
    {
        InitializeComponent();
        _path = path;
        Title = Loc.T("Anotar: {0}", System.IO.Path.GetFileName(path));
        _image = Load(path);
        // Versão "em blocos" da imagem inteira; borrar é mostrar um pedaço dela.
        var small = new TransformedBitmap(_image, new ScaleTransform(1.0 / 14, 1.0 / 14));
        _pixelated = small;
        _stroke = Math.Max(_image.PixelWidth / 320.0, 3);

        Picture.Source = _image;
        Picture.Width = Marks.Width = Stage.Width = _image.PixelWidth;
        Picture.Height = Marks.Height = Stage.Height = _image.PixelHeight;

        BuildTools();
        BuildPalette();
        SourceInitialized += (_, _) => Native.UseDarkTitleBar(new WindowInteropHelper(this).Handle);
    }

    private static BitmapSource Load(string path)
    {
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;   // não deixa o arquivo travado
        image.UriSource = new Uri(path);
        image.EndInit();
        // Trata a imagem em pixels reais, qualquer que seja o DPI gravado no arquivo.
        var converted = new FormatConvertedBitmap(image, PixelFormats.Pbgra32, null, 0);
        var stride = converted.PixelWidth * 4;
        var pixels = new byte[stride * converted.PixelHeight];
        converted.CopyPixels(pixels, stride, 0);
        var normalized = BitmapSource.Create(converted.PixelWidth, converted.PixelHeight, 96, 96, PixelFormats.Pbgra32,
            null, pixels, stride);
        normalized.Freeze();
        return normalized;
    }

    private void BuildTools()
    {
        (Tool tool, string title)[] tools =
        [
            (Tool.Arrow, Loc.T("Seta")), (Tool.Rect, Loc.T("Retângulo")), (Tool.Text, Loc.T("Texto")), (Tool.Blur, Loc.T("Borrar")),
        ];
        foreach (var (tool, title) in tools)
        {
            var option = new RadioButton
            {
                Style = (Style)FindResource("Segment"), Content = title, GroupName = "tool", IsChecked = tool == _tool,
            };
            option.Checked += (_, _) =>
            {
                _tool = tool;
                TextInput.Visibility = tool == Tool.Text ? Visibility.Visible : Visibility.Collapsed;
                Palette.Visibility = tool == Tool.Blur ? Visibility.Collapsed : Visibility.Visible;
                if (tool == Tool.Text) TextInput.Focus();
            };
            Tools.Children.Add(option);
        }
    }

    private void BuildPalette()
    {
        Color[] colors =
        [
            Color.FromRgb(0xFF, 0x45, 0x3A), Color.FromRgb(0xFF, 0x9F, 0x0A), Color.FromRgb(0xFF, 0xD6, 0x0A),
            Color.FromRgb(0x30, 0xD1, 0x58), Color.FromRgb(0x0A, 0x84, 0xFF), Colors.White, Colors.Black,
        ];
        foreach (var color in colors)
        {
            var swatch = new Ellipse
            {
                Width = 18, Height = 18, Margin = new Thickness(0, 0, 6, 0), Cursor = Cursors.Hand,
                Fill = new SolidColorBrush(color), Stroke = Brushes.White, StrokeThickness = color == _color ? 2 : 0.5,
            };
            swatch.MouseLeftButtonDown += (_, _) =>
            {
                _color = color;
                foreach (Ellipse other in Palette.Children) other.StrokeThickness = other == swatch ? 2 : 0.5;
            };
            Palette.Children.Add(swatch);
        }
    }

    // MARK: Desenho

    private void OnDown(object sender, MouseButtonEventArgs e)
    {
        var point = e.GetPosition(Marks);
        if (_tool == Tool.Text)
        {
            var text = TextInput.Text.Trim();
            if (text.Length == 0) return;
            var label = new TextBlock
            {
                Text = text, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(_color),
                FontSize = Math.Max(_image.PixelWidth / 45.0, 14),
            };
            Canvas.SetLeft(label, point.X);
            Canvas.SetTop(label, point.Y);
            Marks.Children.Add(label);
            return;
        }
        _start = point;
        Marks.CaptureMouse();
    }

    private void OnMove(object sender, MouseEventArgs e)
    {
        if (_start is not { } start) return;
        if (_draft != null) Marks.Children.Remove(_draft);
        _draft = Make(start, e.GetPosition(Marks));
        if (_draft != null) Marks.Children.Add(_draft);
    }

    private void OnUp(object sender, MouseButtonEventArgs e)
    {
        if (_start is not { } start) return;
        Marks.ReleaseMouseCapture();
        var end = e.GetPosition(Marks);
        // Um clique sem arrastar não vira marcação.
        if (_draft != null && Math.Abs(end.X - start.X) < 5 && Math.Abs(end.Y - start.Y) < 5) Marks.Children.Remove(_draft);
        _start = null;
        _draft = null;
    }

    private UIElement? Make(Point start, Point end)
    {
        var rect = new Rect(start, end);
        var brush = new SolidColorBrush(_color);
        switch (_tool)
        {
            case Tool.Rect:
                var box = new Rectangle { Width = rect.Width, Height = rect.Height, Stroke = brush, StrokeThickness = _stroke, RadiusX = _stroke, RadiusY = _stroke };
                Canvas.SetLeft(box, rect.X);
                Canvas.SetTop(box, rect.Y);
                return box;
            case Tool.Blur:
                // Um pedaço da imagem em blocos, mapeado para a mesma posição da imagem original.
                var blur = new Rectangle
                {
                    Width = rect.Width, Height = rect.Height,
                    Fill = new ImageBrush(_pixelated)
                    {
                        Stretch = Stretch.Fill, ViewboxUnits = BrushMappingMode.RelativeToBoundingBox,
                        Viewbox = new Rect(rect.X / _image.PixelWidth, rect.Y / _image.PixelHeight,
                                           rect.Width / _image.PixelWidth, rect.Height / _image.PixelHeight),
                    },
                };
                RenderOptions.SetBitmapScalingMode(blur, BitmapScalingMode.NearestNeighbor);
                Canvas.SetLeft(blur, rect.X);
                Canvas.SetTop(blur, rect.Y);
                return blur;
            case Tool.Arrow:
                var angle = Math.Atan2(end.Y - start.Y, end.X - start.X);
                var head = _stroke * 4.5;
                var figure = new GeometryGroup();
                figure.Children.Add(new LineGeometry(start,
                    new Point(end.X - Math.Cos(angle) * head * 0.7, end.Y - Math.Sin(angle) * head * 0.7)));
                var arrow = new System.Windows.Shapes.Path
                {
                    Data = figure, Stroke = brush, StrokeThickness = _stroke,
                    StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
                };
                var tip = new Polygon
                {
                    Fill = brush,
                    Points =
                    [
                        end,
                        new Point(end.X - Math.Cos(angle - 0.45) * head, end.Y - Math.Sin(angle - 0.45) * head),
                        new Point(end.X - Math.Cos(angle + 0.45) * head, end.Y - Math.Sin(angle + 0.45) * head),
                    ],
                };
                var group = new Canvas();
                group.Children.Add(arrow);
                group.Children.Add(tip);
                return group;
            default:
                return null;
        }
    }

    private void OnUndo(object sender, RoutedEventArgs e)
    {
        if (Marks.Children.Count > 0) Marks.Children.RemoveAt(Marks.Children.Count - 1);
    }

    private void OnCancel(object sender, RoutedEventArgs e) => Close();

    private void OnSave(object sender, RoutedEventArgs e)
    {
        try
        {
            // Renderiza a imagem com as marcações no tamanho real, não no tamanho da janela.
            var size = new Size(_image.PixelWidth, _image.PixelHeight);
            Stage.Measure(size);
            Stage.Arrange(new Rect(size));
            var render = new RenderTargetBitmap(_image.PixelWidth, _image.PixelHeight, 96, 96, PixelFormats.Pbgra32);
            render.Render(Stage);

            var folder = System.IO.Path.GetDirectoryName(_path) ?? Paths.Captures;
            var name = System.IO.Path.GetFileNameWithoutExtension(_path) + Loc.T(" anotado");
            var target = System.IO.Path.Combine(folder, name + ".png");
            for (var i = 2; System.IO.File.Exists(target); i++) target = System.IO.Path.Combine(folder, $"{name} {i}.png");
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(render));
            using (var stream = System.IO.File.Create(target)) encoder.Save(stream);
            Saved?.Invoke(target);
        }
        catch
        {
            // pasta sem permissão de escrita: a janela fecha sem salvar
        }
        Close();
    }
}
