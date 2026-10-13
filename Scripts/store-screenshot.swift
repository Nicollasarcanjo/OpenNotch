// Monta uma captura de tela no tamanho que a Microsoft Store pede (1920×1080) a partir de
// uma imagem do autoteste do Windows. Uso:
//   swift Scripts/store-screenshot.swift entrada.png saida.png "Legenda" [escala]
import AppKit

let args = CommandLine.arguments
guard args.count >= 4, let source = NSImage(contentsOfFile: args[1]),
      let rep = source.representations.first,
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { exit(1) }
let scale = args.count > 4 ? CGFloat(Double(args[4]) ?? 2) : 2
let canvas = CGSize(width: 1920, height: 1080)
let size = CGSize(width: CGFloat(rep.pixelsWide) * scale, height: CGFloat(rep.pixelsHigh) * scale)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8,
                    bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Mesmo fundo usado nas imagens do autoteste, para o recorte do notch não deixar marca.
ctx.setFillColor(CGColor(red: 0x6E / 255, green: 0x7B / 255, blue: 0x8B / 255, alpha: 1))
ctx.fill(CGRect(origin: .zero, size: canvas))
ctx.interpolationQuality = .high
// O notch fica colado no topo; janelas (como a de configurações) ficam centralizadas.
let isNotch = args[1].contains("notch-")
let y = isNotch ? canvas.height - size.height : (canvas.height - size.height) / 2 + 40
ctx.draw(cg, in: CGRect(x: (canvas.width - size.width) / 2, y: y, width: size.width, height: size.height))

let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.current = graphics
let style = NSMutableParagraphStyle()
style.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 54, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: style,
]
(args[3] as NSString).draw(in: CGRect(x: 120, y: isNotch ? 250 : 30, width: canvas.width - 240, height: 140),
                           withAttributes: attributes)
graphics.flushGraphics()

let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
