import AppKit
import CoreImage
import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
    case arrow, rect, text, blur

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rect: return "rectangle"
        case .text: return "textformat"
        case .blur: return "square.grid.3x3.fill"
        }
    }

    var title: String {
        switch self {
        case .arrow: return L("Seta")
        case .rect: return L("Retângulo")
        case .text: return L("Texto")
        case .blur: return L("Borrar")
        }
    }
}

/// Uma marcação sobre o print. As coordenadas são em pixels da imagem, origem no canto superior esquerdo.
struct Annotation: Identifiable {
    let id = UUID()
    var tool: AnnotationTool
    var start: CGPoint
    var end: CGPoint
    var color: Color
    var text = ""

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

/// Desenha o print com as marcações. É usada tanto na tela (reduzida) quanto para exportar (tamanho real).
struct AnnotationCanvas: View {
    let image: NSImage
    let pixelated: NSImage
    let pixelSize: CGSize
    let items: [Annotation]

    var body: some View {
        Canvas { context, size in
            let scale = size.width / max(pixelSize.width, 1)
            let full = CGRect(origin: .zero, size: size)
            context.draw(Image(nsImage: image), in: full)
            // Espessura proporcional à imagem, para a marcação ficar igual em prints pequenos e grandes.
            let stroke = max(pixelSize.width / 320, 3) * scale

            for item in items {
                let start = CGPoint(x: item.start.x * scale, y: item.start.y * scale)
                let end = CGPoint(x: item.end.x * scale, y: item.end.y * scale)
                let rect = item.rect.applying(CGAffineTransform(scaleX: scale, y: scale))
                switch item.tool {
                case .blur:
                    context.drawLayer { layer in
                        layer.clip(to: Path(rect))
                        layer.draw(Image(nsImage: pixelated), in: full)
                    }
                case .rect:
                    context.stroke(Path(roundedRect: rect, cornerRadius: stroke), with: .color(item.color),
                                   style: StrokeStyle(lineWidth: stroke, lineJoin: .round))
                case .arrow:
                    let angle = atan2(end.y - start.y, end.x - start.x)
                    let head = stroke * 4.5
                    var line = Path()
                    line.move(to: start)
                    line.addLine(to: CGPoint(x: end.x - cos(angle) * head * 0.7, y: end.y - sin(angle) * head * 0.7))
                    context.stroke(line, with: .color(item.color), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    var tip = Path()
                    tip.move(to: end)
                    tip.addLine(to: CGPoint(x: end.x - cos(angle - 0.45) * head, y: end.y - sin(angle - 0.45) * head))
                    tip.addLine(to: CGPoint(x: end.x - cos(angle + 0.45) * head, y: end.y - sin(angle + 0.45) * head))
                    tip.closeSubpath()
                    context.fill(tip, with: .color(item.color))
                case .text:
                    let font = Font.system(size: max(pixelSize.width / 45, 14) * scale, weight: .bold)
                    context.draw(Text(item.text).font(font).foregroundColor(item.color), at: start, anchor: .topLeading)
                }
            }
        }
    }
}

struct AnnotateView: View {
    let url: URL
    let image: NSImage
    let pixelated: NSImage
    let pixelSize: CGSize
    let finish: (NSImage?) -> Void

    @State private var items: [Annotation] = []
    @State private var tool: AnnotationTool = .arrow
    @State private var color: Color = .red
    @State private var text = ""
    @State private var draft: Annotation?

    private let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .white, .black]

