// Menu bar glyph: the language code, and under it where that language sits in the list.
// The indicator is the person's choice (Settings → Indicator):
//   Auto     — dots for up to five languages, a slider from six on (default)
//   Dots     — one dot per language; past five, five dots around the current one, the edge ones smaller
//   Slider   — a thin track with a pill that slides to the current language
//   Segments — the track split into one segment per language, the current one lit
//   Number   — a small "3/8" under the code
// Every style keeps the icon narrow however many languages there are, and `position` can be fractional so a
// switch slides from the old language to the new one.

import AppKit

enum Indicator: String, CaseIterable, Identifiable {
    case auto, dots, slider, segments, number
    var id: String { rawValue }

    static var current: Indicator { UserDefaults.standard.string(forKey: "indicator").flatMap(Indicator.init) ?? .auto }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .dots: "Dots"
        case .slider: "Slider"
        case .segments: "Segments"
        case .number: "Number"
        }
    }

    /// What's actually drawn for this many languages (Auto picks).
    func resolved(count: Int) -> Indicator {
        if count <= 1 && self != .number { return .dots }          // one language: a single dot, not a full bar
        return self == .auto ? (count <= maxDots ? .dots : .slider) : self
    }
}

let maxDots = 5
private let trackWidth: CGFloat = 20

/// - position: index of the current language; fractional while a switch animates; nil when the active layout isn't in the list.
func glyph(code: String, count: Int, current position: Double?, style: Indicator = .current) -> NSImage {
    let size: CGFloat = 11.5
    let system = NSFont.systemFont(ofSize: size, weight: .semibold)
    let font = system.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? system
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let textWidth = ceil((code as NSString).size(withAttributes: attributes).width)
    let style = style.resolved(count: count)

    let number = "\(position.map { Int($0.rounded()) + 1 } ?? 0)/\(count)"
    let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 6.5, weight: .bold)
    let numberWidth = style == .number && count > 0 ? ceil((number as NSString).size(withAttributes: [.font: numberFont]).width) : 0

    let dot: CGFloat = 2.2, gap: CGFloat = 2.8
    let dots = style == .dots ? dotWindow(count: count, current: position) : []
    let dotsWidth = dots.isEmpty ? 0 : CGFloat(dots.count) * dot + CGFloat(dots.count - 1) * gap
    let barWidth: CGFloat = (style == .slider || style == .segments) && count > 0 ? max(textWidth, trackWidth) : 0
    let width = max(textWidth, numberWidth, dotsWidth, barWidth)
    let codeX = (width - textWidth) / 2

    let image = NSImage(size: NSSize(width: width, height: 18), flipped: false) { _ in
        let baseline = 10.5 - font.capHeight / 2 + font.descender
        (code as NSString).draw(at: NSPoint(x: codeX, y: baseline), withAttributes: attributes)
        switch style {
        case .dots:
            for (slot, d) in dots.enumerated() {
                // lit by closeness, so a switch fades from one dot into the next
                let lit = position.map { max(0, 1 - abs(Double(d.index) - $0)) } ?? 0
                NSColor.black.withAlphaComponent(0.3 + 0.7 * lit).setFill()
                let size = dot * d.scale
                let x = (width - dotsWidth) / 2 + CGFloat(slot) * (dot + gap) + (dot - size) / 2
                NSBezierPath(ovalIn: NSRect(x: x, y: 1 + (dot - size) / 2, width: size, height: size)).fill()
            }
        case .slider:
            guard count > 0 else { break }
            let x0 = (width - barWidth) / 2
            NSColor.black.withAlphaComponent(0.28).setFill()
            NSBezierPath(roundedRect: NSRect(x: x0, y: 1.2, width: barWidth, height: 1.4), xRadius: 0.7, yRadius: 0.7).fill()
            if let position {
                let pill = max(4, barWidth / CGFloat(count))
                let x = x0 + (count > 1 ? (barWidth - pill) * CGFloat(position) / CGFloat(count - 1) : (barWidth - pill) / 2)
                NSColor.black.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 0.8, width: pill, height: 2.2), xRadius: 1.1, yRadius: 1.1).fill()
            }
        case .segments:
            guard count > 0 else { break }
            let x0 = (width - barWidth) / 2
            let segGap: CGFloat = count > 8 ? 0.8 : 1.4
            let seg = max(0.6, (barWidth - segGap * CGFloat(count - 1)) / CGFloat(count))
            for i in 0..<count {
                let lit = position.map { max(0, 1 - abs(Double(i) - $0)) } ?? 0
                NSColor.black.withAlphaComponent(0.28 + 0.72 * lit).setFill()
                NSBezierPath(roundedRect: NSRect(x: x0 + CGFloat(i) * (seg + segGap), y: 1, width: seg, height: 1.8), xRadius: min(0.9, seg / 2), yRadius: 0.9).fill()
            }
        case .number:
            guard count > 0 else { break }
            (number as NSString).draw(at: NSPoint(x: (width - numberWidth) / 2, y: -1.6),
                                      withAttributes: [.font: numberFont, .foregroundColor: NSColor.black.withAlphaComponent(0.6)])
        case .auto:
            break
        }
        return true
    }
    image.isTemplate = true      // follows the menu bar's colour
    return image
}

/// Which languages get a dot: all of them up to five; otherwise five around the current one.
/// An edge dot is drawn smaller when there are more languages past it.
func dotWindow(count: Int, current: Double?) -> [(index: Int, scale: CGFloat)] {
    guard count > maxDots else { return (0..<max(count, 0)).map { ($0, 1) } }
    let center = min(max(Int((current ?? 0).rounded()), 0), count - 1)
    let start = min(max(center - maxDots / 2, 0), count - maxDots)
    return (start..<start + maxDots).map { index in
        let moreBefore = index == start && start > 0
        let moreAfter = index == start + maxDots - 1 && start + maxDots < count
        return (index, moreBefore || moreAfter ? 0.6 : 1)
    }
}
