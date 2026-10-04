import HunterFanKit
import SwiftUI

struct ContentView: View {
    let controller: HunterController
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: [HunterCommand: CommandStatus] = [:]

    enum CommandStatus {
        case sending, succeeded, failed
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Controller", value: statusText)
                }

                Section {
                    commandButton("Light", "lightbulb", .light)
                    commandButton("Fan On / Off", "fan", .fan)
                }

                Section("Fan Speed") {
                    commandButton("Low", "gauge.with.dots.needle.33percent", .low)
                    commandButton("Medium", "gauge.with.dots.needle.50percent", .medium)
                    commandButton("High", "gauge.with.dots.needle.67percent", .high)
                }

                Section {
                    ForEach(controller.log.reversed()) { entry in
                        LogRow(entry: entry)
                    }
                } header: {
                    HStack {
                        Text("Log")
                        Spacer()
                        Button("Clear") { controller.clearLog() }
                            .font(.caption)
                            .disabled(controller.log.isEmpty)
                    }
                }
            }
            .navigationTitle("Ceiling Fan")
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

    private var isSending: Bool {
        status.values.contains(.sending)
    }

    private func commandButton(_ title: String, _ systemImage: String, _ command: HunterCommand) -> some View {
        Button {
            send(command)
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                statusIndicator(status[command])
            }
        }
        .disabled(controller.state != .ready || isSending)
    }

    @ViewBuilder
    private func statusIndicator(_ status: CommandStatus?) -> some View {
        switch status {
        case .sending:
            ProgressView()
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }

    private func send(_ command: HunterCommand) {
        status[command] = .sending
        Task {
            let result: CommandStatus
            do {
                try await controller.send(command)
                result = .succeeded
            } catch {
                result = .failed
            }
            withAnimation { status[command] = result }

            // Fade the result out, unless the button has been pressed again.
            try? await Task.sleep(for: .seconds(1.5))
            if status[command] == result {
                withAnimation { status[command] = nil }
            }
        }
    }
}

private struct LogRow: View {
    let entry: HunterLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.date, format: .dateTime.hour().minute().second().secondFraction(.fractional(3)))
                    .foregroundStyle(.secondary)
                Image(systemName: symbol)
                    .foregroundStyle(color)
                Text(entry.message)
            }
            if let hex = entry.hex {
                Text(hex)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.monospaced())
        .textSelection(.enabled)
    }

    private var symbol: String {
        switch entry.kind {
        case .info: "info.circle"
        case .sent: "arrow.up.circle"
        case .acknowledged: "checkmark.circle"
        case .received: "arrow.down.circle"
        case .error: "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch entry.kind {
        case .info: .secondary
        case .sent: .blue
        case .acknowledged: .green
        case .received: .purple
        case .error: .red
        }
    }
}
