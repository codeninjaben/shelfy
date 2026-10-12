import AppKit
import Quartz

/// Drives the shared Quick Look panel for whichever basket asked for it.
///
/// Quick Look finds its controller through the responder chain, so the edge panel and the
/// popover's view controller forward `acceptsPreviewPanelControl` and friends here.
@MainActor
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var items: [BasketItem] = []
    private weak var source: BasketViewModel?
    private var isControlling = false

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    func toggle(items: [BasketItem], from source: BasketViewModel) {
        if isVisible {
            close()
            return
        }
        self.items = items
        self.source = source
        source.host?.basketQuickLookDidChange(visible: true)
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.makeKeyAndOrderFront(nil)
        if isControlling {
            panel.reloadData()
            panel.currentPreviewItemIndex = 0
        }
    }

    func close() {
        guard isVisible else { return }
        QLPreviewPanel.shared().orderOut(nil)
        finish()
    }

    // MARK: Responder-chain hooks

    func beginControl(_ panel: QLPreviewPanel) {
        isControlling = true
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
    }

    func endControl(_ panel: QLPreviewPanel) {
        isControlling = false
        panel.dataSource = nil
        panel.delegate = nil
        finish()
    }

    private func finish() {
        let source = self.source
        self.source = nil
        source?.host?.basketQuickLookDidChange(visible: false)
    }

    // MARK: QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        items.indices.contains(index) ? items[index].url as NSURL : nil
    }

    // MARK: QLPreviewPanelDelegate

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        guard let view = sourceView(for: item), let window = view.window else { return .zero }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }

    func previewPanel(_ panel: QLPreviewPanel!, transitionImageFor item: (any QLPreviewItem)!,
                      contentRect: UnsafeMutablePointer<NSRect>!) -> Any! {
        guard let match = basketItem(for: item) else { return nil }
        return ThumbnailProvider.shared.bestAvailableImage(for: match).image
    }

    func windowWillClose(_ notification: Notification) {
        finish()
    }

    private func basketItem(for previewItem: (any QLPreviewItem)?) -> BasketItem? {
        guard let url = previewItem?.previewItemURL else { return nil }
        return items.first { $0.url == url }
    }

    private func sourceView(for previewItem: (any QLPreviewItem)?) -> NSView? {
        guard let item = basketItem(for: previewItem) else { return nil }
        return source?.sourceView(for: item.id)
    }
}
