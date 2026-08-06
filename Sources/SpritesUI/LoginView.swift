import SwiftUI
import SpritesCore

#if os(iOS)
import SafariServices
import UIKit

/// Where Sprite tokens live. Opened in an in-app browser.
private let dashboardURL = URL(string: "https://fly.io/dashboard/personal/sprites")!

public struct LoginView: View {
    @Bindable var session: Session

    @State private var manualToken = ""
    @State private var showingBrowser = false
    @State private var pasteboardCountAtPresent: Int?
    @State private var isValidating = false
    @State private var errorMessage: String?

    public init(session: Session) {
        self.session = session
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        pasteboardCountAtPresent = UIPasteboard.general.changeCount
                        showingBrowser = true
                    } label: {
                        Label("Open Fly dashboard", systemImage: "safari")
                    }
                } footer: {
                    Text("Log in to Fly and copy your Sprite token from the dashboard. It fills in below automatically.")
                }

                Section("Sprite token") {
                    SecureField("Sprite token", text: $manualToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Log in") {
                        logIn(with: manualToken)
                    }
                    .disabled(manualToken.isEmpty || isValidating)
                }

                if isValidating {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Validating token...")
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Sprites")
            .sheet(isPresented: $showingBrowser, onDismiss: autoFillFromPasteboard) {
                SafariView(url: dashboardURL)
                    .ignoresSafeArea()
            }
        }
    }

    /// Fills the token field when something was copied during the dashboard
    /// visit and it looks like a Sprite token. The read itself shows the
    /// system paste alert; nothing is submitted without the Log in tap.
    private func autoFillFromPasteboard() {
        guard let before = pasteboardCountAtPresent,
            UIPasteboard.general.changeCount != before,
            let copied = UIPasteboard.general.string
        else { return }
        let token = copied.trimmingCharacters(in: .whitespacesAndNewlines)
        if SpriteTokenFormat.matches(token) {
            manualToken = token
            errorMessage = nil
        }
    }

    private func logIn(with token: String) {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        isValidating = true
        errorMessage = nil
        Task {
            defer { isValidating = false }
            do {
                try await session.logIn(token: token)
            } catch PlatformError.unauthorized {
                errorMessage = "That token was rejected by the Sprites API. Check it and try again."
            } catch {
                errorMessage = "Could not validate the token: \(error.localizedDescription)"
            }
        }
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
