# Between Vault protocol, version 1

This document describes everything that leaves a Between Vault phone: the pairing codes, the exchange package (`.nvlt`), the recovery file (`.nvrec`) and the nearby connection. The code in `ios/BetweenVault/Security` and `ios/BetweenVault/Protocol` is the reference; where this text and the code disagree, the code wins and this text is a bug.

There is no server. Nothing here is sent anywhere by the app on its own: every transfer starts with one of the two people.

## Primitives

All cryptography is Apple CryptoKit and the Network framework.

| Use | Primitive |
| --- | --- |
| Key agreement | X25519, one time keys per pairing attempt |
| Key derivation | HKDF with SHA256 |
| Encryption | AES 256 GCM, random 12 byte nonce |
| Commitment and codes | SHA256 |
| Nearby link | TLS 1.2 with a pre shared key, `TLS_PSK_WITH_AES_128_GCM_SHA256` |

An AES GCM box is always `nonce (12 bytes) || ciphertext || tag (16 bytes)`.

Device IDs are random UUIDs, one per installation, written in lowercase. A reset of the vault makes a new one.

## Keys

| Key | Where it lives | Made from |
| --- | --- | --- |
| Vault key | Keychain, this device only | 32 random bytes. Encrypts each note's title and body at rest. Never leaves the phone except inside a recovery blob. |
| Pair key | Keychain, this device only | Pairing, below |
| Package key | Never stored | `HKDF(pairKey, salt: exchange ID, info: "betweenvault.exchange.v1")` |
| Recovery key | Never stored | `HKDF(pairKey, info: "betweenvault.recovery.v1")` |
| Nearby key | Never stored | `HKDF(pairKey, info: "betweenvault.nearby.v1")` |
| Fingerprint | Shown on screen | first 16 bytes of `HKDF(pairKey, info: "betweenvault.fingerprint.v1")`, as 32 hex characters |

The pair key itself never encrypts anything. Each use has its own derived key.

## Pairing

Pairing happens in person with three QR codes, commit first, as in Bluetooth numeric comparison. No QR carries a secret.

1. A makes a one time X25519 key and a 16 byte nonce, and shows QR 1: `SHA256("betweenvault.commit.v1" || offer(A) || nonce)`.
2. B scans it, makes its own one time key, and shows QR 2: `offer(B)`.
3. A scans it, derives the pair key, and shows QR 3: `offer(A) || nonce`.
4. B scans it and checks it against QR 1. A mismatch stops the pairing.
5. Both phones show the same six digit code. Each person confirms on their own phone, and each phone saves only on its own confirmation.

`offer(X)` is the 32 byte public key followed by the 16 raw bytes of the device ID.

Because A's key stays hidden until B's key is fixed, nobody in the middle can try keys until both codes match: a forged pairing shows matching codes one time in a million. A reveals once per attempt; a retry starts over with a new key and a new QR 1.

```
pairKey = HKDF(
  X25519(own private, their public),
  salt: the two public keys sorted bytewise and joined,
  info: "betweenvault.pairKey.v1|" + the two device IDs sorted and joined with "|",
  32 bytes)

code = SHA256(pairKey || the two device IDs sorted, as UTF8),
       first 8 bytes as a little endian integer, modulo 1 000 000, six digits
```

QR text: `betweenvault:pair:` then base64url without padding of `version (1 byte, 1) || step (1 byte, 1 to 3) || payload`. The payloads are 32, 48 and 64 bytes for steps 1, 2 and 3.

## Exchange package (`.nvlt`)

A file of UTF8 JSON with sorted keys:

```json
{
  "format": "betweenvault.exchange",
  "package": {
    "protocolVersion": 1,
    "senderDeviceID": "…",
    "recipientDeviceID": "…",
    "exchangeID": "…",
    "createdAt": 0,
    "ciphertext": "base64"
  }
}
```

`ciphertext` is an AES GCM box under the package key. Its additional authenticated data is the header, encoded as JSON with sorted keys: `protocolVersion`, `senderDeviceID`, `recipientDeviceID`, `exchangeID`, `createdAt`. Changing any header field breaks the check, so a package cannot be readdressed or replayed under another ID.

The plaintext is a JSON array of items:

| Field | Meaning |
| --- | --- |
| `objectID` | The note's UUID, the same on both phones |
| `version` | The sender's version of the note |
| `baseVersion` | The version the sender last had from the partner, for conflict detection |
| `updatedAt` | Last edit |
| `title`, `body` | The note. `body` is plain text that may carry inline Markdown marks (`**bold**`, `*italic*`, `~~struck~~`, with `\` escaping a literal mark character) and list prefixes (`• `, `1. `); a reader that does not render them shows them as typed |
| `category` | `name`, `symbol`, and `builtInKey` for built in categories, or absent |

A receiving phone imports a package only if it comes from the paired partner, is addressed to this phone, and authenticates. Import is atomic: all items land or none do. Titles are shown for review before anything is saved, and a note changed on both phones asks the owner which copy to keep.

Unknown future versions are refused, not guessed at.

## Recovery file (`.nvrec`)

The recovery copy is the owner's vault key only, never notes.

```
blob = AES-GCM(vaultKey, key: recoveryKey(pairKey), aad: "recovery|" + owner device ID)
```

The file is UTF8 JSON:

```json
{
  "format": "betweenvault.recovery",
  "version": 1,
  "ownerDeviceID": "…",
  "holderDeviceID": "…",
  "blob": "base64",
  "returned": "base64, optional"
}
```

The holder keeps only `blob`, and only if the file names the paired partner as owner and this phone as holder, and the blob opens under the current pair key. By design the holder can open it: a paired partner can recover the vault.

### Restore on a new phone

1. The owner's new phone (or the same phone after a reset) has a fresh device ID and no pairing.
2. On the partner's phone, "Partner has a new iPhone" ends the old pairing but keeps the owner's blob together with the old pair key and the old device ID.
3. The two phones pair again, which gives a new pair key.
4. The partner sends a recovery file. Next to the partner's own blob, `returned` carries the owner's vault key, unwrapped with the old pair key and wrapped again under the new one, bound to the owner's new device ID.
5. The owner's phone opens `returned` under the new pair key. It installs the key only when notes on the phone wait for a key and the returned key decrypts one of them.

A file with a `returned` field that does not open for this phone under this pairing is refused as a whole. Files without the field, from before restore existed, read as before.

The data comes back separately: from an iPhone backup of the app, or, for shared notes, from the partner sending them again. Without a partner and without a backup there is nothing to restore from.

## Nearby connection

Used when both phones are side by side and someone opened the exchange or recovery screen.

* Bonjour service `_bvexchange._tcp`, peer to peer allowed. Each phone advertises a random code, and the phone with the smaller code connects.
* TLS 1.2 with the nearby key as the pre shared key, identity `betweenvault`. A phone without the pair key cannot finish the handshake.
* Each message is a 4 byte big endian length, then that many bytes of JSON, at most 16 MiB.
* Messages: `hello` (protocol version and device ID, checked against the partner), `confirmations` (exchange IDs imported, IDs only), `offer` (the same bytes as a `.nvlt` file), `accepted`, `declined`, `imported`, `recovery` (the same bytes as a `.nvrec` file), `recoveryStored`, `recoveryRefused`, `holdsRecovery`, `bye`.

Packages sent nearby are still sealed packages: the link is a second layer, not the only one.

## Versioning

`protocolVersion` in packages, `version` in recovery files, and the first byte of pairing codes are versioned apart. A phone refuses a version it does not know and says so; it never tries to read it.
