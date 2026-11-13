import AppKit
import CoreText
let a = CommandLine.arguments
CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: a[1]) as CFURL, .process, nil)
let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func col(_ h: UInt32, _ al: CGFloat = 1) -> CGColor { CGColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: al) }
let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: col(0x000000, 0.45))
ctx.addPath(shape); ctx.setFillColor(col(0x0a5ab8)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState(); ctx.addPath(shape); ctx.clip()
let g1 = CGGradient(colorsSpace: cs, colors: [col(0x3aa6ff), col(0x0b63c9), col(0x07356f)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(g1, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
let g2 = CGGradient(colorsSpace: cs, colors: [col(0x9fd6ff, 0.55), col(0x9fd6ff, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(g2, startCenter: CGPoint(x: 512, y: 600), startRadius: 0, endCenter: CGPoint(x: 512, y: 600), endRadius: 430, options: [])
ctx.restoreGState()
ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 22, dy: 22), cornerWidth: 165, cornerHeight: 165, transform: nil))
ctx.setStrokeColor(col(0xf3cf6a, 0.75)); ctx.setLineWidth(7); ctx.strokePath()
let font = CTFontCreateWithName("GWENT-ExtraBold" as CFString, 640, nil)
var glyph: CGGlyph = 0; var ch: UniChar = 0x47
CTFontGetGlyphsForCharacters(font, &ch, &glyph, 1)
let gp = CTFontCreatePathForGlyph(font, glyph, nil)!
let bb = gp.boundingBoxOfPath
var t = CGAffineTransform(translationX: 512 - bb.midX, y: 512 - bb.midY + 6)
let path = gp.copy(using: &t)!
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 22, color: col(0x021a3a, 0.75))
ctx.addPath(path); ctx.setFillColor(col(0xe9b844)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState(); ctx.addPath(path); ctx.clip()
let g3 = CGGradient(colorsSpace: cs, colors: [col(0xfff0b0), col(0xf5c952), col(0xc98a1f)] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(g3, start: CGPoint(x: 512, y: bb.maxY + 512 - bb.midY), end: CGPoint(x: 512, y: 512 - bb.midY + bb.minY), options: [])
ctx.restoreGState()
ctx.addPath(path); ctx.setStrokeColor(col(0x6b4410, 0.6)); ctx.setLineWidth(5); ctx.strokePath()
let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
print("ikona:", a[2])
