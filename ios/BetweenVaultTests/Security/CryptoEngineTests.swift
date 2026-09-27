import Foundation
import Testing

@testable import BetweenVault

struct CryptoEngineTests {
    @Test func roundTrip() throws {
        let key = CryptoEngine.randomKey()
        let plaintext = Data("Boiler service notes".utf8)
        let aad = Data("header".utf8)

        let box = try CryptoEngine.encrypt(plaintext, key: key, aad: aad)
        let opened = try CryptoEngine.decrypt(box, key: key, aad: aad)

        #expect(opened == plaintext)
    }

    @Test func tamperedCiphertextFails() throws {
        let key = CryptoEngine.randomKey()
        var box = try CryptoEngine.encrypt(Data("secret".utf8), key: key)
        box[box.count - 1] ^= 0xFF

        #expect(throws: CryptoEngine.CryptoError.self) {
            _ = try CryptoEngine.decrypt(box, key: key)
        }
    }

    @Test func wrongKeyFails() throws {
        let box = try CryptoEngine.encrypt(Data("secret".utf8), key: CryptoEngine.randomKey())
        #expect(throws: CryptoEngine.CryptoError.self) {
            _ = try CryptoEngine.decrypt(box, key: CryptoEngine.randomKey())
        }
    }

    @Test func wrongAADFails() throws {
        let key = CryptoEngine.randomKey()
        let box = try CryptoEngine.encrypt(Data("secret".utf8), key: key, aad: Data("a".utf8))
        #expect(throws: CryptoEngine.CryptoError.self) {
            _ = try CryptoEngine.decrypt(box, key: key, aad: Data("b".utf8))
        }
    }

    @Test func pairingCodeIsDeterministicAndOrderIndependent() {
        let key = CryptoEngine.randomKey()
        let first = CryptoEngine.pairingCode(pairKey: key, deviceIDs: ["A", "B"])
        let second = CryptoEngine.pairingCode(pairKey: key, deviceIDs: ["B", "A"])

        #expect(first == second)
        #expect(first.count == 6)
        #expect(first.allSatisfy { $0.isNumber })
    }
}
