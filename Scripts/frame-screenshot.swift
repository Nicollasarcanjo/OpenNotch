// Coloca a imagem do notch sobre um fundo em degradê, colada no topo, como na tela de verdade.
// Uso: swift Scripts/frame-screenshot.swift entrada.png saida.png
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]),
      let rep = source.representations.first else { exit(1) }
let size = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
let margin: CGFloat = 110
let canvas = CGSize(width: size.width + margin * 2, height: size.height + margin)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8,
                    bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func color(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let gradient = CGGradient(colorsSpace: space, colors: [color(0x3E8BFF), color(0x6D5BFF), color(0xA64BF4)] as CFArray,
                          locations: [0, 0.55, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: canvas.height), end: CGPoint(x: canvas.width, y: 0), options: [])
if let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    ctx.draw(cg, in: CGRect(x: margin, y: canvas.height - size.height, width: size.width, height: size.height))
}
let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
