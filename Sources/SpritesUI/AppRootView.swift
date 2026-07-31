import SwiftUI
import SpritesCore

#if os(iOS)
public struct AppRootView: View {
    @Bindable var session: Session

    public init(session: Session) {
        self.session = session
    }

    public var body: some View {
        if let platform = session.platform {
            // State resets when the branch leaves the hierarchy on logout,
            // so a re-login always gets a fresh list model.
            SpriteListView(session: session, platform: platform)
        } else {
            LoginView(session: session)
        }
    }
}
#endif
