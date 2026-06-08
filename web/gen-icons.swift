// Genera icon-192.png e icon-512.png para la PWA. Uso: swift gen-icons.swift
import AppKit

func makeIcon(_ size: Int, _ path: String) {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Fondo redondeado con gradiente azul oscuro
    let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s),
                          xRadius: s * 0.22, yRadius: s * 0.22)
    bg.addClip()
    let grad = NSGradient(colors: [
        NSColor(srgbRed: 0.05, green: 0.08, blue: 0.16, alpha: 1),
        NSColor(srgbRed: 0.10, green: 0.18, blue: 0.40, alpha: 1)])!
    grad.draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: 115)

    // Símbolo Bluetooth blanco al centro
    let bt = NSBezierPath()
    let cx = s * 0.5, w = s * 0.16, top = s * 0.20, bot = s * 0.80, mid = s * 0.5
    bt.move(to: NSPoint(x: cx, y: bot))
    bt.line(to: NSPoint(x: cx + w, y: s * 0.65))
    bt.line(to: NSPoint(x: cx - w, y: s * 0.35))
    bt.line(to: NSPoint(x: cx, y: top))
    bt.line(to: NSPoint(x: cx, y: bot))
    bt.line(to: NSPoint(x: cx - w, y: s * 0.65))
    bt.line(to: NSPoint(x: cx + w, y: s * 0.35))
    bt.line(to: NSPoint(x: cx, y: top))
    bt.lineWidth = s * 0.045
    bt.lineJoinStyle = .round
    bt.lineCapStyle = .round
    NSColor.white.setStroke()
    bt.stroke()
    _ = mid

    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: path))
    print("✅ \(path) (\(size)x\(size))")
}

let dir = (CommandLine.arguments.count > 1) ? CommandLine.arguments[1] : "."
makeIcon(192, "\(dir)/icon-192.png")
makeIcon(512, "\(dir)/icon-512.png")
