import Foundation
import UniformTypeIdentifiers

/// Coarse file categories used for the basket's summary capsule ("1 Image", "3 Files").
nonisolated enum ItemKind: Hashable, Sendable {
    case image, video, audio, pdf, archive, diskImage, folder, application, document, other

    init(contentType: UTType?, isDirectory: Bool) {
        guard let type = contentType else {
            self = isDirectory ? .folder : .other
            return
        }
        if type.conforms(to: .application) || type.conforms(to: .applicationBundle) {
            self = .application
        } else if isDirectory {
            self = .folder
        } else if type.conforms(to: .pdf) {
            self = .pdf
        } else if type.conforms(to: .image) {
            self = .image
        } else if type.conforms(to: .movie) || type.conforms(to: .video) {
            self = .video
        } else if type.conforms(to: .audio) {
            self = .audio
        } else if type.conforms(to: .diskImage) {
            self = .diskImage
        } else if type.conforms(to: .archive) {
            self = .archive
        } else if type.conforms(to: .text) || type.conforms(to: .presentation)
                    || type.conforms(to: .spreadsheet) || type.conforms(to: .compositeContent) {
            self = .document
        } else {
            self = .other
        }
    }

    func noun(count: Int) -> String {
        let one = count == 1
        switch self {
        case .image: return one ? "Image" : "Images"
        case .video: return one ? "Video" : "Videos"
        case .audio: return one ? "Audio File" : "Audio Files"
        case .pdf: return one ? "PDF" : "PDFs"
        case .archive: return one ? "Archive" : "Archives"
        case .diskImage: return one ? "Disk Image" : "Disk Images"
        case .folder: return one ? "Folder" : "Folders"
        case .application: return one ? "App" : "Apps"
        case .document: return one ? "Document" : "Documents"
        case .other: return one ? "File" : "Files"
        }
    }

    /// "1 Image", "2 PDFs", "5 Files" for a mixed set.
    static func summary(for items: [BasketItem]) -> String {
        let kinds = Set(items.map(\.kind))
        let kind = kinds.count == 1 ? kinds.first ?? .other : .other
        return "\(items.count) \(kind.noun(count: items.count))"
    }
}
