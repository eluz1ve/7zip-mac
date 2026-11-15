import Cocoa

// Готовит записанные кадры для монтажа: убирает простой (одинаковые кадры дольше
// maxIdle секунд), уменьшает кадры и раскладывает их в public/<name>/.
//
//   prep <папка-записи> <выходная-папка> <offsetX> <offsetY> [maxIdle]
//
// offsetX/offsetY — где на экране (в точках) находился левый верхний угол записи.
// Пишет timeline.json: [{ "file": "k0001.png", "t": 0.0 }, ...] — время в секундах
// после сжатия простоя, плюс размеры и смещение кадра.

let args = CommandLine.arguments
guard args.count >= 5, let offsetX = Double(args[3]), let offsetY = Double(args[4]) else {
    print("usage: prep <rawDir> <outDir> <offsetX> <offsetY> [maxIdle]"); exit(2)
}
let rawDir = URL(fileURLWithPath: args[1], isDirectory: true)
let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
let maxIdle = args.count > 5 ? Double(args[5]) ?? 0.5 : 0.5
try? FileManager.default.removeItem(at: outDir)
try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// Список кадров и их время: из frames.tsv, а если его нет — по времени изменения файлов.
var frames: [(name: String, time: Double)] = []
let tsv = rawDir.appendingPathComponent("frames.tsv")
if let text = try? String(contentsOf: tsv, encoding: .utf8) {
    for line in text.split(separator: "\n").dropFirst() {
        let parts = line.split(separator: "\t")
        if parts.count >= 2, let t = Double(parts[1]) { frames.append((String(parts[0]), t)) }
    }
} else {
    let names = try! FileManager.default.contentsOfDirectory(atPath: rawDir.path).filter { $0.hasSuffix(".png") }.sorted()
    var t0: Date?
    for name in names {
        let date = (try? FileManager.default.attributesOfItem(atPath: rawDir.appendingPathComponent(name).path)[.modificationDate]) as? Date ?? Date()
        if t0 == nil { t0 = date }
        frames.append((name, date.timeIntervalSince(t0!)))
    }
}

func load(_ name: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(rawDir.appendingPathComponent(name) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func thumbnail(_ image: CGImage) -> [UInt8] {
    let tw = 192, th = Int(192 * Double(image.height) / Double(image.width))
    var pixels = [UInt8](repeating: 0, count: tw * th * 4)
    let context = CGContext(data: &pixels, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: tw * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
    return pixels
}

/// Уменьшенная копия (половина размера записи = 1x точек экрана × 1.5 для запаса чёткости).
func resized(_ image: CGImage, scale: Double) -> CGImage {
    let w = Int(Double(image.width) * scale), h = Int(Double(image.height) * scale)
    let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return context.makeImage()!
}

func save(_ image: CGImage, _ url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let scale = 0.75   // запись в 2x → 1.5x точек
var entries: [String] = []
var previous: [UInt8]?
var outputTime = 0.0
var lastKeptTime: Double?
var kept = 0
var width = 0, height = 0

for (index, frame) in frames.enumerated() {
    guard let image = load(frame.name) else { continue }
    let thumb = thumbnail(image)
    var changed = previous == nil
    if let previous = previous {
        for i in stride(from: 0, to: thumb.count, by: 1) where abs(Int(thumb[i]) - Int(previous[i])) > 2 { changed = true; break }
    }
    _ = index
    if !changed { continue }
    // Промежуток между соседними изменившимися кадрами: обычный — как есть, простой — не дольше maxIdle.
    if let last = lastKeptTime { outputTime += min(frame.time - last, maxIdle) }
    previous = thumb
    lastKeptTime = frame.time
    kept += 1
    let small = resized(image, scale: scale)
    width = small.width; height = small.height
    let name = String(format: "k%05d.png", kept)
    save(small, outDir.appendingPathComponent(name))
    entries.append("{\"file\":\"\(name)\",\"t\":\(String(format: "%.3f", outputTime)),\"src\":\"\(frame.name)\"}")
}

let json = """
{"width":\(width),"height":\(height),"scale":\(scale * 2),"offsetX":\(offsetX),"offsetY":\(offsetY),"duration":\(String(format: "%.3f", outputTime + 0.5)),
"frames":[
\(entries.joined(separator: ",\n"))
]}
"""
try! json.write(to: outDir.appendingPathComponent("timeline.json"), atomically: true, encoding: .utf8)
print("\(rawDir.lastPathComponent): \(frames.count) → \(kept) кадров, \(String(format: "%.1f", outputTime)) с")
