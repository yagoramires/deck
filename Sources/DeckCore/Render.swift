import AppKit

enum Render {
    /// Tamanho de cada tela do D6 em pixels.
    static let size = 112

    static func tile(_ key: Key, store: Store) -> NSImage {
        let side = CGFloat(size)
        let icon = store.image(for: key, alt: showsAlt(key))
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()
            if let icon {
                let scale = min(side / icon.size.width, side / icon.size.height)
                let w = icon.size.width * scale, h = icon.size.height * scale
                icon.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
            }
            if !key.title.isEmpty {
                let shadow = NSShadow()
                shadow.shadowColor = .black
                shadow.shadowBlurRadius = 3
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: icon == nil ? 18 : 13, weight: .semibold),
                    .foregroundColor: NSColor.white,
                    .shadow: shadow,
                ]
                let text = key.title as NSString
                let textSize = text.size(withAttributes: attributes)
                let y = icon == nil ? (side - textSize.height) / 2 : 5
                text.draw(at: NSPoint(x: max(2, (side - textSize.width) / 2), y: y), withAttributes: attributes)
            }
            return true
        }
    }

    static func showsAlt(_ key: Key) -> Bool {
        guard case .audioToggle(_, let second) = key.action else { return false }
        return Audio.defaultOutputUID() == second
    }

    /// JPEG pro aparelho: a tela do D6 é montada de cabeça pra baixo.
    static func jpeg(_ image: NSImage) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let context = NSGraphicsContext.current!.cgContext
        context.translateBy(x: CGFloat(size), y: CGFloat(size))
        context.rotate(by: .pi)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) ?? Data()
    }
}

/// O padrão de ícone do usuário: fundo preto com brilho no centro, logo em silhueta com degradê
/// ciano → rosa e cópias deslocadas em ciano e magenta (efeito glitch).
enum IconStyle {
    static func make(_ source: NSImage, side: Int = 256) -> NSImage {
        let s = CGFloat(side)
        let glyphSide = Int(s * 0.62)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        let rgb = CGColorSpaceCreateDeviceRGB()
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: rgb, components: [r, g, b, a])! }

        context.setFillColor(color(0, 0, 0))
        context.fill(CGRect(x: 0, y: 0, width: s, height: s))
        let glow = CGGradient(colorsSpace: rgb, colors: [color(0.15, 0.10, 0.15), color(0, 0, 0)] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(glow, startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: 0,
                                   endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: s * 0.6, options: [])

        guard let mask = mask(source, side: side) else { return NSImage(cgImage: context.makeImage()!, size: NSSize(width: s, height: s)) }
        let fit = CGFloat(glyphSide) / CGFloat(max(mask.width, mask.height))
        let gw = CGFloat(mask.width) * fit, gh = CGFloat(mask.height) * fit
        let glyph = CGRect(x: (s - gw) / 2, y: (s - gh) / 2, width: gw, height: gh)
        let offset = s * 0.022
        func copy(_ tint: CGColor, dx: CGFloat, dy: CGFloat) {
            let rect = glyph.offsetBy(dx: dx, dy: dy)
            context.saveGState()
            context.setBlendMode(.screen)
            context.clip(to: rect, mask: mask)
            context.setFillColor(tint)
            context.fill(rect)
            context.restoreGState()
        }
        // y cresce pra cima: magenta embaixo à direita, ciano em cima à esquerda.
        copy(color(0.95, 0.12, 0.72, 0.95), dx: offset, dy: -offset * 0.6)
        copy(color(0.05, 0.92, 1.0, 0.95), dx: -offset, dy: offset * 0.6)
        context.saveGState()
        context.clip(to: glyph, mask: mask)
        let fill = CGGradient(colorsSpace: rgb, colors: [color(0.70, 0.97, 0.94), color(0.97, 0.72, 0.90)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(fill, start: CGPoint(x: glyph.minX, y: glyph.maxY), end: CGPoint(x: glyph.maxX, y: glyph.minY), options: [])
        context.restoreGState()
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: s, height: s))
    }

    /// Silhueta do logo em tons de cinza (branco = logo). Imagem com fundo transparente usa a
    /// transparência; imagem chapada (ícone de app, foto) usa o que difere da cor da borda.
    static func mask(_ source: NSImage, side m: Int) -> CGImage? {
        guard let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: m, height: m, bitsPerComponent: 8, bytesPerRow: m * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let scale = min(Double(m) / Double(cg.width), Double(m) / Double(cg.height))
        let w = Double(cg.width) * scale, h = Double(cg.height) * scale
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: (Double(m) - w) / 2, y: (Double(m) - h) / 2, width: w, height: h))
        guard let data = context.data else { return nil }
        let bytesPerRow = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * m)
        func rgba(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
            let p = y * bytesPerRow + x * 4
            let a = Double(pixels[p + 3]) / 255
            guard a > 0 else { return (0, 0, 0, 0) }
            return (Double(pixels[p]) / 255 / a, Double(pixels[p + 1]) / 255 / a, Double(pixels[p + 2]) / 255 / a, a)
        }

        var minX = m, minY = m, maxX = -1, maxY = -1, opaque = 0
        for y in 0..<m {
            for x in 0..<m where rgba(x, y).a > 0.5 {
                opaque += 1
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard opaque > 0 else { return nil }
        let boxArea = (maxX - minX + 1) * (maxY - minY + 1)

        var out = [UInt8](repeating: 0, count: m * m)
        if Double(opaque) / Double(boxArea) > 0.85 {
            let band = max(2, min(maxX - minX, maxY - minY) / 8)
            var sum = (0.0, 0.0, 0.0), count = 0.0
            for y in minY...maxY {
                for x in minX...maxX where x - minX < band || maxX - x < band || y - minY < band || maxY - y < band {
                    let p = rgba(x, y)
                    guard p.a > 0.5 else { continue }
                    sum.0 += p.r; sum.1 += p.g; sum.2 += p.b; count += 1
                }
            }
            let background = (sum.0 / count, sum.1 / count, sum.2 / count)
            for y in 0..<m {
                for x in 0..<m {
                    let p = rgba(x, y)
                    let distance = (pow(p.r - background.0, 2) + pow(p.g - background.1, 2) + pow(p.b - background.2, 2)) / 3
                    // Borda semitransparente (sombra do ícone de app) não conta como logo.
                    out[y * m + x] = UInt8(255 * smoothstep(0.85, 1, p.a) * smoothstep(0.10, 0.25, distance.squareRoot()))
                }
            }
        } else {
            for y in 0..<m {
                for x in 0..<m { out[y * m + x] = pixels[y * bytesPerRow + x * 4 + 3] }
            }
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData),
              let image = CGImage(width: m, height: m, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: m,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        // Recorta no logo, pra o espaço em volta (padding do ícone de app) não encolher o desenho.
        var gx0 = m, gy0 = m, gx1 = -1, gy1 = -1
        for y in 0..<m {
            for x in 0..<m where out[y * m + x] > 24 {
                gx0 = min(gx0, x); gx1 = max(gx1, x); gy0 = min(gy0, y); gy1 = max(gy1, y)
            }
        }
        guard gx1 >= gx0 else { return nil }
        return image.cropping(to: CGRect(x: gx0, y: gy0, width: gx1 - gx0 + 1, height: gy1 - gy0 + 1))
    }

    private static func smoothstep(_ low: Double, _ high: Double, _ x: Double) -> Double {
        let t = min(max((x - low) / (high - low), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
