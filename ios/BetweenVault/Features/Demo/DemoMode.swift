#if DEBUG
import SwiftUI

/// Debug builds only, for screenshots: `-demo -demoScreen vault|note|exchange|delivered`. Runs on
/// an in-memory store with sample notes and a demo partner, never the Keychain or the real store,
/// and skips onboarding and the lock. Compiled out of release builds entirely.
enum DemoMode {
    enum Screen: String {
        case vault, note, exchange, delivered
    }

    static var screen: Screen? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-demo") else { return nil }
        guard let index = arguments.firstIndex(of: "-demoScreen"), index + 1 < arguments.count else { return .vault }
        return Screen(rawValue: arguments[index + 1]) ?? .vault
    }

    @MainActor
    static func services() throws -> AppServices {
        let services = try AppServices(demoKey: CryptoEngine.randomKey())
        try seed(services)
        return services
    }

    /// Sample notes a couple would keep, across the three states.
    @MainActor
    private static func seed(_ services: AppServices) throws {
        let categories = try services.categoryRepository.categories()
        func category(_ key: BuiltInCategory) -> UUID? { categories.first { $0.builtInKey == key }?.id }
        func named(_ name: String) -> UUID? { categories.first { $0.name == name }?.id }
        let day: TimeInterval = 86_400
        let samples: [(String, String, NoteState, UUID?, Int, Int, TimeInterval)] = [
            ("Who to call first", "Mum: +44 7700 900123\nOur GP, Dr Patel: 020 7946 0321\nNeighbour with the spare key: Sam, flat 4.", .shared, category(.emergency), 2, 2, 2 * day),
            ("Doctor and pharmacy", "Surgery opens 8:00. Repeat prescriptions online.\nPharmacy on Elm Street, open late on Thursdays.", .sealed, category(.emergency), 1, 0, 0.2 * day),
            ("Home insurance", "Policy HX-48213, renews 14 March.\nClaims line on the back of the card in the blue folder.", .sealed, named("Home"), 1, 0, 0.1 * day),
            ("Boiler service", "Annual service booked for October.\nEngineer: Northside Heating, 0161 496 0754.", .shared, named("Home"), 3, 2, 0.05 * day),
            ("Landlord contact", "Email first, phone for emergencies only.", .private, named("Home"), 1, 0, 6 * day),
            ("Passports and birth certificates", "Top drawer of the desk, red envelope.", .private, named("Documents"), 1, 0, 12 * day),
            ("Bank and pension contacts", "Joint account at the high street branch. Pension provider letters in the grey box file.", .private, named("Finance"), 1, 0, 20 * day),
            ("Wi-Fi at your parents'", "Network: Hillside-5G", .shared, named("Personal"), 1, 1, 9 * day),
        ]
        for (title, body, state, categoryID, version, partnerKnown, age) in samples {
            let date = Date.now.addingTimeInterval(-age)
            try services.noteRepository.save(Note(
                id: UUID(), title: title, body: body, state: state, categoryID: categoryID, version: version,
                baseVersion: partnerKnown, partnerKnownVersion: partnerKnown, createdAt: date, updatedAt: date
            ))
        }
        try services.partnerRepository.save(Partner(
            id: UUID(), deviceID: UUID().uuidString.lowercased(),
            fingerprint: "5F2A91C07E3B44D8A1C90B72E5F63D18",
            pairedAt: Date.now.addingTimeInterval(-30 * day)
        ))
        try services.exchangeLogRepository.record("demo-sent", direction: .sent, itemCount: 3, at: Date.now.addingTimeInterval(-6 * day))
        try services.pendingPackages.keep(exchangeID: "demo-waiting", data: Data(), itemCount: 2)
    }
}

/// The screen a demo launch opens on.
struct DemoRoot: View {
    let screen: DemoMode.Screen
    let services: AppServices
    @State private var note: Note?

    var body: some View {
        Group {
            switch screen {
            case .vault: RootView(tab: .vault)
            case .exchange: RootView(tab: .exchange)
            case .note:
                NavigationStack {
                    if let note { NoteDetailView(note: note) }
                }
            case .delivered:
                NearbyDelivered(count: 3, sent: 3, confirmed: 1, received: 1, conflicts: 0, onDone: {}, onStay: {})
            }
        }
        .environment(services)
        .modelContainer(services.container)
        .task {
            note = ((try? services.noteRepository.notes(in: nil)) ?? []).first { $0.title == "Boiler service" }
        }
    }
}
#endif
