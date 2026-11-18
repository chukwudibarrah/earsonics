// Views/Shared/QRCodeImage.swift
import CoreImage.CIFilterBuiltins
import SwiftUI
import EarsonicsCore

/// Links the app shows as QR codes (an Apple TV can't open them itself).
enum AppLinks {
    /// The App Store "write a review" page for earsonics.
    static let writeReview = URL(string: "https://apps.apple.com/app/id6766037499?action=write-review")!
}

/// A QR code for `text`, drawn crisp at any size (black on white, with the
/// quiet border scanners need).
struct QRCodeImage: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(uiImage: image)
                .interpolation(.none)        // keep the modules sharp when scaled up
                .resizable()
                .scaledToFit()
                .padding(24)
                .background(Color.white)
        } else {
            Text(text).font(.caption)        // fall back to the link itself
        }
    }

    private static func render(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    QRCodeImage(text: AppLinks.writeReview.absoluteString)
        .frame(width: 400, height: 400)
}
