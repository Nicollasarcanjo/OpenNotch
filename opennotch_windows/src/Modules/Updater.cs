using System.Diagnostics;
using System.Net.Http;
using System.Reflection;
using System.Text.Json;

namespace OpenNotch;

/// <summary>
/// Confere no GitHub se há versão mais nova. Só avisa e abre a página de download;
/// não baixa nem instala nada sozinho. Igual à versão macOS (Updater.swift).
/// </summary>
public sealed class Updater : Observable
{
    public const string Repository = "Nicollasarcanjo/OpenNotch";

    private string _status = Loc.T("Ainda não verificado");
    private string? _page;
    private bool _checking;

    public string Status { get => _status; private set => Set(ref _status, value); }
    public bool Available => _page != null;

    public static string Current =>
        Assembly.GetExecutingAssembly().GetName().Version is { } v ? $"{v.Major}.{v.Minor}.{v.Build}" : "0.0.0";

    public async Task Check()
    {
        if (_checking) return;
        _checking = true;
        Status = Loc.T("Verificando…");
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd("OpenNotch");
            http.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
            var response = await http.GetAsync($"https://api.github.com/repos/{Repository}/releases/latest");
            if (!response.IsSuccessStatusCode)
            {
                Status = Loc.T("Não foi possível verificar");
                return;
            }
            var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;
            var tag = json.Str("tag_name").TrimStart('v');
            if (Version.TryParse(tag, out var latest) && Version.TryParse(Current, out var mine) && latest > mine)
            {
                _page = json.Str("html_url");
                Status = Loc.T("Versão {0} disponível", tag);
            }
            else
            {
                _page = null;
                Status = Loc.T("Você está na versão mais recente");
            }
            Raise(nameof(Available));
        }
        catch
        {
            Status = Loc.T("Não foi possível verificar");
        }
        finally
        {
            _checking = false;
        }
    }

    public void OpenDownloadPage()
    {
        if (_page == null) return;
        try { Process.Start(new ProcessStartInfo(_page) { UseShellExecute = true }); }
        catch { }
    }
}
