// Renders option B (GF monogram + check) as outlined paths.
// usage: swift render.swift <font.ttf> <outdir>
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let fontURL = URL(fileURLWithPath: args[1]) as CFURL
let outDir = URL(fileURLWithPath: args[2])

// Manrope variable font at weight 800, size 46 in a 100-unit square
let descs = CTFontManagerCreateFontDescriptorsFromURL(fontURL) as! [CTFontDescriptor]
let wght = 0x7767_6874 // 'wght'
let desc = CTFontDescriptorCreateCopyWithAttributes(
    descs[0], [kCTFontVariationAttribute: [wght: 800]] as CFDictionary)
let font = CTFontCreateWithFontDescriptor(desc, 46, nil)

// Glyph outlines in y-up font space, letter-spacing -2
let chars = Array("GF".utf16)
var glyphs = [CGGlyph](repeating: 0, count: chars.count)
CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count)
var advances = [CGSize](repeating: .zero, count: glyphs.count)
CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
let text = CGMutablePath()
var x: CGFloat = 0
for (g, adv) in zip(glyphs, advances) {
    if let p = CTFontCreatePathForGlyph(font, g, nil) {
        text.addPath(p, transform: CGAffineTransform(translationX: x, y: 0))
    }
    x += adv.width - 2
}
// Into the 100-unit, y-down icon space: ink centred on x = 50, baseline at y = 58
let ink = text.boundingBoxOfPath
var place = CGAffineTransform(translationX: 50 - ink.midX, y: 58).scaledBy(x: 1, y: -1)
let letters = text.copy(using: &place)!

let check = CGMutablePath()
check.move(to: CGPoint(x: 30, y: 70))
check.addLine(to: CGPoint(x: 39, y: 77))
check.addLine(to: CGPoint(x: 71, y: 65))

struct Variant { let name: String; let bg: CGColor?; let fg: CGColor; let ac: CGColor }
func rgb(_ hex: Int) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
let variants = [
    Variant(name: "AppIcon-Light", bg: rgb(0x0000FF), fg: rgb(0xFFFFFF), ac: rgb(0x63A6FF)),
    Variant(name: "AppIcon-Dark", bg: rgb(0x000000), fg: rgb(0x4390F9), ac: rgb(0xFFFFFF)),
    Variant(name: "AppIcon-Tinted", bg: rgb(0x000000), fg: rgb(0xE6E6E6), ac: rgb(0x8C8C8C)),
]

let px = 1024
for v in variants {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // y-down, 100 units across
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: CGFloat(px) / 100, y: -CGFloat(px) / 100)
    ctx.setFillColor(v.bg!)
    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    ctx.addPath(letters)
    ctx.setFillColor(v.fg)
    ctx.fillPath()
    ctx.addPath(check)
    ctx.setStrokeColor(v.ac)
    ctx.setLineWidth(5)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    let url = outDir.appendingPathComponent(v.name + ".png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

// SVG master of the light icon, letters as paths
func svgPath(_ p: CGPath) -> String {
    var d = ""
    let f = { (v: CGFloat) in String(format: "%.2f", v) }
    p.applyWithBlock { e in
        let pts = e.pointee.points
        switch e.pointee.type {
        case .moveToPoint: d += "M\(f(pts[0].x)) \(f(pts[0].y))"
        case .addLineToPoint: d += "L\(f(pts[0].x)) \(f(pts[0].y))"
        case .addQuadCurveToPoint: d += "Q\(f(pts[0].x)) \(f(pts[0].y)) \(f(pts[1].x)) \(f(pts[1].y))"
        case .addCurveToPoint:
            d += "C\(f(pts[0].x)) \(f(pts[0].y)) \(f(pts[1].x)) \(f(pts[1].y)) \(f(pts[2].x)) \(f(pts[2].y))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
<rect width="100" height="100" fill="#0000FF"/>
<path fill="#FFFFFF" d="\(svgPath(letters))"/>
<path d="M30 70 L39 77 L71 65" fill="none" stroke="#63A6FF" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
</svg>

"""
try! svg.write(to: outDir.appendingPathComponent("AppIcon.svg"), atomically: true, encoding: .utf8)
print("letters ink:", letters.boundingBoxOfPath)
