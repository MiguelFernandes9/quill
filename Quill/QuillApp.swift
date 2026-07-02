import SwiftUI

@main
struct QuillApp: App {
    @StateObject private var store: SketchStore
    @StateObject private var connectivity: ConnectivityManager
    @StateObject private var thumbnails: ThumbnailStore

    init() {
        let store = SketchStore()
        _store = StateObject(wrappedValue: store)
        _connectivity = StateObject(wrappedValue: ConnectivityManager(store: store))
        _thumbnails = StateObject(wrappedValue: ThumbnailStore(store: store))
    }

    var body: some Scene {
        WindowGroup {
            SketchListView()
                .environmentObject(store)
                .environmentObject(connectivity)
                .environmentObject(thumbnails)
        }
    }
}
