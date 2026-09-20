import AppKit
import Foundation

enum ColorFormat: String, CaseIterable, Sendable {
    case hex, rgb, hsl

    var displayName: String {
        switch self {
        case .hex: "HEX"
        case .rgb: "RGB"
        case .hsl: "HSL"
        }
    }

    var example: String {
        switch self {
        case .hex: "#FF8800"
        case .rgb: "rgb(255, 136, 0)"
        case .hsl: "hsl(32, 100%, 50%)"
        }
    }
}

/// Parsing and formatting CSS-style colours — for the eyedropper's output and for
/// recognizing a copied `#FF8800` as a colour rather than plain text.
enum ColorTools {
    static func format(_ color: NSColor, as format: ColorFormat) -> String {
        let (r, g, b) = rgb255(color)
        switch format {
        case .hex:
            return hex(color)
        case .rgb:
            return "rgb(\(r), \(g), \(b))"
        case .hsl:
            let (h, s, l) = hsl(r: r, g: g, b: b)
            return "hsl(\(h), \(s)%, \(l)%)"
        }
    }

    static func hex(_ color: NSColor) -> String {
        let (r, g, b) = rgb255(color)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func rgb255(_ color: NSColor) -> (Int, Int, Int) {
        let c = color.usingColorSpace(.sRGB) ?? color
        func byte(_ v: CGFloat) -> Int { max(0, min(255, Int((v * 255).rounded()))) }
        return (byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }

    private static func hsl(r: Int, g: Int, b: Int) -> (Int, Int, Int) {
        let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
        let maxV = max(rf, gf, bf), minV = min(rf, gf, bf)
        let l = (maxV + minV) / 2
        guard maxV != minV else { return (0, 0, Int((l * 100).rounded())) }

        let d = maxV - minV
        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var h: Double
        switch maxV {
        case rf: h = (gf - bf) / d + (gf < bf ? 6 : 0)
        case gf: h = (bf - rf) / d + 2
        default: h = (rf - gf) / d + 4
        }
        h *= 60
        return (Int(h.rounded()) % 360, Int((s * 100).rounded()), Int((l * 100).rounded()))
    }

    /// `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, `rgb()/rgba()`, `hsl()/hsla()`. The `#` is
    /// required for hex — bare "add" or "bad" or "fed" are words far more often than colours.
    static func parse(_ string: String) -> NSColor? {
        let t = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count <= 40 else { return nil }

        if t.hasPrefix("#") {
            var digits = String(t.dropFirst())
            guard [3, 4, 6, 8].contains(digits.count),
                  digits.allSatisfy(\.isHexDigit) else { return nil }
            if digits.count <= 4 { digits = digits.map { "\($0)\($0)" }.joined() }
            guard let value = UInt64(digits.prefix(6), radix: 16) else { return nil }
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }

        let lowered = t.lowercased()
        let numbers = #"(\d{1,3}(?:\.\d+)?)"#
        if let m = match(#"^rgba?\(\s*\#(numbers)\s*[, ]\s*\#(numbers)\s*[, ]\s*\#(numbers)\s*(?:[,/]\s*[\d.]+%?\s*)?\)$"#, in: lowered),
           m.count == 3, m.allSatisfy({ $0 <= 255 }) {
            return NSColor(srgbRed: m[0] / 255, green: m[1] / 255, blue: m[2] / 255, alpha: 1)
        }
        if let m = match(#"^hsla?\(\s*\#(numbers)(?:deg)?\s*[, ]\s*\#(numbers)%\s*[, ]\s*\#(numbers)%\s*(?:[,/]\s*[\d.]+%?\s*)?\)$"#, in: lowered),
           m.count == 3, m[0] <= 360, m[1] <= 100, m[2] <= 100 {
            return NSColor(hue: m[0] / 360, saturation: m[1] / 100, brightness: 0, alpha: 1)
                .withHSL(h: m[0], s: m[1], l: m[2])
        }
        return nil
    }

    private static func match(_ pattern: String, in string: String) -> [Double]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string))
        else { return nil }
        return (1..<result.numberOfRanges).compactMap { index in
            Range(result.range(at: index), in: string).flatMap { Double(string[$0]) }
        }
    }
}

private extension NSColor {
    /// HSL → sRGB. `NSColor` only speaks HSB natively.
    func withHSL(h: Double, s: Double, l: Double) -> NSColor {
        let s = s / 100, l = l / 100
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<60: (r, g, b) = (c, x, 0)
        case ..<120: (r, g, b) = (x, c, 0)
        case ..<180: (r, g, b) = (0, c, x)
        case ..<240: (r, g, b) = (0, x, c)
        case ..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return NSColor(srgbRed: r + m, green: g + m, blue: b + m, alpha: 1)
    }
}
