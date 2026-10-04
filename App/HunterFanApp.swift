import HunterFanKit
import SwiftUI

@main
struct HunterFanApp: App {
    @State private var controller = HunterController()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
        }
    }
}
