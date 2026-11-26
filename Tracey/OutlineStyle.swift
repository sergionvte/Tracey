//
//  OutlineStyle.swift
//  Tracey
//
//  How the Outline filter draws: how much detail it keeps and the color of its lines.
//

import UIKit

/// An sRGB color (components 0–1) that can be saved with a reference.
struct OutlineColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Any UIColor, converted to sRGB (wide-gamut picks are clamped)
    init(_ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let srgb = color.cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
        if let components = srgb?.components, components.count >= 3 {
            r = components[0]; g = components[1]; b = components[2]
        } else {
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
        }
        self.init(red: min(max(Double(r), 0), 1), green: min(max(Double(g), 0), 1), blue: min(max(Double(b), 0), 1))
    }

    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }

    /// #1E6BFF: reference lines can't be mistaken for graphite
    static let blue = OutlineColor(hex: 0x1E6BFF)
    static let black = OutlineColor(hex: 0x000000)
    static let red = OutlineColor(hex: 0xE53935)
    static let green = OutlineColor(hex: 0x2E9E4F)
    static let purple = OutlineColor(hex: 0x8E44EC)
    static let white = OutlineColor(hex: 0xFFFFFF)

    static let presets: [OutlineColor] = [.blue, .black, .red, .green, .purple, .white]

    /// Spoken name of a preset (nil for a custom color)
    var presetName: String? {
        switch self {
        case .blue: String(localized: "Blue")
        case .black: String(localized: "Black")
        case .red: String(localized: "Red")
        case .green: String(localized: "Green")
        case .purple: String(localized: "Purple")
        case .white: String(localized: "White")
        default: nil
        }
    }

    private static let preferredKey = "outlineColor"

    /// The last color the person picked; new references start with it
    static var preferred: OutlineColor {
        get {
            guard let data = UserDefaults.standard.data(forKey: preferredKey),
                  let color = try? JSONDecoder().decode(OutlineColor.self, from: data) else { return .blue }
            return color
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: preferredKey)
            }
        }
    }
}

/// Outline filter settings. `detail` 0 keeps only the main shapes, 1 keeps fine lines; 0.5 is
/// the look the filter always had.
struct OutlineStyle: Codable, Hashable {
    var detail: Double = 0.5
    var color: OutlineColor = .blue

    private var clampedDetail: Double { detail.isFinite ? min(max(detail, 0), 1) : 0.5 }

    /// CILineOverlay threshold: lower keeps fainter edges
    var lineThreshold: Double { Self.piecewise(clampedDetail, low: 0.45, middle: 0.2, high: 0.05) }

    /// Blur before tracing: less blur keeps texture and small details
    var blurRadius: Double { Self.piecewise(clampedDetail, low: 3.0, middle: 1.5, high: 0.5) }

    /// Linear from `low` (0) to `middle` (0.5) to `high` (1)
    private static func piecewise(_ t: Double, low: Double, middle: Double, high: Double) -> Double {
        t <= 0.5 ? low + (middle - low) * (t / 0.5) : middle + (high - middle) * ((t - 0.5) / 0.5)
    }
}
