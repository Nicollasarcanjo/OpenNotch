import Foundation
import Network

/// O que a extensão do navegador informa sobre a aba que está tocando.
struct BrowserState: Decodable {
    var site = ""
    var title = ""
    var artist = ""
    var album = ""
    var artwork = ""
    var playing = false
}

/// Servidor HTTP mínimo, só em 127.0.0.1, que recebe da extensão do navegador a música
/// tocando e devolve o comando pendente (tocar/pausar, próxima, anterior).
final class BrowserBridge {
    static let port: UInt16 = 38917

    /// Última vez que a extensão falou com o app (para a tela de configurações mostrar se está conectada).
    static private(set) var lastContact: Date?

    var onState: ((BrowserState) -> Void)?
    /// Comando esperando a próxima chamada da extensão.
    var pendingCommand: String?

    private var listener: NWListener?
    private static let allowedOrigins = ["chrome-extension://", "moz-extension://", "safari-web-extension://"]
    private static let maxRequest = 64 * 1024

    func start() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            self?.receive(on: connection, buffer: Data())
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Request(buffer) {
                self.respond(to: request, on: connection)
            } else if done || error != nil || buffer.count > Self.maxRequest {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: Request, on connection: NWConnection) {
        // Só extensões de navegador podem falar com o app; páginas comuns são recusadas.
        guard let origin = request.headers["origin"],
              Self.allowedOrigins.contains(where: origin.hasPrefix) else {
            send(status: "403 Forbidden", body: "{}", origin: nil, on: connection)
            return
        }
        switch (request.method, request.path) {
        case ("OPTIONS", _):
            send(status: "204 No Content", body: "", origin: origin, on: connection)
        case ("POST", "/state"):
            Self.lastContact = Date()
            if let state = try? JSONDecoder().decode(BrowserState.self, from: request.body) {
                onState?(state)
            }
            let command = pendingCommand.map { "\"\($0)\"" } ?? "null"
            pendingCommand = nil
            send(status: "200 OK", body: "{\"command\":\(command)}", origin: origin, on: connection)
        default:
            send(status: "404 Not Found", body: "{}", origin: origin, on: connection)
        }
    }

    private func send(status: String, body: String, origin: String?, on connection: NWConnection) {
        var head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n"
        if let origin {
            head += "Access-Control-Allow-Origin: \(origin)\r\nAccess-Control-Allow-Headers: Content-Type\r\n"
                + "Access-Control-Allow-Methods: POST, OPTIONS\r\n"
        }
        head += "Connection: close\r\n\r\n"
        connection.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Requisição HTTP já completa (cabeçalhos + corpo), ou nil se ainda falta chegar algo.
    private struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data

        init?(_ data: Data) {
            guard let split = data.range(of: Data("\r\n\r\n".utf8)),
                  let head = String(data: data[data.startIndex..<split.lowerBound], encoding: .utf8) else { return nil }
            var lines = head.components(separatedBy: "\r\n")
            let start = lines.removeFirst().split(separator: " ")
            guard start.count >= 2 else { return nil }
            var headers: [String: String] = [:]
            for line in lines {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            let length = Int(headers["content-length"] ?? "0") ?? 0
            let body = data[split.upperBound...]
            guard body.count >= length else { return nil }
            method = String(start[0])
            path = String(start[1])
            self.headers = headers
            self.body = Data(body.prefix(length))
        }
    }
}
