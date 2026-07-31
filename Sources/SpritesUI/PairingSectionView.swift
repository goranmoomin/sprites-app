import SwiftUI
import SpritesCore
import CoreImage.CIFilterBuiltins

#if os(iOS)
/// The Pairing screen: hostname, one-time code, QR, copy buttons, and the
/// T3 Code app handoff.
struct PairingSectionView: View {
    let pairing: Pairing
    let done: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section("Pair T3 Code") {
            LabeledContent("Host", value: pairing.host)
            LabeledContent("Code") {
                Text(pairing.code)
                    .font(.body.monospaced())
            }
            if let expires = pairing.expiresAt {
                LabeledContent("Expires", value: expires.formatted(date: .omitted, time: .shortened))
            }
            if let qr = qrImage {
                HStack {
                    Spacer()
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                    Spacer()
                }
            }
            Button {
                UIPasteboard.general.string = pairing.code
            } label: {
                Label("Copy code", systemImage: "doc.on.doc")
            }
            if let url = pairing.pairURL {
                Button {
                    UIPasteboard.general.string = url.absoluteString
                } label: {
                    Label("Copy pairing URL", systemImage: "link")
                }
                Button {
                    openURL(url)
                } label: {
                    Label("Open T3 Code", systemImage: "arrow.up.forward.app")
                }
            }
            Button("Done", action: done)
        }
    }

    private var qrImage: UIImage? {
        guard let payload = pairing.pairURL?.absoluteString ?? (pairing.code.isEmpty ? nil : pairing.code)
        else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
#endif
