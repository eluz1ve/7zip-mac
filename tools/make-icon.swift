import Cocoa

// Рисует картинки для значка 7-Zip (1024×1024).
//
//   make-icon tile        out.png  — готовый значок: тёмная плитка, белые «7» и «z»
//                                    (запасной .icns и значок в меню Finder)
//   make-icon glyph-light out.png  — только знак на прозрачном фоне, чёрный (слой для светлой темы)
//   make-icon glyph-dark  out.png  — только знак на прозрачном фоне, белый (слой для тёмной темы)

let size: CGFloat = 1024
guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-icon tile|glyph-light|glyph-dark out.png\n".utf8))
    exit(2)
}
let mode = CommandLine.arguments[1]

let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

func draw(_ text: String, centeredIn rect: NSRect, color: NSColor, fontSize: CGFloat) {
    let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let bounds = string.size()
    string.draw(at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2))
}

/// Знак «7» + «z» в квадрате. `scale` — размер относительно всего холста, центр — в середине.
func drawGlyph(foreground: NSColor, knockout: NSColor, scale: CGFloat) {
    let transform = NSAffineTransform()
    transform.translateX(by: size / 2, yBy: size / 2)
    transform.scale(by: scale)
    transform.translateX(by: -size / 2, yBy: -size / 2)
    transform.concat()

    draw("7", centeredIn: NSRect(x: 110, y: 212, width: 400, height: 600), color: foreground, fontSize: 600)
    let box = NSRect(x: 512, y: 282, width: 400, height: 460)
    foreground.setFill()
    NSBezierPath(roundedRect: box, xRadius: 52, yRadius: 52).fill()
    draw("z", centeredIn: box.offsetBy(dx: 0, dy: 30), color: knockout, fontSize: 500)
}

switch mode {
case "tile":
    // Плитка в пропорциях значков macOS; тёмная — одинаково хорошо смотрится в светлой и тёмной теме.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(white: 0.24, alpha: 1), ending: NSColor(white: 0.10, alpha: 1))!
        .draw(in: path, angle: -90)
    NSColor(white: 1, alpha: 0.22).setStroke()
    path.lineWidth = 6
    path.stroke()
    drawGlyph(foreground: .white, knockout: NSColor(white: 0.12, alpha: 1), scale: 0.68)
case "glyph-light":
    drawGlyph(foreground: NSColor(white: 0.08, alpha: 1), knockout: .white, scale: 0.78)
case "glyph-dark":
    drawGlyph(foreground: .white, knockout: NSColor(white: 0.12, alpha: 1), scale: 0.78)
default:
    FileHandle.standardError.write(Data("unknown mode \(mode)\n".utf8))
    exit(2)
}

NSGraphicsContext.restoreGraphicsState()
try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
