// Renders Shelfy's icon artwork: a file card tucked into a glass pocket.
//
//   swift scripts/make-icon.swift <output-directory>
//
// Writes the layer images for the Icon Composer icon (Card.png, Pocket.png) and a flattened
// Preview.png. No SF Symbols are used; the glyph is drawn from paths.
import AppKit
import CoreGraphics

let canvas = 1024
let arguments = CommandLine.arguments
let outputDirectory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : ".", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func makeContext() -> CGContext {
    let context = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.displayP3)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Work in top-left coordinates like the design.
    context.translateBy(x: 0, y: CGFloat(canvas))
    context.scaleBy(x: 1, y: -1)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    return context
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
            components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                         CGFloat(hex & 0xFF) / 255, alpha])!
}

func write(_ context: CGContext, to name: String) throws {
    let image = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: outputDirectory.appending(path: name))
}

// MARK: Card: a document with a folded corner and a few lines of "text", tilted slightly.

func drawCard(in context: CGContext) {
    context.saveGState()
    let center = CGPoint(x: 512, y: 452)
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: -7 * .pi / 180)
    let size = CGSize(width: 340, height: 420)
    let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
    let fold: CGFloat = 92
    let radius: CGFloat = 44

    let body = CGMutablePath()
    body.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
    body.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
    body.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
    body.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
    body.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - radius, y: rect.maxY), radius: radius)
    body.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
    body.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - radius), radius: radius)
    body.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
    body.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY), radius: radius)
    body.closeSubpath()

    context.addPath(body)
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()

    // Folded corner.
    let corner = CGMutablePath()
    corner.move(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
    corner.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY + fold - 18))
    corner.addQuadCurve(to: CGPoint(x: rect.maxX - fold + 18, y: rect.minY + fold), control: CGPoint(x: rect.maxX - fold, y: rect.minY + fold))
    corner.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
    corner.closeSubpath()
    context.addPath(corner)
    context.setFillColor(color(0xD6E2F5))
    context.fillPath()

    // Lines of text.
    context.setFillColor(color(0x9DB4D8))
    let lineHeight: CGFloat = 26
    let lines: [(CGFloat, CGFloat)] = [(0.0, 0.52), (1, 0.78), (2, 0.66), (3, 0.74)]
    for (index, widthFraction) in lines {
        let y = rect.minY + 150 + index * 58
        let line = CGRect(x: rect.minX + 52, y: y, width: (size.width - 104) * widthFraction, height: lineHeight)
        context.addPath(CGPath(roundedRect: line, cornerWidth: lineHeight / 2, cornerHeight: lineHeight / 2, transform: nil))
        context.fillPath()
    }
    context.restoreGState()
}

// MARK: Pocket: the glass sleeve the card is tucked into.

let pocketRect = CGRect(x: 214, y: 548, width: 596, height: 268)

func pocketPath() -> CGPath {
    CGPath(roundedRect: pocketRect, cornerWidth: 86, cornerHeight: 86, transform: nil)
}

func drawPocket(in context: CGContext) {
    context.addPath(pocketPath())
    context.setFillColor(color(0xFFFFFF, alpha: 0.92))
    context.fillPath()
    // A soft lip along the top edge.
    let lip = CGRect(x: pocketRect.minX + 70, y: pocketRect.minY + 34, width: pocketRect.width - 140, height: 18)
    context.addPath(CGPath(roundedRect: lip, cornerWidth: 9, cornerHeight: 9, transform: nil))
    context.setFillColor(color(0x5B8CF0, alpha: 0.35))
    context.fillPath()
}

let card = makeContext()
drawCard(in: card)
try write(card, to: "Card.png")

let pocket = makeContext()
drawPocket(in: pocket)
try write(pocket, to: "Pocket.png")

// MARK: Flattened preview (and legacy fallback artwork).

let preview = makeContext()
let squircle = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 186, cornerHeight: 186, transform: nil)
preview.saveGState()
preview.addPath(squircle)
preview.clip()
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                          colors: [color(0x78B4FF), color(0x2E62F0)] as CFArray, locations: [0, 1])!
preview.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
preview.beginTransparencyLayer(auxiliaryInfo: nil)
preview.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: color(0x0B2A7A, alpha: 0.35))
preview.beginTransparencyLayer(auxiliaryInfo: nil) // shadow the card as one shape, not per line
drawCard(in: preview)
preview.endTransparencyLayer()
preview.endTransparencyLayer()
preview.setShadow(offset: .zero, blur: 0, color: nil)
preview.setAlpha(0.42)
preview.addPath(pocketPath())
preview.setFillColor(color(0xFFFFFF))
preview.fillPath()
preview.setAlpha(1)
preview.addPath(pocketPath())
preview.setStrokeColor(color(0xFFFFFF, alpha: 0.8))
preview.setLineWidth(6)
preview.strokePath()
preview.restoreGState()
try write(preview, to: "Preview.png")
print("Wrote icon artwork to \(outputDirectory.path)")
