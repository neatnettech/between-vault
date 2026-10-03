import CryptoKit
import Foundation
import Network
import Observation

/// Part C: the two phones find each other and connect directly, over the Wi-Fi radio AirDrop uses
/// (peer to peer, no internet, no Wi-Fi network). Network framework, iOS 17.
///
/// * Each phone advertises a random code for this session, never a name: anything nearby can
///   see what a phone announces.
/// * The connection is TLS with a pre-shared key derived from the pair key, so only the paired
///   phone can complete it; another couple's phone fails the handshake.
/// * It listens only while the exchange screen is open: `stop()` ends both listening and looking.
@MainActor
@Observable
final class NearbyLink {
    enum State: Equatable {
        case idle
        /// N1: looking for the partner's phone.
        case looking
        case connected
        /// iOS local network access is off (N0 explained it; Settings turns it on).
        case localNetworkDenied
        /// Wi-Fi off, or the radio unavailable.
        case unavailable
    }

    static let serviceType = "_bvexchange._tcp"

    private(set) var state = State.idle
    /// Set when a connection to the paired phone is up; the session runs on it.
    private(set) var connection: NearbyConnection?

    @ObservationIgnored private let parameters: NWParameters
    @ObservationIgnored private let code = NearbyLink.randomCode()
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var attempted = Set<String>()

    init(pairKey: Data) {
        parameters = Self.parameters(pairKey: pairKey)
    }

    func start() {
        guard state == .idle || state == .unavailable else { return }
        state = .looking
        startListener()
        startBrowser()
    }

    func stop() {
        listener?.cancel()
        browser?.cancel()
        connection?.close()
        listener = nil
        browser = nil
        connection = nil
        state = .idle
    }

    // MARK: Listening and looking

    private func startListener() {
        guard let listener = try? NWListener(using: parameters) else { state = .unavailable; return }
        // A random code, never the phone's or the owner's name.
        listener.service = NWListener.Service(name: code, type: Self.serviceType)
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.adopt(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.handle(state) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func startBrowser() {
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.found(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.handle(state) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    /// Both phones look and listen; the one with the smaller code connects, so there is never a
    /// pair of crossed connections. A phone that fails the handshake (not the partner) is skipped.
    private func found(_ results: Set<NWBrowser.Result>) {
        guard connection == nil else { return }
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint,
                  name != code, code < name, !attempted.contains(name)
            else { continue }
            attempted.insert(name)
            adopt(NWConnection(to: result.endpoint, using: parameters))
            return
        }
    }

    private func adopt(_ nw: NWConnection) {
        guard connection == nil else { nw.cancel(); return }
        let connection = NearbyConnection(nw) { [weak self] ready in
            guard let self else { return }
            if ready {
                state = .connected
            } else if self.connection != nil {
                // The handshake failed (another couple's phone) or the link dropped.
                self.connection = nil
                if state != .idle { state = .looking }
            }
        }
        self.connection = connection
        connection.start()
    }

    private func handle(_ state: NWListener.State) {
        if case let .failed(error) = state { fail(error) }
        if case let .waiting(error) = state { fail(error) }
    }

    private func handle(_ state: NWBrowser.State) {
        if case let .failed(error) = state { fail(error) }
        if case let .waiting(error) = state { fail(error) }
    }

    private func fail(_ error: NWError) {
        // The local network prompt was refused: Bonjour reports the policy denial.
        if case let .dns(code) = error, code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) {
            state = .localNetworkDenied
        } else if state == .looking {
            state = .unavailable
        }
    }

    // MARK: Parameters

    /// TLS 1.2 with a pre-shared key (the API Apple's own peer to peer sample uses), over TCP,
    /// allowed onto the peer to peer radio. The key is an HKDF of the pair key with its own label,
    /// apart from the package and recovery keys; the identity is a constant, never a name.
    static func parameters(pairKey: Data) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let psk = CryptoEngine.derive(pairKey: pairKey, info: "betweenvault.nearby.v1")
        let identity = Data("betweenvault".utf8)
        sec_protocol_options_add_pre_shared_key(
            tls.securityProtocolOptions,
            psk.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData,
            identity.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData
        )
        sec_protocol_options_append_tls_ciphersuite(
            tls.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!
        )
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }

    /// Eight hex characters, new every time the screen opens.
    private static func randomCode() -> String {
        CryptoEngine.randomKey().prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

/// One connection, carrying length prefixed messages (4 byte big endian length, then the bytes)
/// over the TLS stream. The session (part B) sits on top through `NearbyTransport`.
@MainActor
final class NearbyConnection: NearbyTransport {
    var onReceive: ((Data) -> Void)?
    var onClose: (() -> Void)?

    /// A message larger than this is not ours: a package of notes is far smaller.
    private static let maximumMessage = 16 * 1024 * 1024

    private let connection: NWConnection
    private let onReady: (Bool) -> Void
    private var closed = false

    init(_ connection: NWConnection, onReady: @escaping (Bool) -> Void) {
        self.connection = connection
        self.onReady = onReady
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.handle(state) }
        }
        connection.start(queue: .main)
    }

    func send(_ data: Data) {
        guard !closed else { return }
        var length = UInt32(data.count).bigEndian
        let frame = Data(bytes: &length, count: 4) + data
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    func close() {
        guard !closed else { return }
        closed = true
        connection.cancel()
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            onReady(true)
            receiveLength()
        case .failed, .cancelled:
            let wasOpen = !closed
            closed = true
            onReady(false)
            if wasOpen { onClose?() }
        default:
            break
        }
    }

    private func receiveLength() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            MainActor.assumeIsolated {
                guard let self, let data, data.count == 4, error == nil else { self?.lost(); return }
                let length = Int(data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian)
                guard length > 0, length <= Self.maximumMessage else { self.lost(); return }
                // The end of the stream shows up on the next read, as no data.
                self.receiveBody(length)
            }
        }
    }

    private func receiveBody(_ length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, error in
            MainActor.assumeIsolated {
                guard let self, let data, data.count == length, error == nil else { self?.lost(); return }
                self.onReceive?(data)
                self.receiveLength()
            }
        }
    }

    private func lost() {
        guard !closed else { return }
        closed = true
        connection.cancel()
        onClose?()
    }
}
