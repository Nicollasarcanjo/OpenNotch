// Gera o ícone do OpenNotch (PNG 1024×1024). Uso: swift Scripts/make-icon.swift saida.png
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Base no formato dos ícones do macOS: quadrado arredondado de 824 pt com margem e sombra.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x4F7CFF))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()

// Fundo: degradê azul → violeta, como um papel de parede atrás do notch.
let background = CGGradient(colorsSpace: space,
                            colors: [color(0x3E8BFF), color(0x6D5BFF), color(0xA64BF4)] as CFArray,
                            locations: [0, 0.55, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: body.minX, y: body.maxY),
                       end: CGPoint(x: body.maxX, y: body.minY), options: [])

// Brilho suave logo abaixo do notch.
let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 700), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 700), endRadius: 430, options: [])

// O notch: preto, colado no topo, com cantos de cima côncavos e de baixo arredondados.
let notchWidth: CGFloat = 400, notchHeight: CGFloat = 214
let top = body.maxY, left = 512 - notchWidth / 2, right = 512 + notchWidth / 2, bottom = top - notchHeight
let t: CGFloat = 26, b: CGFloat = 70
let notch = CGMutablePath()
notch.move(to: CGPoint(x: left - t, y: top))
notch.addQuadCurve(to: CGPoint(x: left, y: top - t), control: CGPoint(x: left, y: top))
notch.addLine(to: CGPoint(x: left, y: bottom + b))
notch.addQuadCurve(to: CGPoint(x: left + b, y: bottom), control: CGPoint(x: left, y: bottom))
notch.addLine(to: CGPoint(x: right - b, y: bottom))
notch.addQuadCurve(to: CGPoint(x: right, y: bottom + b), control: CGPoint(x: right, y: bottom))
notch.addLine(to: CGPoint(x: right, y: top - t))
notch.addQuadCurve(to: CGPoint(x: right + t, y: top), control: CGPoint(x: right, y: top))
notch.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: color(0x1A1060, 0.55))
ctx.addPath(notch)
ctx.setFillColor(color(0x000000))
ctx.fillPath()
ctx.restoreGState()

// Dentro do notch: um ponto laranja (atividade) e barrinhas brancas (conteúdo ao vivo).
let rowY = bottom + notchHeight * 0.42
ctx.setFillColor(color(0xFF9F0A))
ctx.fillEllipse(in: CGRect(x: left + 58, y: rowY - 29, width: 58, height: 58))

let heights: [CGFloat] = [46, 88, 62, 104, 52]
let barWidth: CGFloat = 22, gap: CGFloat = 16
var x = right - 58 - (CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap)
ctx.setFillColor(color(0xFFFFFF))
for height in heights {
    let bar = CGRect(x: x, y: rowY - height / 2, width: barWidth, height: height)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
    ctx.fillPath()
    x += barWidth + gap
}
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
