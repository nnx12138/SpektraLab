//  SpektraLabApp.swift — the iOS @main.
//
//  The macOS app keeps one Session for the app's lifetime and so does this:
//  `Session` is the document, the engine holds the render state, and a second
//  session would double the GPU pool for no product gain. The editor screen
//  adapts to the idiom — rails on iPad, tab sheets on iPhone — but the model
//  and the engine are exactly the ones the Mac ships.

import SwiftUI

@main
struct SpektraLabApp: App {
    /// One Session for the app's lifetime — same decision as the Mac.
    @MainActor static let session = Session()

    private var session: Session { Self.session }

    var body: some Scene {
        WindowGroup {
            EditorScreen(session: session)
                // Interface scale is a Mac affordance (menu-driven); iOS gets
                // the standard dynamic type instead, so no `.id(scale)` here.
                .preferredColorScheme(.dark)
        }
    }
}
