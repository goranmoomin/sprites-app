import SwiftUI
import SpritesCore

#if os(iOS)
public struct AppRootView: View {
    @Bindable var session: Session

    public init(session: Session) {
        self.session = session
    }

    public var body: some View {
        if session.isLoggedIn {
            SpriteListPlaceholderView()
        } else {
            LoginView(session: session)
        }
    }
}

// Replaced by the real sprite list in ticket 02.
struct SpriteListPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No sprites yet",
                systemImage: "cube",
                description: Text("Create a sprite to get started.")
            )
            .navigationTitle("Sprites")
        }
    }
}
#endif
