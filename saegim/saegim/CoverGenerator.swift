//
//  CoverGenerator.swift
//  saegim
//
//  Soft gradient cover generator - light, vibrant aesthetic
//  Consistent top-light to bottom-dark gradient with gentle color transitions

import AppKit
import CoreGraphics

struct CoverGenerator {
    static let shared = CoverGenerator()

    private let size: CGFloat = 512

    // Lightness constraints: 55-85% range, brighter aesthetic
    private let minBrightness: CGFloat = 0.55
    private let maxBrightness: CGFloat = 0.85

    // Saturation constraints: muted but not gray
    private let minSaturation: CGFloat = 0.40
    private let maxSaturation: CGFloat = 0.65

    func generate(for name: String) -> NSImage {
        let seed = hash(name)

        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        // Draw consistent gradient background (top-light to bottom-dark)
        drawGradientBackground(seed: seed)

        // Draw 2-3 soft blobs (all in light range)
        let blobCount = 2 + Int(seededRandom(seed, offset: 100) * 1.5)
        let hueShift = 0.03 + seededRandom(seed, offset: 101) * 0.05

        for i in 0..<blobCount {
            let shiftAmount = hueShift * Double(i) / Double(blobCount)
            drawSoftBlob(seed: seed, index: i, hueShift: shiftAmount)
        }

        // Subtle highlight bloom in upper area
        drawHighlightBloom(seed: seed)

        // Very subtle vignette (5-8% max)
        drawVignette(seed: seed)

        image.unlockFocus()

        // Apply blur, then noise
        var result = applyBlur(to: image, radius: 30)
        result = applyNoise(to: result, seed: seed)

        return result
    }

    // MARK: - Gradient Background

    private func drawGradientBackground(seed: UInt64) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Pick base color from palette
        let baseRGB = pickPaletteColor(seed: seed)
        let baseHSB = colorToHSB(baseRGB)

        // Top color: lighter version (75-85% brightness)
        let topBrightness = 0.75 + seededRandom(seed, offset: 52) * 0.10
        let topSaturation = max(minSaturation, min(maxSaturation, baseHSB.s * (0.9 + seededRandom(seed, offset: 53) * 0.2)))
        let topColor = NSColor(hue: baseHSB.h, saturation: topSaturation, brightness: topBrightness, alpha: 1.0)

        // Bottom color: medium version (55-65%), slight hue shift
        let bottomHue = (baseHSB.h + 0.02 + seededRandom(seed, offset: 54) * 0.03).truncatingRemainder(dividingBy: 1.0)
        let bottomBrightness = 0.55 + seededRandom(seed, offset: 55) * 0.10
        let bottomSaturation = max(minSaturation, min(maxSaturation, baseHSB.s * (0.9 + seededRandom(seed, offset: 56) * 0.2)))
        let bottomColor = NSColor(hue: bottomHue, saturation: bottomSaturation, brightness: bottomBrightness, alpha: 1.0)

