using System.IO;

namespace OpenNotch;

internal static class Paths
{
    public static string Home => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    public static string Downloads => Path.Combine(Home, "Downloads");

    public static string Captures
    {
        get
        {
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "OpenNotch");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    /// <summary>Pasta onde o Windows salva os prints de Win + PrtScn.</summary>
    public static string SystemScreenshots =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Screenshots");

    public static string FormatBytes(double bytes)
    {
        string[] units = ["B", "KB", "MB", "GB", "TB"];
        var unit = 0;
        while (bytes >= 1024 && unit < units.Length - 1)
        {
            bytes /= 1024;
            unit++;
        }
        return unit == 0 ? $"{bytes:0} {units[unit]}" : $"{bytes:0.#} {units[unit]}";
    }
}