    var body: some View {
        VStack(spacing: 0) {
            toolbar.padding(10)
            Divider()
            GeometryReader { geo in
                let scale = min(geo.size.width / pixelSize.width, geo.size.height / pixelSize.height, 1)
                let size = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
                AnnotationCanvas(image: image, pixelated: pixelated, pixelSize: pixelSize,
                                 items: items + (draft.map { [$0] } ?? []))
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .gesture(drag(scale: scale))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(14)
            .background(Color(nsColor: .underPageBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $tool) {
                ForEach(AnnotationTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.icon).tag(tool)
                }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()

            if tool == .text {
                TextField("Digite o texto e clique na imagem", text: $text)
                    .textFieldStyle(.roundedBorder).frame(width: 230)
            }
            if tool != .blur {
                HStack(spacing: 5) {
                    ForEach(palette, id: \.self) { swatch in
                        Circle().fill(swatch).frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.primary.opacity(color == swatch ? 0.9 : 0.25),
                                                     lineWidth: color == swatch ? 2 : 1))
                            .onTapGesture { color = swatch }
                    }
                }
            }
            Spacer(minLength: 0)
            Button("Desfazer") { if !items.isEmpty { items.removeLast() } }
                .keyboardShortcut("z", modifiers: .command).disabled(items.isEmpty)
            Button("Cancelar") { finish(nil) }.keyboardShortcut(.cancelAction)
            Button("Salvar e copiar") { finish(render()) }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
        }
    }

    private func drag(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = CGPoint(x: value.startLocation.x / scale, y: value.startLocation.y / scale)
                let end = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
                draft = Annotation(tool: tool, start: start, end: tool == .text ? start : end, color: color, text: text)
            }
            .onEnded { _ in
                defer { draft = nil }
                guard let draft else { return }
                switch draft.tool {
                case .text:
                    if !draft.text.trimmingCharacters(in: .whitespaces).isEmpty { items.append(draft) }
                case .arrow:
                    if hypot(draft.end.x - draft.start.x, draft.end.y - draft.start.y) > 6 { items.append(draft) }
                case .rect, .blur:
                    if draft.rect.width > 4, draft.rect.height > 4 { items.append(draft) }
                }
            }
    }

    @MainActor private func render() -> NSImage? {
        let renderer = ImageRenderer(content: AnnotationCanvas(image: image, pixelated: pixelated,
                                                               pixelSize: pixelSize, items: items)
            .frame(width: pixelSize.width, height: pixelSize.height))
        renderer.scale = 1
        return renderer.nsImage
    }
}

/// Janela do editor de marcações. Salva uma cópia ("… anotado.png") ao lado do original.
enum AnnotateWindowController {
    private static var windows: [NSWindow] = []
    static var onSaved: ((URL) -> Void)?

    static func open(_ url: URL) {
        guard let source = NSImage(contentsOf: url),
              let rep = source.representations.first, rep.pixelsWide > 0,
              let ciImage = CIImage(contentsOf: url) else { return }
        let pixelSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        // A imagem é tratada em pixels reais; sem isso prints Retina sairiam com metade do tamanho.
        let image = NSImage(size: pixelSize)
        image.addRepresentation(rep)

        let filter = CIFilter(name: "CIPixellate")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(max(pixelSize.width / 70, 10), forKey: kCIInputScaleKey)
        var pixelated = image
        if let output = filter?.outputImage,
           let cg = CIContext().createCGImage(output, from: ciImage.extent) {
            pixelated = NSImage(cgImage: cg, size: pixelSize)
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = L("Anotar: %@", url.lastPathComponent)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AnnotateView(url: url, image: image, pixelated: pixelated,
                                                                  pixelSize: pixelSize) { [weak window] result in
            if let result { save(result, from: url) }
            window?.close()
            windows.removeAll { $0 === window }
        })
        window.center()
        windows.append(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func save(_ image: NSImage, from original: URL) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return }
        let name = original.deletingPathExtension().lastPathComponent + L(" anotado")
        var target = original.deletingLastPathComponent().appendingPathComponent(name + ".png")
        var counter = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = original.deletingLastPathComponent().appendingPathComponent("\(name) \(counter).png")
            counter += 1
        }
        guard (try? data.write(to: target)) != nil else { return }
        onSaved?(target)
    }
}
