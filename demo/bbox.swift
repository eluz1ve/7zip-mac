import Cocoa

// Дописывает в timeline.json границы видимых окон каждого кадра (в точках экрана).
// Полоса Stage Manager у левого края (x < 150 pt) не учитывается.
//
//   bbox <папка с timeline.json>

let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let url = dir.appendingPathComponent("timeline.json")
var json = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
let scale = json["scale"] as! Double          // пикселей кадра на точку экрана
let offsetX = json["offsetX"] as! Double, offsetY = json["offsetY"] as! Double
var frames = json["frames"] as! [[String: Any]]

let factor = 4.0                               // анализируем уменьшенную в 4 раза копию
for i in frames.indices {
    let file = dir.appendingPathComponent(frames[i]["file"] as! String)
    guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
    let w = Int(Double(image.width) / factor), h = Int(Double(image.height) / factor)
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    let skipX = Int(max(0, (150 - offsetX)) * scale / factor)
    for y in 0..<h {
        for x in skipX..<w where pixels[(y * w + x) * 4 + 3] > 200 {
            // Первая строка буфера — верх картинки.
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    frames[i]["box"] = nil
    // Совсем маленькая область — это только курсор, окон в кадре нет.
    if maxX >= 0, Double(maxX - minX + 1) * factor / scale > 100, Double(maxY - minY + 1) * factor / scale > 60 {
        let k = factor / scale
        frames[i]["box"] = [Double(minX) * k + offsetX, Double(minY) * k + offsetY,
                            Double(maxX - minX + 1) * k, Double(maxY - minY + 1) * k].map { ($0 * 10).rounded() / 10 }
    }
}
json["frames"] = frames
try! JSONSerialization.data(withJSONObject: json, options: []).write(to: url)
print("\(dir.lastPathComponent): \(frames.filter { $0["box"] != nil }.count)/\(frames.count) кадров с окнами")
