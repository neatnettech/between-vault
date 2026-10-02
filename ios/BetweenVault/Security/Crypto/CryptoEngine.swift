import CryptoKit
import Foundation
import Security

enum CryptoEngine {
    enum CryptoError: Error {
        case decryptFailed
    }

    static let keySize = SymmetricKeySize.bits256

    // MARK: Key material

    static func randomKey() -> Data {
        var bytes = [UInt8](repeating: 0, count: keySize.bitCount / 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    /// A key for one purpose from the pair key. `info` names the purpose; `salt` binds it to one
    /// use, as the exchange ID does for a package key.
    static func derive(pairKey: Data, info: String, salt: Data = Data(), outputByteCount: Int = 32) -> Data {
        let input = SymmetricKey(data: pairKey)
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: input,
            salt: salt,
            info: Data(info.utf8),
            outputByteCount: outputByteCount
        )
        return derived.withUnsafeBytes { Data($0) }
    }

    // MARK: Authenticated encryption (AES-GCM 256)

    /// Returns nonce (12 bytes) + ciphertext + tag (16 bytes).
    static func encrypt(_ plaintext: Data, key: Data, aad: Data = Data()) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plaintext, using: symmetricKey, nonce: nonce, authenticating: aad)
        var out = Data()
        nonce.withUnsafeBytes { out.append(contentsOf: $0) }
        out.append(sealed.ciphertext)
        out.append(sealed.tag)
        return out
    }

    static func decrypt(_ box: Data, key: Data, aad: Data = Data()) throws -> Data {
        guard box.count > 28 else { throw CryptoError.decryptFailed }
        let nonceData = box.prefix(12)
        let tag = box.suffix(16)
        let ciphertext = box.dropFirst(12).dropLast(16)
        let symmetricKey = SymmetricKey(data: key)
        do {
            let sealedBox = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: Data(nonceData)),
                ciphertext: Data(ciphertext),
                tag: Data(tag)
            )
            return try AES.GCM.open(sealedBox, using: symmetricKey, authenticating: aad)
        } catch {
            throw CryptoError.decryptFailed
        }
    }

    // MARK: Pairing verification code

    /// Six digits derived from the pair key and both device IDs. Order independent.
    static func pairingCode(pairKey: Data, deviceIDs: [String]) -> String {
        var hash = SHA256()
        hash.update(data: pairKey)
        for id in deviceIDs.sorted() {
            hash.update(data: Data(id.utf8))
        }
        let digest = hash.finalize()
        let value = digest.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) } % 1_000_000
        return String(format: "%06d", value)
    }
}
