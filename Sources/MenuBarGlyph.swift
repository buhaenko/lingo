// Menu bar glyph: the language code with one dot per language underneath, the current one lit.

import AppKit

func glyph(code: String, count: Int, current: Int?) -> NSImage {
    let size: CGFloat = 11.5
    let system = NSFont.systemFont(ofSize: size, weight: .semibold)
    let font = system.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? system
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let textWidth = ceil((code as NSString).size(withAttributes: attributes).width)

    let dot: CGFloat = 2.2, gap: CGFloat = 2.8
    let dotsWidth = count > 0 ? CGFloat(count) * dot + CGFloat(count - 1) * gap : 0
    let width = max(textWidth, dotsWidth)

    let image = NSImage(size: NSSize(width: width, height: 18), flipped: false) { _ in
        (code as NSString).draw(at: NSPoint(x: (width - textWidth) / 2, y: 10.5 - font.capHeight / 2 + font.descender),
                                withAttributes: attributes)
        for index in 0..<count {
            NSColor.black.withAlphaComponent(index == current ? 1 : 0.3).setFill()
            NSBezierPath(ovalIn: NSRect(x: (width - dotsWidth) / 2 + CGFloat(index) * (dot + gap), y: 1, width: dot, height: dot)).fill()
        }
        return true
    }
    image.isTemplate = true      // follows the menu bar's colour
    return image
}
