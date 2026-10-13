using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace OpenNotch;

/// <summary>
/// Servidor HTTP mínimo, só em 127.0.0.1, que conversa com a extensão do navegador.
/// Mesmo protocolo da versão macOS (BrowserBridge.swift). No Windows a música já vem dos
/// controles de mídia do sistema, então aqui a extensão serve só para o volume por aba.
/// </summary>
public sealed class BrowserBridge
{
    public const int Port = 38917;
    private static readonly string[] AllowedOrigins = ["chrome-extension://", "moz-extension://"];

    public sealed record Tab(int Id, string Title, string Site);

    private readonly object _lock = new();
    private readonly Dictionary<int, (Tab tab, DateTime at)> _seen = [];
    private readonly Dictionary<int, double> _volumes = [];
    private TcpListener? _listener;

    public DateTime? LastContact { get; private set; }

    public void Start()
    {
        if (_listener != null) return;
        try
        {
            _listener = new TcpListener(IPAddress.Loopback, Port);
            _listener.Start();
            _ = AcceptLoop(_listener);
        }
        catch
        {
            _listener = null;   // porta ocupada: o volume por aba fica indisponível
        }
    }

    /// <summary>Abas que falaram com o app nos últimos segundos (ou seja, que estão tocando algo).</summary>
    public List<Tab> ActiveTabs()
    {
        lock (_lock)
        {
            foreach (var id in _seen.Where(e => (DateTime.UtcNow - e.Value.at).TotalSeconds > 6).Select(e => e.Key).ToList())
            {
                _seen.Remove(id);
            }
            return _seen.OrderBy(e => e.Key).Select(e => e.Value.tab).ToList();
        }
    }

    public double VolumeOf(int tab)
    {
        lock (_lock) return _volumes.GetValueOrDefault(tab, 1);
    }

    /// <summary>O volume é aplicado na página quando a aba falar com o app de novo (até 1 s).</summary>
    public void SetVolume(int tab, double value)
    {
        lock (_lock) _volumes[tab] = Math.Clamp(value, 0, 1);
    }

    private async Task AcceptLoop(TcpListener listener)
    {
        while (true)
        {
            TcpClient client;
            try { client = await listener.AcceptTcpClientAsync(); }
            catch { return; }
            _ = Task.Run(() => Handle(client));
        }
    }

    private async Task Handle(TcpClient client)
    {
        using (client)
        {
            try
            {
                client.ReceiveTimeout = 5000;
                var stream = client.GetStream();
                var buffer = new byte[64 * 1024];
                var length = 0;
                var headerEnd = -1;
                var contentLength = 0;
                // Lê até ter os cabeçalhos e o corpo inteiros.
                while (length < buffer.Length)
                {
                    var read = await stream.ReadAsync(buffer.AsMemory(length, buffer.Length - length));
                    if (read == 0) break;
                    length += read;
                    if (headerEnd < 0)
                    {
                        headerEnd = Encoding.ASCII.GetString(buffer, 0, length).IndexOf("\r\n\r\n", StringComparison.Ordinal);
                        if (headerEnd >= 0)
                        {
                            var head = Encoding.ASCII.GetString(buffer, 0, headerEnd);
                            var line = head.Split("\r\n").FirstOrDefault(l => l.StartsWith("content-length:", StringComparison.OrdinalIgnoreCase));
                            if (line != null) int.TryParse(line[(line.IndexOf(':') + 1)..].Trim(), out contentLength);
                        }
                    }
                    if (headerEnd >= 0 && length >= headerEnd + 4 + contentLength) break;
                }
                if (headerEnd < 0) return;

                var headers = Encoding.ASCII.GetString(buffer, 0, headerEnd).Split("\r\n");
                var request = headers[0].Split(' ');
                var origin = headers.FirstOrDefault(l => l.StartsWith("origin:", StringComparison.OrdinalIgnoreCase));
                origin = origin?[(origin.IndexOf(':') + 1)..].Trim();
                // Só extensões de navegador podem falar com o app; páginas comuns são recusadas.
                if (origin == null || !AllowedOrigins.Any(origin.StartsWith) || request.Length < 2)
                {
                    await Reply(stream, "403 Forbidden", "{}", null);
                    return;
                }
                if (request[0] == "OPTIONS")
                {
                    await Reply(stream, "204 No Content", "", origin);
                    return;
                }
                if (request[0] != "POST" || request[1] != "/state")
                {
                    await Reply(stream, "404 Not Found", "{}", origin);
                    return;
                }
                var body = Encoding.UTF8.GetString(buffer, headerEnd + 4, Math.Min(contentLength, length - headerEnd - 4));
                var volume = "null";
                try
                {
                    var state = JsonDocument.Parse(body).RootElement;
                    if (state.Num("tab") is { } id)
                    {
                        lock (_lock)
                        {
                            _seen[(int)id] = (new Tab((int)id, state.Str("title"), state.Str("site")), DateTime.UtcNow);
                            if (_volumes.TryGetValue((int)id, out var chosen))
                            {
                                volume = chosen.ToString("0.000", System.Globalization.CultureInfo.InvariantCulture);
                            }
                        }
                    }
                }
                catch
                {
                    // corpo inválido: responde sem volume
                }
                LastContact = DateTime.UtcNow;
                await Reply(stream, "200 OK", $"{{\"command\":null,\"volume\":{volume}}}", origin);
            }
            catch
            {
                // conexão interrompida
            }
        }
    }

    private static async Task Reply(NetworkStream stream, string status, string body, string? origin)
    {
        var head = $"HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {Encoding.UTF8.GetByteCount(body)}\r\n";
        if (origin != null)
        {
            head += $"Access-Control-Allow-Origin: {origin}\r\nAccess-Control-Allow-Headers: Content-Type\r\n"
                + "Access-Control-Allow-Methods: POST, OPTIONS\r\n";
        }
        head += "Connection: close\r\n\r\n";
        await stream.WriteAsync(Encoding.UTF8.GetBytes(head + body));
    }
}

/// <summary>A extensão do navegador vem embutida no app; aqui ela é entregue como um .zip.</summary>
public static class BrowserExtension
{
    private static readonly string[] Files = ["manifest.json", "background.js", "content.js"];

    public static bool SaveZip(string path)
    {
        try
        {
            if (System.IO.File.Exists(path)) System.IO.File.Delete(path);
            using var zip = System.IO.Compression.ZipFile.Open(path, System.IO.Compression.ZipArchiveMode.Create);
            var assembly = typeof(BrowserExtension).Assembly;
            foreach (var file in Files)
            {
                using var source = assembly.GetManifestResourceStream("Extension." + file);
                if (source == null) return false;
                // Dentro de uma pasta, para o usuário descompactar e já ter o que o navegador pede.
                using var target = zip.CreateEntry("OpenNotch-Extensao/" + file).Open();
                source.CopyTo(target);
            }
            return true;
        }
        catch
        {
            return false;
        }
    }
}
