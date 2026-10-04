import AppKit

/// Стилизованная готическая буква «N» (штрихи широкого пера, как в textura),
/// нарисованная кодом: иконка приложения и значок в трее.
enum GothicN {
    private struct Stroke {
        let a: CGPoint
        let b: CGPoint
        let nib: CGFloat
    }

    // Координаты в сетке 1024×1024, ось Y направлена вверх.
    private static let strokes: [Stroke] = [
        // левая ножка
        Stroke(a: CGPoint(x: 310, y: 765), b: CGPoint(x: 310, y: 245), nib: 130),
        // диагональ
        Stroke(a: CGPoint(x: 330, y: 745), b: CGPoint(x: 690, y: 265), nib: 110),
        // правая ножка
        Stroke(a: CGPoint(x: 710, y: 765), b: CGPoint(x: 710, y: 245), nib: 130),
        // засечки сверху
        Stroke(a: CGPoint(x: 245, y: 775), b: CGPoint(x: 355, y: 790), nib: 72),
        Stroke(a: CGPoint(x: 650, y: 775), b: CGPoint(x: 775, y: 792), nib: 72),
        // основание левой ножки и «хвост» правой
        Stroke(a: CGPoint(x: 240, y: 238), b: CGPoint(x: 375, y: 236), nib: 64),
        Stroke(a: CGPoint(x: 712, y: 242), b: CGPoint(x: 805, y: 305), nib: 64),
        // декоративный ромб над левой ножкой
        Stroke(a: CGPoint(x: 296, y: 818), b: CGPoint(x: 324, y: 832), nib: 56)
    ]

    private static let nibAngle: CGFloat = 40 * .pi / 180

    private static func hull(of s: Stroke) -> [CGPoint] {
        let dx = cos(nibAngle) * s.nib / 2
        let dy = sin(nibAngle) * s.nib / 2
        let points = [
            CGPoint(x: s.a.x - dx, y: s.a.y - dy), CGPoint(x: s.a.x + dx, y: s.a.y + dy),
            CGPoint(x: s.b.x - dx, y: s.b.y - dy), CGPoint(x: s.b.x + dx, y: s.b.y + dy)
        ]
        return convexHull(points)
    }

    private static func convexHull(_ pts: [CGPoint]) -> [CGPoint] {
        let p = pts.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [CGPoint] = []
        for q in p {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], q) <= 0 { lower.removeLast() }
            lower.append(q)
        }
        var upper: [CGPoint] = []
        for q in p.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], q) <= 0 { upper.removeLast() }
            upper.append(q)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    private static func letterPath() -> NSBezierPath {
        let path = NSBezierPath()
        for stroke in strokes {
            let poly = hull(of: stroke)
            guard let first = poly.first else { continue }
            path.move(to: first)
            for pt in poly.dropFirst() { path.line(to: pt) }
            path.close()
        }
        return path
    }

    private static func fitted(_ path: NSBezierPath, into target: NSRect) -> NSBezierPath {
        let b = path.bounds
        let s = min(target.width / b.width, target.height / b.height)
        let t = AffineTransform(
            m11: s, m12: 0, m21: 0, m22: s,
            tX: target.midX - s * b.midX, tY: target.midY - s * b.midY
        )
        let copy = path.copy() as! NSBezierPath
        copy.transform(using: t)
        return copy
    }

    // MARK: - Иконка приложения

    /// Рисует иконку в системе координат 1024×1024 (начало — слева снизу).
    static func drawAppIcon() {
        let body = NSRect(x: 100, y: 100, width: 824, height: 824)
        let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

        let gold = NSColor(srgbRed: 0.89, green: 0.73, blue: 0.36, alpha: 1)
        let goldDark = NSColor(srgbRed: 0.55, green: 0.38, blue: 0.12, alpha: 1)
        let goldLight = NSColor(srgbRed: 0.99, green: 0.89, blue: 0.58, alpha: 1)

        // тень корпуса
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowOffset = NSSize(width: 0, height: -14)
        shadow.shadowBlurRadius = 28
        shadow.set()
        NSColor(srgbRed: 0.3, green: 0.04, blue: 0.08, alpha: 1).setFill()
        bodyPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        // фон — глубокий бордовый «пергамент витража»
        NSGraphicsContext.saveGraphicsState()
        bodyPath.addClip()
        NSGradient(colors: [
            NSColor(srgbRed: 0.24, green: 0.03, blue: 0.07, alpha: 1),
            NSColor(srgbRed: 0.50, green: 0.09, blue: 0.13, alpha: 1)
        ])?.draw(in: body, angle: 90)
        NSGradient(colors: [NSColor(white: 1, alpha: 0.16), NSColor(white: 1, alpha: 0)])?
            .draw(fromCenter: NSPoint(x: 512, y: 640), radius: 0, toCenter: NSPoint(x: 512, y: 640), radius: 480, options: [])
        NSGraphicsContext.restoreGraphicsState()

        // двойная золотая рамка
        gold.setStroke()
        let outer = NSBezierPath(roundedRect: body.insetBy(dx: 52, dy: 52), xRadius: 135, yRadius: 135)
        outer.lineWidth = 9
        outer.stroke()
        gold.withAlphaComponent(0.7).setStroke()
        let inner = NSBezierPath(roundedRect: body.insetBy(dx: 74, dy: 74), xRadius: 115, yRadius: 115)
        inner.lineWidth = 3
        inner.stroke()

        // ромбы по углам
        gold.setFill()
        for c in [NSPoint(x: 205, y: 205), NSPoint(x: 819, y: 205), NSPoint(x: 205, y: 819), NSPoint(x: 819, y: 819)] {
            let d = NSBezierPath()
            d.move(to: NSPoint(x: c.x, y: c.y + 24))
            d.line(to: NSPoint(x: c.x + 24, y: c.y))
            d.line(to: NSPoint(x: c.x, y: c.y - 24))
            d.line(to: NSPoint(x: c.x - 24, y: c.y))
            d.close()
            d.fill()
        }

        // буква N
        let letter = fitted(letterPath(), into: NSRect(x: 232, y: 232, width: 560, height: 560))

        NSGraphicsContext.saveGraphicsState()
        let shade = letter.copy() as! NSBezierPath
        shade.transform(using: AffineTransform(translationByX: 0, byY: -14))
        NSColor.black.withAlphaComponent(0.55).setFill()
        shade.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        letter.addClip()
        NSGradient(colors: [goldDark, gold, goldLight])?.draw(in: letter.bounds, angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        NSColor(srgbRed: 0.25, green: 0.12, blue: 0.02, alpha: 0.9).setStroke()
        letter.lineWidth = 5
        letter.lineJoinStyle = .miter
        letter.stroke()
    }

    static func appIconPNG(pixels: Int) throws -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            throw NSError(domain: "GothicN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось создать растр"])
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let scale = CGFloat(pixels) / 1024
        let t = NSAffineTransform()
        t.scaleX(by: scale, yBy: scale)
        t.concat()
        drawAppIcon()
        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "GothicN", code: 2, userInfo: [NSLocalizedDescriptionKey: "Не удалось закодировать PNG"])
        }
        return png
    }

    static func appIconImage(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform()
            t.scaleX(by: rect.width / 1024, yBy: rect.height / 1024)
            t.concat()
            drawAppIcon()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }

    // MARK: - Значок в трее (шаблонное изображение)

    static func trayImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let path = fitted(letterPath(), into: rect.insetBy(dx: 1.5, dy: 1.5))
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
