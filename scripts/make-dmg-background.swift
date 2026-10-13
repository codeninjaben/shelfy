// Renders the disk image background page to background.png and background@2x.png.
//
//   swift scripts/make-dmg-background.swift packaging/dmg/background.html packaging/dmg
//
// The images take the size of the page's first element (680 × 460 points for Shelfy's window).
// WebKit draws the page exactly as Safari would. The fonts load from Google Fonts, so this needs
// a network connection; dmgbuild combines the two PNGs into a Retina TIFF when it builds the image.
import AppKit
import WebKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: swift scripts/make-dmg-background.swift <page.html> <output-directory>\n".utf8))
    exit(2)
}
let page = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)
let viewport = CGSize(width: 1200, height: 1000)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-dmg-background: \(message)\n".utf8))
    exit(1)
}

/// Draws the snapshot into a bitmap of exactly `scale` pixels per point and writes it as PNG.
func write(_ image: NSImage, size: CGSize, scale: Int, named name: String) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
                               pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let url = outputDirectory.appendingPathComponent(name)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
    print("\(url.path) (\(Int(size.width) * scale) × \(Int(size.height) * scale))")
}

final class Renderer: NSObject, WKNavigationDelegate {
    let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: viewport),
                          styleMask: .borderless, backing: .buffered, defer: false)
    let webView = WKWebView(frame: CGRect(origin: .zero, size: viewport))

    func start() {
        window.contentView = webView
        window.orderFrontRegardless()
        webView.navigationDelegate = self
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let measure = """
            await document.fonts.ready;
            const box = document.body.firstElementChild.getBoundingClientRect();
            return [box.width, box.height];
            """
        webView.callAsyncJavaScript(measure, arguments: [:], in: nil, in: .page) { result in
            guard case .success(let value) = result, let box = value as? [Double], box.count == 2,
                  box[0] >= 1, box[1] >= 1 else { fail("could not measure the page: \(result)") }
            let size = CGSize(width: box[0].rounded(), height: box[1].rounded())
            // Give the last layout a moment to paint before capturing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.capture(size) }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("could not load \(page.path): \(error.localizedDescription)")
    }

    func capture(_ size: CGSize) {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(origin: .zero, size: size)
        // Ask for 2× pixels whatever the current display's scale.
        configuration.snapshotWidth = NSNumber(value: Double(size.width) * 2 / Double(window.backingScaleFactor))
        webView.takeSnapshot(with: configuration) { image, error in
            guard let image else { fail("snapshot failed: \(error?.localizedDescription ?? "unknown error")") }
            do {
                try write(image, size: size, scale: 1, named: "background.png")
                try write(image, size: size, scale: 2, named: "background@2x.png")
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
