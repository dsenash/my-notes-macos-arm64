import AppKit

// Служебный режим для сборки: рисует иконку приложения в набор PNG (используется build.sh).
if let i = CommandLine.arguments.firstIndex(of: "--render-icons"), i + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sizes: [(String, Int)] = [
            ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
        ]
        for (name, px) in sizes {
            try GothicN.appIconPNG(pixels: px).write(to: dir.appendingPathComponent(name))
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Не удалось создать иконки: \(error)\n".utf8))
        exit(1)
    }
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