        let gradientColors = [topColor.cgColor, bottomColor.cgColor]
        let locations: [CGFloat] = [0.0, 1.0]

        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: gradientColors as CFArray,
                                      locations: locations) {
            // Draw top to bottom gradient
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: size / 2, y: size),  // Top
                end: CGPoint(x: size / 2, y: 0),        // Bottom
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
    }

    // MARK: - Color Palette

    /// Curated palette of 24 distinct, well-chosen colors
    private static let palette: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [
        // Blues
        (0x4A / 255.0, 0x90 / 255.0, 0xA4 / 255.0),  // muted blue
        (0x6B / 255.0, 0x8E / 255.0, 0x9B / 255.0),  // steel blue
        (0x5D / 255.0, 0x7F / 255.0, 0xA3 / 255.0),  // denim
        (0x7D / 255.0, 0xA0 / 255.0, 0xA6 / 255.0),  // teal

        // Purples & Mauves
        (0x7B / 255.0, 0x68 / 255.0, 0xA6 / 255.0),  // soft purple
        (0x9B / 255.0, 0x7B / 255.0, 0x9B / 255.0),  // mauve
        (0x8E / 255.0, 0x7C / 255.0, 0xA5 / 255.0),  // lavender
        (0xA4 / 255.0, 0x8B / 255.0, 0xB0 / 255.0),  // wisteria

        // Greens
        (0x5B / 255.0, 0xA0 / 255.0, 0x8C / 255.0),  // sage
        (0x8F / 255.0, 0xA6 / 255.0, 0x72 / 255.0),  // olive
        (0x8B / 255.0, 0x9B / 255.0, 0x7A / 255.0),  // moss
        (0x6B / 255.0, 0x9E / 255.0, 0x78 / 255.0),  // eucalyptus

        // Warm Tones
        (0xC4 / 255.0, 0x78 / 255.0, 0x6E / 255.0),  // dusty coral
        (0xD4 / 255.0, 0xA5 / 255.0, 0x74 / 255.0),  // warm sand
        (0xB0 / 255.0, 0x8D / 255.0, 0x7B / 255.0),  // terracotta
        (0xC9 / 255.0, 0x9A / 255.0, 0x6B / 255.0),  // caramel

        // Pinks & Roses
        (0xA6 / 255.0, 0x7B / 255.0, 0x8B / 255.0),  // rose
        (0xC4 / 255.0, 0x8B / 255.0, 0x9F / 255.0),  // blush
        (0xB5 / 255.0, 0x7E / 255.0, 0x8E / 255.0),  // dusty pink
        (0xD4 / 255.0, 0x9B / 255.0, 0xA6 / 255.0),  // soft peach

        // Earth & Neutrals
        (0xA0 / 255.0, 0x8C / 255.0, 0x7A / 255.0),  // taupe
        (0x8B / 255.0, 0x7D / 255.0, 0x6B / 255.0),  // mushroom
        (0x9E / 255.0, 0x8B / 255.0, 0x8B / 255.0),  // dusty rose gray
        (0x7A / 255.0, 0x8B / 255.0, 0x8B / 255.0),  // slate
    ]

    private func pickPaletteColor(seed: UInt64) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        // Use modulo for even distribution across palette
        let index = Int(seed % UInt64(Self.palette.count))
        return Self.palette[index]
    }

    private func colorToHSB(_ rgb: (r: CGFloat, g: CGFloat, b: CGFloat)) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        let color = NSColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1.0)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s, b)
    }

    // MARK: - Hashing

    private func hash(_ string: String) -> UInt64 {
        // FNV-1a hash for better distribution
        var hash: UInt64 = 14695981039346656037  // FNV offset basis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211  // FNV prime
        }
        // Additional mixing for better distribution
        hash ^= hash >> 33
        hash = hash &* 0xff51afd7ed558ccd
        hash ^= hash >> 33
        return hash
    }

    private func seededRandom(_ seed: UInt64, offset: Int = 0) -> Double {
        let offsetBits = UInt64(bitPattern: Int64(offset) &* 2654435761)
        var s = seed &+ offsetBits
        s = s ^ (s >> 21)
        s = s ^ (s << 35)
        s = s ^ (s >> 4)
        s = s &* 2685821657736338717
        return Double(s % 10000) / 10000.0
    }

    // MARK: - Blob Drawing

    private func drawSoftBlob(seed: UInt64, index: Int, hueShift: Double) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let baseOffset = index * 100

        // Blob position - can extend beyond edges
        let centerX = seededRandom(seed, offset: baseOffset + 10) * Double(size) * 1.2 - Double(size) * 0.1
        let centerY = seededRandom(seed, offset: baseOffset + 11) * Double(size) * 1.2 - Double(size) * 0.1

        // Large blob size
        let radiusX = Double(size) * (0.4 + seededRandom(seed, offset: baseOffset + 12) * 0.4)
        let radiusY = Double(size) * (0.4 + seededRandom(seed, offset: baseOffset + 13) * 0.4)

        // Rotation
        let rotation = seededRandom(seed, offset: baseOffset + 14) * .pi * 2

        // Pick blob color from palette (offset by index for variety within same card)
        let blobSeed = seed &+ UInt64(index * 3)  // Offset to get different palette color per blob
        let baseRGB = pickPaletteColor(seed: blobSeed)
        let baseHSB = colorToHSB(baseRGB)

        // Apply hue shift and keep in light range (65-85% brightness)
        let blobHue = (baseHSB.h + CGFloat(hueShift) + seededRandom(seed, offset: baseOffset + 15) * 0.08).truncatingRemainder(dividingBy: 1.0)
        let blobBrightness = 0.65 + seededRandom(seed, offset: baseOffset + 16) * 0.20  // 65-85%
        let blobSaturation = max(minSaturation, min(maxSaturation, baseHSB.s * (0.9 + seededRandom(seed, offset: baseOffset + 17) * 0.2)))

        let color = NSColor(hue: blobHue, saturation: blobSaturation, brightness: blobBrightness, alpha: 0.4)

        // Create organic blob path
        let path = createBlobPath(
            centerX: centerX,
            centerY: centerY,
            radiusX: radiusX,
            radiusY: radiusY,
            rotation: rotation,
            seed: seed,
            index: index
        )

        // Draw with radial gradient for soft edges
        context.saveGState()
        context.addPath(path)
        context.clip()

        // Radial gradient - same hue, fades to transparent
        let edgeColor = NSColor(hue: blobHue, saturation: blobSaturation * 0.8, brightness: blobBrightness, alpha: 0.0)
        let gradientColors = [color.cgColor, edgeColor.cgColor]
        let locations: [CGFloat] = [0.0, 1.0]

        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: gradientColors as CFArray,
                                      locations: locations) {
            let maxRadius = max(radiusX, radiusY) * 1.2
            context.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: centerX, y: centerY),
                startRadius: 0,
                endCenter: CGPoint(x: centerX, y: centerY),
                endRadius: maxRadius,
                options: []
            )
        }

        context.restoreGState()
    }

    private func createBlobPath(centerX: Double, centerY: Double, radiusX: Double, radiusY: Double, rotation: Double, seed: UInt64, index: Int) -> CGPath {
        let path = CGMutablePath()
        let segments = 64
        let baseOffset = index * 100 + 200

        for i in 0...segments {
            let angle = (Double(i) / Double(segments)) * .pi * 2

            // Add organic wobble
            let wobble1 = sin(angle * 2) * seededRandom(seed, offset: baseOffset + 20) * 0.15
            let wobble2 = sin(angle * 3) * seededRandom(seed, offset: baseOffset + 21) * 0.1
            let wobble3 = cos(angle * 2) * seededRandom(seed, offset: baseOffset + 22) * 0.12

            let r = 1.0 + wobble1 + wobble2 + wobble3

            // Calculate point with rotation
            let baseX = cos(angle) * radiusX * r
            let baseY = sin(angle) * radiusY * r

            let rotatedX = baseX * cos(rotation) - baseY * sin(rotation)
            let rotatedY = baseX * sin(rotation) + baseY * cos(rotation)

            let x = centerX + rotatedX
            let y = centerY + rotatedY

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        path.closeSubpath()
        return path
    }

    // MARK: - Highlight Bloom

    private func drawHighlightBloom(seed: UInt64) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Position in upper third, random horizontal
        let centerX = Double(size) * (0.2 + seededRandom(seed, offset: 500) * 0.6)
        let centerY = Double(size) * (0.65 + seededRandom(seed, offset: 501) * 0.25)  // Upper third

        // Radius ~40% of size
        let radius = Double(size) * (0.35 + seededRandom(seed, offset: 502) * 0.1)

        // White at 8-12% opacity
        let opacity = 0.08 + seededRandom(seed, offset: 503) * 0.04

        let gradientColors = [
            NSColor(white: 1.0, alpha: opacity).cgColor,
            NSColor(white: 1.0, alpha: 0).cgColor
        ]
        let locations: [CGFloat] = [0.0, 1.0]

        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: gradientColors as CFArray,
                                      locations: locations) {
            context.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: centerX, y: centerY),
                startRadius: 0,
                endCenter: CGPoint(x: centerX, y: centerY),
                endRadius: radius,
                options: []
            )
        }
    }

    // MARK: - Vignette

    private func drawVignette(seed: UInt64) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: size / 2, y: size / 2)
        let innerRadius = Double(size) * 0.5
        let outerRadius = Double(size) * 0.9

        // Very subtle darkening: 5-8% only
        let darkness = 0.05 + seededRandom(seed, offset: 600) * 0.03

        let gradientColors = [
            NSColor(white: 0, alpha: 0).cgColor,
            NSColor(white: 0, alpha: darkness).cgColor
        ]
        let locations: [CGFloat] = [0.0, 1.0]

        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: gradientColors as CFArray,
                                      locations: locations) {
            context.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: innerRadius,
                endCenter: center,
                endRadius: outerRadius,
                options: [.drawsAfterEndLocation]
            )
        }
    }

    // MARK: - Effects

    private func applyBlur(to image: NSImage, radius: CGFloat) -> NSImage {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let ciImage = CIImage(bitmapImageRep: bitmap) else {
            return image
        }

        let filter = CIFilter(name: "CIGaussianBlur")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)

        guard let output = filter.outputImage else { return image }

        // Crop to original size (blur extends edges)
        let cropped = output.cropped(to: CGRect(x: 0, y: 0, width: size, height: size))

        let rep = NSCIImageRep(ciImage: cropped)
        let result = NSImage(size: NSSize(width: size, height: size))
        result.addRepresentation(rep)

        return result
    }

    private func applyNoise(to image: NSImage, seed: UInt64) -> NSImage {
        let result = NSImage(size: NSSize(width: size, height: size))
        result.lockFocus()

        // Draw original image
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))

        // Generate noise overlay
        guard let context = NSGraphicsContext.current?.cgContext else {
            result.unlockFocus()
            return image
        }

        // 1-2% noise intensity
        let noiseIntensity = 0.01 + seededRandom(seed, offset: 700) * 0.01

        // Draw noise pixels
        let step = 2  // Sample every 2 pixels for performance
        for y in stride(from: 0, to: Int(size), by: step) {
            for x in stride(from: 0, to: Int(size), by: step) {
                let noise = seededRandom(seed, offset: 10000 + y * Int(size) + x)
                let gray = noise < 0.5 ? 0.0 : 1.0
                let alpha = noiseIntensity * seededRandom(seed, offset: 20000 + y * Int(size) + x)

                context.setFillColor(NSColor(white: gray, alpha: alpha).cgColor)
                context.fill(CGRect(x: x, y: y, width: step, height: step))
            }
        }

        result.unlockFocus()
        return result
    }
}
