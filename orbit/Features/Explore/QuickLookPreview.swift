import SwiftUI
import QuickLookUI

struct QuickLookPreview: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let preview = QLPreviewView(frame: .zero, style: .normal)
        preview?.previewItem = fileURL as NSURL
        return preview ?? QLPreviewView()
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = fileURL as NSURL
    }
}
