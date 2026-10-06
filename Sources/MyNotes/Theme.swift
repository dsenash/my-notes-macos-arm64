import AppKit
import SwiftUI
import Combine

// MARK: - Цвета: hex, яркость

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(
            format: "#%02X%02X%02X",
            Int((c.redComponent * 255).rounded()),
            Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent * 255).rounded())
        )
    }

    var isDarkColor: Bool {
        let c = usingColorSpace(.sRGB) ?? self
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent < 0.5
    }
}

// MARK: - Готовая палитра

struct PaletteColor: Identifiable {
    let name: String
    let hex: String
    var id: String { hex }
    var color: NSColor { NSColor(hex: hex) ?? .systemGray }
}

enum Palette {
    static let presets: [PaletteColor] = [
        PaletteColor(name: "Красный", hex: "#E5484D"),
        PaletteColor(name: "Оранжевый", hex: "#F08A24"),
        PaletteColor(name: "Жёлтый", hex: "#D9A400"),
        PaletteColor(name: "Зелёный", hex: "#30A46C"),
        PaletteColor(name: "Бирюзовый", hex: "#12A594"),
        PaletteColor(name: "Синий", hex: "#3E7BFA"),
        PaletteColor(name: "Фиолетовый", hex: "#8E4EC6"),
        PaletteColor(name: "Розовый", hex: "#D6409F"),
        PaletteColor(name: "Серый", hex: "#8B8D98")
    ]
}

enum ColorSwatch {
    /// Цветной кружок для пунктов меню (не шаблонное изображение, поэтому цвет сохраняется).
    static func image(_ color: NSColor, size: CGFloat = 12) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let oval = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            color.setFill()
            oval.fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            oval.lineWidth = 1
            oval.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}

// MARK: - Общая панель цветов

/// Открывает системную панель «Цвета» и передаёт выбранный цвет обработчику.
final class ColorPanelHelper: NSObject {
    static let shared = ColorPanelHelper()
    private var handler: ((NSColor) -> Void)?

    func present(initial: NSColor?, onChange: @escaping (NSColor) -> Void) {
        let panel = NSColorPanel.shared
        handler = nil
        panel.showsAlpha = false
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        if let initial { panel.color = initial }
        handler = onChange
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelClosed), name: NSWindow.willCloseNotification, object: panel
        )
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func changed(_ sender: NSColorPanel) {
        handler?(sender.color)
    }

    @objc private func panelClosed() {
        handler = nil
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Тема: основной цвет экранов для дня и ночи

final class Theme: ObservableObject {
    static let shared = Theme()

    /// nil — стандартный системный цвет.
    @Published var lightHex: String? = nil { didSet { Theme.save(lightHex, key: "theme.light") } }
    @Published var darkHex: String? = nil { didSet { Theme.save(darkHex, key: "theme.dark") } }
    /// Текущая системная тема macOS (обновляется из AppDelegate).
    @Published var systemIsDark = false

    private init() {
        lightHex = UserDefaults.standard.string(forKey: "theme.light")
        darkHex = UserDefaults.standard.string(forKey: "theme.dark")
    }

    private static func save(_ value: String?, key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Выбранный пользователем цвет для текущей системной темы.
    var background: NSColor? {
        (systemIsDark ? darkHex : lightHex).flatMap(NSColor.init(hex:))
    }

    var backgroundColor: Color? {
        background.map { Color(nsColor: $0) }
    }

    /// Боковая панель — тот же цвет, чуть смещённый, чтобы панель отличалась от редактора.
    var sidebarColor: Color? {
        guard let bg = background else { return nil }
        let shifted = bg.blended(withFraction: 0.07, of: bg.isDarkColor ? .white : .black) ?? bg
        return Color(nsColor: shifted)
    }

    /// Если выбран тёмный цвет при светлой теме (или наоборот), окно переключается
    /// в соответствующий вид, чтобы текст и элементы управления оставались читаемыми.
    var forcedAppearance: NSAppearance? {
        guard let bg = background else { return nil }
        return NSAppearance(named: bg.isDarkColor ? .darkAqua : .aqua)
    }
}
