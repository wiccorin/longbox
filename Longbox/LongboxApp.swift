import SwiftUI

@main
struct LongboxApp: App {
    @StateObject private var store = LibraryStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onOpenURL { url in
                    store.importFiles([url])
                }
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.94, green: 0.77, blue: 0.10)
    static let background = Color(red: 0.086, green: 0.078, blue: 0.133)
    static let card = Color(red: 0.16, green: 0.145, blue: 0.24)
}
