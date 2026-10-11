import SniffanKit
import SwiftUI

@main
struct SniffanApp: App {
    @State private var controller = FanController()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
        }
    }
}
