import HunterFanKit
import SwiftUI

struct ContentView: View {
    let controller: HunterController
    @Environment(\.scenePhase) private var scenePhase
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Controller", value: statusText)
                }

                Section {
                    Button("Light", systemImage: "lightbulb") { send(.light) }
                    Button("Fan On / Off", systemImage: "fan") { send(.fan) }
                }

                Section("Fan Speed") {
                    HStack {
                        speedButton("Low", .low)
                        speedButton("Medium", .medium)
                        speedButton("High", .high)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .disabled(controller.state != .ready)
            .navigationTitle("Ceiling Fan")
            .alert("Command Failed", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        // The controller allows one connection at a time, so let go of it in
        // the background in case another app (or the official one) needs it.
        .onChange(of: scenePhase, initial: true) {
            if scenePhase == .active {
                controller.connect()
            } else if scenePhase == .background {
                controller.disconnect()
            }
        }
    }

    private var statusText: String {
        switch controller.state {
        case .unavailable: "Bluetooth unavailable"
        case .disconnected: "Disconnected"
        case .scanning: "Searching…"
        case .connecting: "Connecting…"
        case .ready: "Connected"
        }
    }

    private func speedButton(_ title: String, _ command: HunterCommand) -> some View {
        Button(title) { send(command) }
            .frame(maxWidth: .infinity)
    }

    private func send(_ command: HunterCommand) {
        Task {
            do {
                try await controller.send(command)
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }
}
