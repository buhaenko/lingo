// Menu bar glyph: the language code with one dot per language underneath, the current one lit.
// With more than five languages it works like a page indicator: five dots around the current one, the edge dots
// smaller when more languages lie beyond — so the icon never grows wider than the code.

import AppKit

func glyph(code: String, count: Int, current: Int?) -> NSImage {
    let size: CGFloat = 11.5
    let system = NSFont.systemFont(ofSize: size, weight: .semibold)
    let font = system.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? system
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let textWidth = ceil((code as NSString).size(withAttributes: attributes).width)

    let dot: CGFloat = 2.2, gap: CGFloat = 2.8
    let dots = dotWindow(count: count, current: current)
    let shown = dots.count
    let dotsWidth = shown > 0 ? CGFloat(shown) * dot + CGFloat(shown - 1) * gap : 0
    let width = max(textWidth, dotsWidth)

    let image = NSImage(size: NSSize(width: width, height: 18), flipped: false) { _ in
        (code as NSString).draw(at: NSPoint(x: (width - textWidth) / 2, y: 10.5 - font.capHeight / 2 + font.descender),
                                withAttributes: attributes)
        for (slot, d) in dots.enumerated() {
            NSColor.black.withAlphaComponent(d.index == current ? 1 : 0.3).setFill()
            let size = dot * d.scale
            let x = (width - dotsWidth) / 2 + CGFloat(slot) * (dot + gap) + (dot - size) / 2
            NSBezierPath(ovalIn: NSRect(x: x, y: 1 + (dot - size) / 2, width: size, height: size)).fill()
        }
        return true
    }
    image.isTemplate = true      // follows the menu bar's colour
    return image
}

let maxDots = 5

/// Which languages get a dot: all of them up to five; otherwise five around the current one.
/// An edge dot is drawn smaller when there are more languages past it.
func dotWindow(count: Int, current: Int?) -> [(index: Int, scale: CGFloat)] {
    guard count > maxDots else { return (0..<max(count, 0)).map { ($0, 1) } }
    let center = min(max(current ?? 0, 0), count - 1)
    let start = min(max(center - maxDots / 2, 0), count - maxDots)
    return (start..<start + maxDots).map { index in
        let moreBefore = index == start && start > 0
        let moreAfter = index == start + maxDots - 1 && start + maxDots < count
        return (index, moreBefore || moreAfter ? 0.6 : 1)
    }
}
