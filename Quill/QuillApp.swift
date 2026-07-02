import SwiftUI

@main
struct QuillApp: App {
    @StateObject private var store: SketchStore
    @StateObject private var connectivity: ConnectivityManager

    init() {
        let store = SketchStore()
        _store = StateObject(wrappedValue: store)
        _connectivity = StateObject(wrappedValue: ConnectivityManager(store: store))
    }

    var body: some Scene {
        WindowGroup {
            SketchListView()
                .environmentObject(store)
                .environmentObject(connectivity)
        }
    }
}
