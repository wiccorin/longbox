import SwiftUI

@main
struct LongboxApp: App {
    @StateObject private var store = LibraryStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onOpenURL { url in
                    // A file tapped inside the Longbox folder is handled by the folder scan.
                    if Storage.canonicalPath(url).hasPrefix(Storage.canonicalPath(Storage.dropFolder)) {
                        store.scanDropFolder()
                    } else {
                        store.importFiles([url])
                    }
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                store.scanDropFolder()
            }
        }
    }
}
