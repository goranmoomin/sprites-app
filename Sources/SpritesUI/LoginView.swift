import SwiftUI
import SpritesCore

#if os(iOS)
import SafariServices
import UIKit

/// Where Sprite tokens are created. Opened in an in-app browser.
private let tokenPageURL = URL(string: "https://fly.io/dashboard/personal/tokens")!

public struct LoginView: View {
    @Bindable var session: Session

    @State private var manualToken = ""
    @State private var showingBrowser = false
    @State private var returnedFromBrowser = false
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
                        showingBrowser = true
                    } label: {
                        Label("Create Sprite token", systemImage: "safari")
                    }
                } footer: {
                    Text("Log in to Fly, create a Sprite token, and copy it.")
                }

                if returnedFromBrowser && UIPasteboard.general.hasStrings {
                    Section {
                        Button {
                            // Reading triggers the system paste prompt.
                            guard let copied = UIPasteboard.general.string else { return }
                            let token = copied.trimmingCharacters(in: .whitespacesAndNewlines)
                            // A token is one long opaque word; anything else
                            // is probably not what the user meant to paste.
                            guard token.count >= 20, !token.contains(where: \.isWhitespace) else {
                                errorMessage = "The clipboard contents don't look like a Sprite token."
                                return
                            }
                            logIn(with: token)
                        } label: {
                            Label("Use copied token", systemImage: "doc.on.clipboard")
                        }
                    }
                }

                Section("Paste token") {
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
            .sheet(isPresented: $showingBrowser, onDismiss: { returnedFromBrowser = true }) {
                SafariView(url: tokenPageURL)
                    .ignoresSafeArea()
            }
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
