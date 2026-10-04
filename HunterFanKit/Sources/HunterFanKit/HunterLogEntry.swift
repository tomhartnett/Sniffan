import Foundation

/// One line of `HunterController`'s protocol log.
public struct HunterLogEntry: Identifiable, Sendable {
    public enum Kind: Sendable {
        /// Connection progress and other events.
        case info
        /// A packet written to the controller.
        case sent
        /// The controller acknowledged a write.
        case acknowledged
        /// An indication received from the controller.
        case received
        case error
    }

    public let id: Int
    public let date: Date
    public let kind: Kind
    public let message: String
    /// The packet bytes, for `.sent` and `.received` entries.
    public let data: Data?

    /// `data` as space-separated hex, e.g. "f1 c9 af 18".
    public var hex: String? {
        data?.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
