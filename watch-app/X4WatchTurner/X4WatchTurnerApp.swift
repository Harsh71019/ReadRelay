import SwiftUI

@main
struct X4WatchTurnerApp: App {
    @StateObject private var bluetooth = BluetoothController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetooth)
        }
    }
}
