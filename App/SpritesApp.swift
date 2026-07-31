import SwiftUI
import SpritesCore
import SpritesUI

@main
struct SpritesApp: App {
    @State private var session: Session

    init() {
        let session = Session(
            tokenStore: KeychainTokenStore(),
            platformFactory: { HTTPSpritesPlatform(token: $0) }
        )
        session.restore()
        _session = State(initialValue: session)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(session: session)
        }
    }
}
