import Foundation

/// Texto traduzido para o idioma do app. A chave é a frase em português; se não houver
/// tradução, a própria frase é usada. Aceita os mesmos formatos de `String(format:)`.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
    return arguments.isEmpty ? format : String(format: format, locale: .current, arguments: arguments)
}
