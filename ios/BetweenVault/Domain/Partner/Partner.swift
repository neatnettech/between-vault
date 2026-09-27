import Foundation

struct Partner: Identifiable, Equatable, Sendable {
    let id: UUID
    let deviceID: String
    let fingerprint: String
    let pairedAt: Date
}
