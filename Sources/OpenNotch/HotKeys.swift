import AppKit
import Carbon.HIToolbox

/// Atalho de teclado global do OpenNotch (fixo por enquanto).
enum Shortcut: UInt32, CaseIterable, Identifiable {
    case toggleNotch = 1, texts, capture, recordRegion

    var id: UInt32 { rawValue }

    var keyCode: Int {
        switch self {
        case .toggleNotch: return kVK_ANSI_N
        case .texts: return kVK_ANSI_V
        case .capture: return kVK_ANSI_S
        case .recordRegion: return kVK_ANSI_R
        }
    }

    var keys: String {
        switch self {
        case .toggleNotch: return "⌃⌥N"
        case .texts: return "⌃⌥V"
        case .capture: return "⌃⌥S"
        case .recordRegion: return "⌃⌥R"
        }
    }

    var title: String {
        switch self {
        case .toggleNotch: return L("Abrir ou fechar o notch")
        case .texts: return L("Abrir Textos (anotações e copiados)")
        case .capture: return L("Abrir Captura de tela")
        case .recordRegion: return L("Gravar uma área / parar a gravação")
        }
    }
}

/// Registra atalhos globais pelo Carbon, que não exige permissão de Acessibilidade.
final class HotKeys {
    var onShortcut: ((Shortcut) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x4F4E_4348   // "ONCH"

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if let userData, let shortcut = Shortcut(rawValue: id.id) {
                Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue().onShortcut?(shortcut)
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled, refs.isEmpty {
            for shortcut in Shortcut.allCases {
                var ref: EventHotKeyRef?
                let id = EventHotKeyID(signature: Self.signature, id: shortcut.rawValue)
                RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(controlKey | optionKey), id,
                                    GetApplicationEventTarget(), 0, &ref)
                if let ref { refs.append(ref) }
            }
        } else if !enabled {
            refs.forEach { UnregisterEventHotKey($0) }
            refs = []
        }
    }
}
