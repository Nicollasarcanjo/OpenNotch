using System.IO;
using System.Text.Json;

namespace OpenNotch;

/// <summary>
/// Preferências do app, guardadas em %APPDATA%\OpenNotch\settings.json.
/// Os nomes seguem os da versão macOS (Prefs.swift) sempre que o recurso existe nas duas.
/// </summary>
public sealed class CustomAgent
{
    public string Name { get; set; } = "";
    public string Match { get; set; } = "";
}

public sealed class Settings : Observable
{
    public static Settings Current { get; } = Load();

    public static string Folder
    {
        get
        {
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "OpenNotch");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    private static string FilePath => Path.Combine(Folder, "settings.json");

    // Geral
    private bool _hoverOpens = true;
    public bool HoverOpens { get => _hoverOpens; set => Change(ref _hoverOpens, value); }
    // Um pouco mais que no macOS: no Windows o topo da tela é muito usado (abas, botões de janela),
    // e a espera evita abrir o notch sem querer.
    private double _hoverDelay = 0.2;
    public double HoverDelay { get => _hoverDelay; set => Change(ref _hoverDelay, value); }
    private double _closeDelay = 0.35;
    public double CloseDelay { get => _closeDelay; set => Change(ref _closeDelay, value); }
    private string _fullscreenMode = "passive";
    /// <summary>
    /// Com um app em tela cheia: "passive" mostra o notch só quando está em uso (letra, avisos),
    /// sem receber mouse nem clique; "hidden" esconde; "normal" funciona como fora da tela cheia.
    /// </summary>
    public string FullscreenMode { get => _fullscreenMode; set => Change(ref _fullscreenMode, value); }
    private bool _displayAllScreens = true;
    public bool DisplayAllScreens { get => _displayAllScreens; set => Change(ref _displayAllScreens, value); }
    private bool _showClosedIndicators;
    /// <summary>Só no Windows: fechado, o notch mostra música/timer/agentes em vez de ficar minimizado.</summary>
    public bool ShowClosedIndicators { get => _showClosedIndicators; set => Change(ref _showClosedIndicators, value); }
    private bool _hotkeysEnabled = true;
    public bool HotkeysEnabled { get => _hotkeysEnabled; set => Change(ref _hotkeysEnabled, value); }
    private string _language = "";
    public string Language { get => _language; set => Change(ref _language, value); }
    private bool _updateAutoCheck = true;
    public bool UpdateAutoCheck { get => _updateAutoCheck; set => Change(ref _updateAutoCheck, value); }
    private bool _startupConfigured;
    public bool StartupConfigured { get => _startupConfigured; set => Change(ref _startupConfigured, value); }
    private bool _onboardingDone;
    public bool OnboardingDone { get => _onboardingDone; set => Change(ref _onboardingDone, value); }

    // Tela inicial
    private List<string> _homeBlocks = ["music", "clock"];
    /// <summary>Blocos da tela inicial, da esquerda para a direita (ver HomeBlock).</summary>
    public List<string> HomeBlocks { get => _homeBlocks; set => Change(ref _homeBlocks, value); }
    private List<string> _homeApps = [];
    public List<string> HomeApps { get => _homeApps; set => Change(ref _homeApps, value); }
    private string _homeGif = "";
    public string HomeGif { get => _homeGif; set => Change(ref _homeGif, value); }
    private List<string> _homeSlides = [];
    public List<string> HomeSlides { get => _homeSlides; set => Change(ref _homeSlides, value); }
    private double _homeSlideInterval = 5;
    public double HomeSlideInterval { get => _homeSlideInterval; set => Change(ref _homeSlideInterval, value); }
    private double _homeMediaWidth = 190;
    public double HomeMediaWidth { get => _homeMediaWidth; set => Change(ref _homeMediaWidth, value); }

    // Módulos
    private bool _modMusic = true;
    public bool ModMusic { get => _modMusic; set => Change(ref _modMusic, value); }
    private bool _modAgents = true;
    public bool ModAgents { get => _modAgents; set => Change(ref _modAgents, value); }
    private bool _modApps = true;
    public bool ModApps { get => _modApps; set => Change(ref _modApps, value); }
    private bool _modMixer = true;
    public bool ModMixer { get => _modMixer; set => Change(ref _modMixer, value); }
    private bool _modCapture = true;
    public bool ModCapture { get => _modCapture; set => Change(ref _modCapture, value); }
    private bool _modNotes = true;
    public bool ModNotes { get => _modNotes; set => Change(ref _modNotes, value); }
    private bool _modClipboard = true;
    public bool ModClipboard { get => _modClipboard; set => Change(ref _modClipboard, value); }
    private bool _modTray = true;
    public bool ModTray { get => _modTray; set => Change(ref _modTray, value); }
    private bool _modDownloads = true;
    public bool ModDownloads { get => _modDownloads; set => Change(ref _modDownloads, value); }
    private bool _modTimers = true;
    public bool ModTimers { get => _modTimers; set => Change(ref _modTimers, value); }
    private bool _modSystem = true;
    public bool ModSystem { get => _modSystem; set => Change(ref _modSystem, value); }

    // Letra da música
    // Na versão da loja a letra vem desligada: ela exibe conteúdo de um serviço de terceiros,
    // e a decisão de usá-lo fica com o usuário.
    private bool _lyricsEnabled = !Packaged.IsPackaged;
    public bool LyricsEnabled { get => _lyricsEnabled; set => Change(ref _lyricsEnabled, value); }
    private string _lyricsFont = "system";
    public string LyricsFont { get => _lyricsFont; set => Change(ref _lyricsFont, value); }
    private double _lyricsSize = 12;
    public double LyricsSize { get => _lyricsSize; set => Change(ref _lyricsSize, value); }
    private bool _lyricsBold = true;
    public bool LyricsBold { get => _lyricsBold; set => Change(ref _lyricsBold, value); }
    private string _lyricsColor = "#FFFFFF";
    public string LyricsColor { get => _lyricsColor; set => Change(ref _lyricsColor, value); }
    private bool _lyricsOutline;
    public bool LyricsOutline { get => _lyricsOutline; set => Change(ref _lyricsOutline, value); }
    private string _lyricsOutlineColor = "#000000";
    public string LyricsOutlineColor { get => _lyricsOutlineColor; set => Change(ref _lyricsOutlineColor, value); }
    private double _lyricsOutlineWidth = 1;
    public double LyricsOutlineWidth { get => _lyricsOutlineWidth; set => Change(ref _lyricsOutlineWidth, value); }

    // Agentes de IA
    private bool _agentsClaude = true;
    public bool AgentsClaude { get => _agentsClaude; set => Change(ref _agentsClaude, value); }
    private bool _agentsCodex = true;
    public bool AgentsCodex { get => _agentsCodex; set => Change(ref _agentsCodex, value); }
    private bool _agentsAntigravity = true;
    public bool AgentsAntigravity { get => _agentsAntigravity; set => Change(ref _agentsAntigravity, value); }
    private List<CustomAgent> _customAgents = [];
    /// <summary>Ferramentas cadastradas pelo usuário, detectadas pelo nome do processo.</summary>
    public List<CustomAgent> CustomAgents { get => _customAgents; set => Change(ref _customAgents, value); }
    private bool _agentsNotify = true;
    public bool AgentsNotify { get => _agentsNotify; set => Change(ref _agentsNotify, value); }
    private double _agentsNotifySeconds = 6;
    public double AgentsNotifySeconds { get => _agentsNotifySeconds; set => Change(ref _agentsNotifySeconds, value); }
    private bool _agentsSound = true;
    public bool AgentsSound { get => _agentsSound; set => Change(ref _agentsSound, value); }
    private int _agentsClaudeWindow = 200_000;
    public int AgentsClaudeWindow { get => _agentsClaudeWindow; set => Change(ref _agentsClaudeWindow, value); }
    private int _agentsHideIdleHours = 12;
    public int AgentsHideIdleHours { get => _agentsHideIdleHours; set => Change(ref _agentsHideIdleHours, value); }

    // Textos e captura
    private int _clipLimit = 40;
    public int ClipLimit { get => _clipLimit; set => Change(ref _clipLimit, value); }
    private bool _clipPersist = true;
    public bool ClipPersist { get => _clipPersist; set => Change(ref _clipPersist, value); }
    private bool _captureAutoCopy = true;
    public bool CaptureAutoCopy { get => _captureAutoCopy; set => Change(ref _captureAutoCopy, value); }
    private bool _captureShowAfter = true;
    public bool CaptureShowAfter { get => _captureShowAfter; set => Change(ref _captureShowAfter, value); }
    private bool _captureShowNotch;
    public bool CaptureShowNotch { get => _captureShowNotch; set => Change(ref _captureShowNotch, value); }
    private int _captureGalleryCount = 12;
    public int CaptureGalleryCount { get => _captureGalleryCount; set => Change(ref _captureGalleryCount, value); }

    // Timers
    private int _focusMinutes = 25;
    public int FocusMinutes { get => _focusMinutes; set => Change(ref _focusMinutes, value); }
    private int _breakMinutes = 5;
    public int BreakMinutes { get => _breakMinutes; set => Change(ref _breakMinutes, value); }
    private int _countdownMinutes = 10;
    public int CountdownMinutes { get => _countdownMinutes; set => Change(ref _countdownMinutes, value); }
    private bool _timersSound = true;
    public bool TimersSound { get => _timersSound; set => Change(ref _timersSound, value); }

    // Enquanto o arquivo está sendo lido (ou importado), as propriedades mudam uma a uma;
    // gravar a cada mudança salvaria um estado pela metade.
    private static bool _loading;

    private void Change<T>(ref T field, T value, [System.Runtime.CompilerServices.CallerMemberName] string? name = null)
    {
        if (Set(ref field, value, name) && !_loading) Save();
    }

    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    private static Settings Load()
    {
        // No modo de demonstração valem sempre os padrões, e nada é gravado.
        if (Demo.Enabled) return new Settings();
        _loading = true;
        try
        {
            if (File.Exists(FilePath))
            {
                var loaded = JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath));
                if (loaded != null) return loaded;
            }
        }
        catch
        {
            // arquivo corrompido: segue com os padrões
        }
        finally
        {
            _loading = false;
        }
        return new Settings();
    }

    public void Save()
    {
        if (Demo.Enabled) return;
        try { File.WriteAllText(FilePath, JsonSerializer.Serialize(this, Json)); }
        catch { /* disco cheio ou pasta bloqueada: as preferências valem só nesta execução */ }
    }

    /// <summary>Adiciona um atalho de app e garante que o bloco de atalhos esteja na tela inicial.</summary>
    public void AddHomeApp(string path)
    {
        if (!HomeApps.Contains(path, StringComparer.OrdinalIgnoreCase)) HomeApps = [.. HomeApps, path];
        if (!HomeBlocks.Contains("apps")) HomeBlocks = [.. HomeBlocks, "apps"];
    }

    public string Export() => JsonSerializer.Serialize(this, Json);

    /// <summary>Aplica um arquivo exportado. Devolve false se não for um arquivo válido.</summary>
    public bool Import(string json)
    {
        Settings? other;
        _loading = true;
        try { other = JsonSerializer.Deserialize<Settings>(json); }
        catch { other = null; }
        finally { _loading = false; }
        if (other == null) return false;
        _loading = true;
        foreach (var property in typeof(Settings).GetProperties())
        {
            if (!property.CanWrite || property.Name is nameof(OnboardingDone) or nameof(StartupConfigured)) continue;
            property.SetValue(this, property.GetValue(other));
        }
        _loading = false;
        Save();
        return true;
    }
}
