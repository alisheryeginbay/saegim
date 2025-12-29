//
//  Color+Hex.swift
//  saegim
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let length = hexSanitized.count

        switch length {
        case 6:
            self.init(
                red: Double((rgb & 0xFF0000) >> 16) / 255.0,
                green: Double((rgb & 0x00FF00) >> 8) / 255.0,
                blue: Double(rgb & 0x0000FF) / 255.0
            )
        case 8:
            self.init(
                red: Double((rgb & 0xFF000000) >> 24) / 255.0,
                green: Double((rgb & 0x00FF0000) >> 16) / 255.0,
                blue: Double((rgb & 0x0000FF00) >> 8) / 255.0,
                opacity: Double(rgb & 0x000000FF) / 255.0
            )
        default:
            return nil
        }
    }

    func toHex(includeAlpha: Bool = false) -> String? {
        #if canImport(AppKit)
        guard let components = NSColor(self).cgColor.components else {
            return nil
        }
        #else
        guard let components = UIColor(self).cgColor.components else {
            return nil
        }
        #endif

        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)

        if includeAlpha, components.count >= 4 {
            let a = Int(components[3] * 255)
            return String(format: "%02X%02X%02X%02X", r, g, b, a)
        }

        return String(format: "%02X%02X%02X", r, g, b)
    }
}
