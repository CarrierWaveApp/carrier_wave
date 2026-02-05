import SwiftUI
import UniformTypeIdentifiers

struct ShareableImage: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.uiImage.pngData() ?? Data() }
    }

    let uiImage: UIImage
}
