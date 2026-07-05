//
//  Theme.swift
//  InternationalDraughts
//
//  App palette ported from the web version's CSS variables (light/dark).
//

import UIKit

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xff) / 255,
            green: CGFloat((rgb >> 8) & 0xff) / 255,
            blue: CGFloat(rgb & 0xff) / 255,
            alpha: alpha
        )
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    // --bg / --text / --text-h / --border
    static let appBackground = dynamic(light: .white, dark: UIColor(rgb: 0x16171d))
    static let appText = dynamic(light: UIColor(rgb: 0x6b6375), dark: UIColor(rgb: 0x9ca3af))
    static let appHeading = dynamic(light: UIColor(rgb: 0x08060d), dark: UIColor(rgb: 0xf3f4f6))
    static let appBorder = dynamic(light: UIColor(rgb: 0xe5e4e7), dark: UIColor(rgb: 0x2e303a))

    // --accent / --accent-bg / --accent-border
    static let accent = dynamic(light: UIColor(rgb: 0xaa3bff), dark: UIColor(rgb: 0xc084fc))
    static let accentBackground = dynamic(
        light: UIColor(rgb: 0xaa3bff, alpha: 0.1),
        dark: UIColor(rgb: 0xc084fc, alpha: 0.15)
    )
    static let accentBorder = dynamic(
        light: UIColor(rgb: 0xaa3bff, alpha: 0.5),
        dark: UIColor(rgb: 0xc084fc, alpha: 0.5)
    )
}
