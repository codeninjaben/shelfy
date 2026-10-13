// Renders the disk image background page to background.png (680 × 420) and background@2x.png.
//
//   swift scripts/make-dmg-background.swift packaging/dmg/background.html packaging/dmg
//
// WebKit draws the page exactly as Safari would. The fonts load from Google Fonts, so this needs
// a network connection; dmgbuild combines the two PNGs into a Retina TIFF when it builds the image.
import AppKit
import WebKit

let canvas = CGSize(width: 680, height: 420)
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: swift scripts/make-dmg-background.swift <page.html> <output-directory>\n".utf8))
    exit(2)
}
let page = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-dmg-background: \(message)\n".utf8))
    exit(1)
}

/// Draws the snapshot into a bitmap of exactly `scale` pixels per point and writes it as PNG.
func write(_ image: NSImage, scale: Int, named name: String) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width) * scale,
                               pixelsHigh: Int(canvas.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: CGRect(origin: .zero, size: canvas), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let url = outputDirectory.appendingPathComponent(name)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
    print(url.path)
}

final class Renderer: NSObject, WKNavigationDelegate {
    let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: canvas),
                          styleMask: .borderless, backing: .buffered, defer: false)
    let webView = WKWebView(frame: CGRect(origin: .zero, size: canvas))

    func start() {
        window.contentView = webView
        window.orderFrontRegardless()
        webView.navigationDelegate = self
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.callAsyncJavaScript("await document.fonts.ready; return document.fonts.size", arguments: [:], in: nil,
                                    in: .page) { _ in
            // Give the last layout a moment to paint before capturing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.capture() }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("could not load \(page.path): \(error.localizedDescription)")
    }

    func capture() {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(origin: .zero, size: canvas)
        // Ask for 2× pixels whatever the current display's scale.
        configuration.snapshotWidth = NSNumber(value: Double(canvas.width) * 2 / Double(window.backingScaleFactor))
        webView.takeSnapshot(with: configuration) { image, error in
            guard let image else { fail("snapshot failed: \(error?.localizedDescription ?? "unknown error")") }
            do {
                try write(image, scale: 1, named: "background.png")
                try write(image, scale: 2, named: "background@2x.png")
                exit(0)
            } catch {
                fail("could not write the images: \(error.localizedDescription)")
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = Renderer()
renderer.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { fail("timed out waiting for the page to render") }
app.run()
