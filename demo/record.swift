import Cocoa
import ScreenCaptureKit

// Записывает кадры демо-видео: только окна 7-Zip, одно окно Finder и меню Finder.
// Всё остальное (рабочий стол, Dock, другие программы) в кадр не попадает — фон прозрачный.
//
//   record <папка> <finderWindowNumber> <x> <y> <w> <h> [fps]
//
// x y w h — область экрана в точках (начало координат — левый верхний угол главного экрана).
// Пишет frame-000001.png … и frames.tsv (имя, время в секундах, изменение относительно
// предыдущего кадра). Останавливается, когда в папке появляется файл STOP.

let args = CommandLine.arguments
guard args.count >= 7, let finderWindow = UInt32(args[2]),
      let x = Double(args[3]), let y = Double(args[4]), let w = Double(args[5]), let h = Double(args[6]) else {
    FileHandle.standardError.write(Data("usage: record <dir> <finderWindow> <x> <y> <w> <h> [fps]\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
let fps = args.count > 7 ? Double(args[7]) ?? 12 : 12
let region = CGRect(x: x, y: y, width: w, height: h)
let stopFile = outDir.appendingPathComponent("STOP")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: stopFile)

/// Маленькая серая копия кадра для сравнения соседних кадров.
func thumbnail(_ image: CGImage) -> [UInt8] {
    let tw = 96, th = Int(96 * Double(image.height) / Double(image.width))
    var pixels = [UInt8](repeating: 0, count: tw * th)
    let context = CGContext(data: &pixels, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: tw,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    context.interpolationQuality = .low
    context.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
    return pixels
}

func save(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let logURL = outDir.appendingPathComponent("frames.tsv")
FileManager.default.createFile(atPath: logURL.path, contents: Data("file\ttime\tdiff\n".utf8))
let logHandle = try! FileHandle(forWritingTo: logURL)
logHandle.seekToEndOfFile()

let task = Task {
    var previous: [UInt8]?
    var index = 0
    let start = Date()
    let interval = 1.0 / fps

    while !FileManager.default.fileExists(atPath: stopFile.path) {
        let tick = Date()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: region.midX, y: region.midY)) })
                    ?? content.displays.first else { break }
            let windows = content.windows.filter { window in
                guard let app = window.owningApplication else { return false }
                switch app.bundleIdentifier {
                case "local.sevenzip.SevenZip":
                    return true
                case "com.apple.finder":
                    // Демо-окно Finder и его контекстные меню (уровень выше обычных окон).
                    return window.windowID == finderWindow || window.windowLayer > 0
                default:
                    return false
                }
            }
            let filter = SCContentFilter(display: display, including: windows)
            let config = SCStreamConfiguration()
            config.sourceRect = CGRect(x: region.minX - display.frame.minX, y: region.minY - display.frame.minY,
                                       width: region.width, height: region.height)
            config.width = Int(region.width * 2)
            config.height = Int(region.height * 2)
            config.showsCursor = true
            config.backgroundColor = .clear
            config.colorSpaceName = CGColorSpace.sRGB
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

            let thumb = thumbnail(image)
            var diff = 0
            if let previous = previous {
                for i in 0..<thumb.count where abs(Int(thumb[i]) - Int(previous[i])) > 6 { diff += 1 }
            } else {
                diff = thumb.count
            }
            previous = thumb
            index += 1
            let name = String(format: "frame-%06d.png", index)
            save(image, to: outDir.appendingPathComponent(name))
            // Пишем сразу, чтобы журнал не потерялся, если запись прервут.
            logHandle.write(Data("\(name)\t\(String(format: "%.3f", tick.timeIntervalSince(start)))\t\(diff)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("capture error: \(error)\n".utf8))
        }
        let spent = Date().timeIntervalSince(tick)
        if spent < interval { try? await Task.sleep(nanoseconds: UInt64((interval - spent) * 1e9)) }
    }
    try? logHandle.close()
    print("frames: \(index)")
    exit(0)
}
RunLoop.main.run()
