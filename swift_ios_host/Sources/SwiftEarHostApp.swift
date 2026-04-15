import SwiftUI
import Ear

@main
struct SwiftEarHostApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                EarHomeView()
            }
        }
    }
}
