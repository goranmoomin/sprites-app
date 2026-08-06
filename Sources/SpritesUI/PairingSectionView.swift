import SwiftUI
import SpritesCore
import CoreImage.CIFilterBuiltins

#if os(iOS)
/// The Pairing screen: copyable host and one-time code, QR for pairing
/// other devices, the T3 Code app handoff, and in-place re-issue.
struct PairingSectionView: View {
    let pairing: T3Pairing
    var requestNewCode: (() -> Void)?
    let done: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var handoffFailed = false
    @State private var copyCount = 0

    var body: some View {
        Section {
            CopyableValueRow(label: "Host", value: pairing.host)
            CopyableValueRow(label: "Code", value: pairing.code, monospaced: true)
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
                .accessibilityLabel("Pairing QR code")
                .contextMenu {
                    if let url = pairing.pairURL {
                        Button("Copy pairing URL", systemImage: "link") {
                            copy(url.absoluteString)
                        }
                    }
                    Button("Copy code", systemImage: "doc.on.doc") {
                        copy(pairing.code)
                    }
                }
            }
            Button {
                openInT3Code()
            } label: {
                Label("Open T3 Code", systemImage: "arrow.up.forward.app")
            }
            if handoffFailed {
                Text("T3 Code doesn't seem to be installed. The pairing link is copied; paste it into T3 Code once installed.")
                    .foregroundStyle(.secondary)
            }
            if let requestNewCode {
                Button {
                    requestNewCode()
                } label: {
                    Label("New code", systemImage: "arrow.clockwise")
                }
            }
            Button("Done", action: done)
        } header: {
            Text("Pair T3 Code")
        } footer: {
            Text("Open T3 Code copies the pairing link; paste it into the Host field of the Add Environment screen. The QR pairs another device.")
        }
        .sensoryFeedback(.success, trigger: copyCount)
    }

    private func copy(_ string: String) {
        UIPasteboard.general.string = string
        copyCount += 1
    }

    /// Never a browser: the /pair web page redeems the single-use token on
    /// sight. The handoff is copy the link, open the app's Add Environment
    /// screen, paste.
    private func openInT3Code() {
        copy(pairing.pairURL?.absoluteString ?? pairing.code)
        openURL(T3CodeIntegration.addEnvironmentURL) { accepted in
            handoffFailed = !accepted
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
