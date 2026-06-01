import SwiftUI

@main
struct KnotLinkApp: App {
    @StateObject private var store = KnotLinkStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
