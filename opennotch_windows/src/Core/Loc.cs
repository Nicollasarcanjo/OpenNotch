using System.Globalization;
using System.Windows.Markup;

namespace OpenNotch;

/// <summary>
/// Tradução. Como na versão macOS, a chave é a frase em português; sem tradução, a própria frase é usada.
/// As frases em inglês ficam em Strings.en.cs.
/// </summary>
public static class Loc
{
    public static bool English { get; private set; }

    public static void Init()
    {
        // OPENNOTCH_LANG força o idioma (usado ao gerar as imagens do README).
        var chosen = Environment.GetEnvironmentVariable("OPENNOTCH_LANG") ?? Settings.Current.Language;
        var code = string.IsNullOrEmpty(chosen) ? CultureInfo.CurrentUICulture.TwoLetterISOLanguageName : chosen;
        English = !code.StartsWith("pt", StringComparison.OrdinalIgnoreCase);
    }

    public static string T(string key) =>
        English && Strings.English.TryGetValue(key, out var value) ? value : key;

    public static string T(string key, params object[] args) => string.Format(T(key), args);
}

/// <summary>Uso no XAML: <c>Text="{l:T 'Nada tocando'}"</c>.</summary>
[MarkupExtensionReturnType(typeof(string))]
public sealed class TExtension : MarkupExtension
{
    public string Key { get; set; }

    public TExtension(string key) => Key = key;

    public override object ProvideValue(IServiceProvider serviceProvider) => Loc.T(Key);
}
