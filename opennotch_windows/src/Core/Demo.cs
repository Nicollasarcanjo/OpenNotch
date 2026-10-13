using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace OpenNotch;

/// <summary>
/// Modo de demonstração (OPENNOTCH_DEMO=1): troca os dados reais por exemplos fictícios, como na
/// versão macOS (Demo.swift). Serve para gerar imagens da interface sem expor dados de ninguém.
/// </summary>
public static class Demo
{
    public static bool Enabled { get; } = Environment.GetEnvironmentVariable("OPENNOTCH_DEMO") != null;

    public static ImageSource Artwork()
    {
        var visual = new DrawingVisual();
        using (var context = visual.RenderOpen())
        {
            var gradient = new LinearGradientBrush(Color.FromRgb(0xFF, 0x37, 0x5F), Color.FromRgb(0x5E, 0x5C, 0xE6), 45);
            context.DrawRectangle(gradient, null, new Rect(0, 0, 300, 300));
        }
        var bitmap = new RenderTargetBitmap(300, 300, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        bitmap.Freeze();
        return bitmap;
    }

    public static List<AgentProvider> Providers() =>
    [
        new AgentProvider
        {
            Id = "claude", Name = "Claude Code",
            Sessions =
            [
                new AgentSession { Id = "1", Title = "Refatorar o checkout", Project = "loja-online", Working = true, Usage = 0.42 },
                new AgentSession { Id = "2", Title = "Corrigir testes da API", Project = "backend", Working = false, Usage = 0.71 },
            ],
        },
        new AgentProvider
        {
            Id = "codex", Name = "Codex",
            Limits = [new AgentLimit("5 h", 38), new AgentLimit(Loc.T("semana"), 12)],
            Sessions = [new AgentSession { Id = "3", Title = "Tela de cadastro", Project = "app-mobile", Working = true, Usage = 0.27 }],
        },
    ];

    public static List<AppRow> Apps()
    {
        AppRow Row(string name, double cpu, double gpu, double gigabytes, int count) => new()
        {
            Id = name, Name = name, MainPids = [1000], Cpu = cpu, Gpu = gpu, Memory = (long)(gigabytes * 1_073_741_824),
            Processes = Enumerable.Range(0, count).Select(i => new ProcessRow
            {
                Pid = 1000 + i, Name = name, Cpu = cpu / count, Memory = (long)(gigabytes * 1_073_741_824 / count),
            }).ToList(),
        };
        return [Row("Navegador", 12.4, 3.1, 2.3, 14), Row("Editor de código", 8.7, 1.2, 4.1, 9), Row("Música", 2.1, 0, 0.6, 3),
                Row("E-mail", 0.8, 0, 0.9, 5), Row("Notas", 0.3, 0, 0.4, 2)];
    }

    public static List<Note> Notes() =>
    [
        new Note { Text = "Ideias para o projeto\n- revisar o layout" }, new Note { Text = "Lista de compras" },
        new Note { Text = "Reunião de quinta: levar o protótipo" },
    ];

    public static List<ClipItem> Copied() =>
    [
        new ClipItem { Text = "git commit -m \"ajusta o layout\"" }, new ClipItem { Text = "https://exemplo.com/documentacao" },
        new ClipItem { Text = "Rua das Flores, 123" },
    ];
}

/// <summary>
/// Autoteste visual (OPENNOTCH_SNAPSHOT_DIR=pasta): abre cada aba do notch e cada painel das
/// configurações, salva um PNG de cada um e fecha o app. É assim que a versão Windows é conferida
/// por quem desenvolve num Mac: o CI roda isto num Windows de verdade e devolve as imagens.
/// </summary>
internal static class SelfTest
{
    public static string? Folder { get; } = Environment.GetEnvironmentVariable("OPENNOTCH_SNAPSHOT_DIR");

    public static void Log(string message)
    {
        try
        {
            var target = Folder != null ? Path.Combine(Folder, "errors.txt") : Path.Combine(Settings.Folder, "errors.log");
            if (Folder != null) Directory.CreateDirectory(Folder);
            File.AppendAllText(target, $"[{DateTime.Now:HH:mm:ss}] {message}\n\n");
        }
        catch
        {
            // sem onde escrever: o erro só deixa de ser registrado
        }
    }

    public static async Task Run(NotchWindow notch)
    {
        if (Folder == null) return;
        Directory.CreateDirectory(Folder);
        var gray = new SolidColorBrush(Color.FromRgb(0x6E, 0x7B, 0x8B));
        await Task.Delay(2500);
        Step("notch-fechado", () => Save(notch, gray, "notch-fechado"));
        foreach (var tab in Enum.GetValues<NotchTab>())
        {
            Step("abrir " + tab, () => notch.Open(tab));
            await Task.Delay(1000);
            Step("notch-" + tab, () => Save(notch, gray, "notch-" + tab.ToString().ToLowerInvariant()));
        }
        Step("fechar", () => notch.Close(animated: false));

        SettingsWindow? settings = null;
        Step("configurações", () => { settings = new SettingsWindow(); settings.Show(); });
        if (settings != null)
        {
            foreach (var pane in settings.PaneIds)
            {
                Step("painel " + pane, () => settings.Select(pane));
                await Task.Delay(500);
                Step("config-" + pane, () => Save(settings, settings.Background, "config-" + pane));
            }
            Step("fechar configurações", settings.Close);
        }

        OnboardingWindow? welcome = null;
        Step("boas-vindas", () => { welcome = new OnboardingWindow(); welcome.Show(); });
        await Task.Delay(700);
        if (welcome != null)
        {
            Step("boas-vindas png", () => Save(welcome, welcome.Background, "boas-vindas"));
            Step("fechar boas-vindas", welcome.Close);
        }
        File.WriteAllText(Path.Combine(Folder, "done.txt"), DateTime.Now.ToString("s"));
        Application.Current.Shutdown();
    }

    private static void Step(string name, Action action)
    {
        try { action(); }
        catch (Exception error) { Log($"{name}: {error}"); }
    }

    /// <summary>Desenha o conteúdo da janela sobre um fundo liso e grava como PNG.</summary>
    private static void Save(Window window, Brush? background, string name)
    {
        if (window.Content is not FrameworkElement content || content.ActualWidth < 1 || content.ActualHeight < 1)
        {
            Log(name + ": conteúdo sem tamanho");
            return;
        }
        var dpi = VisualTreeHelper.GetDpi(content);
        var size = new Size(content.ActualWidth, content.ActualHeight);
        var visual = new DrawingVisual();
        using (var context = visual.RenderOpen())
        {
            context.DrawRectangle(background ?? Brushes.Gray, null, new Rect(size));
            context.DrawRectangle(new VisualBrush(content) { Stretch = Stretch.None }, null, new Rect(size));
        }
        var bitmap = new RenderTargetBitmap((int)(size.Width * dpi.DpiScaleX), (int)(size.Height * dpi.DpiScaleY),
            dpi.PixelsPerInchX, dpi.PixelsPerInchY, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(Path.Combine(Folder!, name + ".png"));
        encoder.Save(stream);
    }
}
