import AppKit

/// Seleção de uma área da tela arrastando o mouse (usada para gravar só um trecho).
/// Devolve o retângulo nas coordenadas do `screencapture -R`: origem no canto superior
/// esquerdo da tela principal. Esc ou um clique sem arrastar cancelam.
final class RegionSelector {
    private var window: SelectorWindow?

    func select(completion: @escaping (CGRect?) -> Void) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            completion(nil)
            return
        }
        let window = SelectorWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.sharingType = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onFinish = { [weak self] rect in
            self?.window?.orderOut(nil)
            self?.window = nil
            guard let rect else {
                completion(nil)
                return
            }
            let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
            // Dimensões pares evitam problemas no codificador de vídeo.
            completion(CGRect(x: global.minX.rounded(), y: (primaryHeight - global.maxY).rounded(),
                              width: (global.width / 2).rounded() * 2, height: (global.height / 2).rounded() * 2))
        }
        window.contentView = view
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }
}

private final class SelectorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var selection: CGRect?
    private let minimumSide: CGFloat = 24

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        if let selection {
            NSColor.clear.setFill()
            selection.fill(using: .copy)
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1
            border.stroke()
            label("\(Int(selection.width)) × \(Int(selection.height))", near: selection)
        } else {
            label(L("Arraste para escolher a área da gravação · Esc cancela"),
                  near: CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0), centered: true)
        }
    }

    private func label(_ text: String, near rect: CGRect, centered: Bool = false) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: centered ? 15 : 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = centered
            ? CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
            : CGPoint(x: rect.minX, y: max(rect.minY - size.height - 6, 4))
        let background = CGRect(origin: origin, size: size).insetBy(dx: -6, dy: -3)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                           width: abs(point.x - start.x), height: abs(point.y - start.y)).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let selection, selection.width >= minimumSide, selection.height >= minimumSide {
            onFinish?(selection)
        } else {
            onFinish?(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) } else { super.keyDown(with: event) }   // 53 = Esc
    }
}
