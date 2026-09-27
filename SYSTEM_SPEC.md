# Private Couple Vault

## System Specification & Product Vision

**Status:** Draft v0.2
**Platform:** iOS
**Architecture:** Local first, zero cloud, encrypted vault for two people
**Primary principle:** Nothing leaves a device unless a person explicitly chooses to exchange it.

---

# 1. Decision Log

v0.2 decisions, agreed during review:

* Single partner per install.
* Symmetric pair key instead of per device asymmetric identities.
* Per record encryption with a Keychain held vault key instead of SQLCipher.
* Snapshot exchange instead of operation log and delta engine.
* Trusted partner recovery instead of passphrase or server based recovery.
* Freemium: notes are free, attachments are a paid nonconsumable unlock at $9.99.
* 1.0 ships notes only. Attachments arrive in 1.1 as the paid feature.
* Persistence via SwiftData (SQLite backing), decoupled behind a repository layer.
* GPLv3, open source from day 1. Funding goal: cover costs plus coffee, via App Store sales and donations.

---

# 2. Product Vision

Private Couple Vault is a private digital space for two people to intentionally store, protect, and exchange information that belongs between them.

It is not a messaging application.

It is not a cloud notes application.

It is not a password manager.

It is a **private vault shared deliberately between two trusted people**.

The fundamental product promise is:

> **Your data stays with you until you decide to give it to the other person.**

There is no central account, no cloud database, no automatic synchronization, and no background sharing.

Each person owns an independent local vault.

The two vaults communicate only through explicitly initiated encrypted exchanges.

---

# 3. Product Philosophy

## 3.1 Privacy by architecture

Privacy must not depend solely on a privacy policy.

There should be:

* no application backend
* no user accounts
* no cloud database
* no analytics
* no advertising
* no behavioral tracking
* no automatic synchronization
* no background exchange
* no server side plaintext
* no requirement for internet connectivity

---

# 4. Core Product Concept

Each person has their own vault.

```text
Person A
└── Vault A
    ├── Private information
    ├── Sealed information
    └── Shared information


Person B
└── Vault B
    ├── Private information
    ├── Sealed information
    └── Shared information
```

The vaults are independent. There is no "master shared database."

Information moves between them only through an authenticated encrypted exchange initiated by a person.

---

# 5. Information States

Every vault object has an explicit sharing state.

## 5.1 Private

Only the owner has access.

```text
PRIVATE
```

Example: personal note, private financial information, personal journal.

## 5.2 Sealed

The owner has explicitly prepared the object for the partner but has not yet sent it.

```text
SEALED
```

This represents deliberate intent.

## 5.3 Shared

The object has been successfully transferred to the partner's vault, or received from the partner.

```text
SHARED
```

The app never implies that shared information can be remotely deleted. Once information has reached another device, the sender no longer controls that copy.

---

# 6. Primary Use Cases

## 6.1 Emergency information

The primary use case. Insurance information, bank information, important contacts, home and vehicle information, legal information, account recovery information, instructions for the partner.

## 6.2 Important household information

Internet, electricity, keys, utilities, important contacts.

## 6.3 Documents

Passports, insurance documents, contracts, warranties, property documents, vehicle documents. In 1.0 these live as notes. In 1.1 they can be attached as encrypted files (paid feature).

## 6.4 Personal information

Personal notes, private instructions, things the partner should know.

---

# 7. Product Principles

## Principle 1: No automatic synchronization

The application must never silently synchronize vault contents.

There is no "Last synced 2 minutes ago". Instead: "Last exchanged yesterday".

## Principle 2: Explicit consent for exchange

An exchange requires deliberate user action.

```text
3 items will be shared with your partner.

[Review]
[Cancel]
```

## Principle 3: Encryption before transport

The transport mechanism must not be trusted. The exchange package is fully encrypted before it leaves the device.

AirDrop, Files, Messages, Mail, USB, and nearby transfer are transport mechanisms, not security mechanisms.

## Principle 4: No server dependency

The core system works without an internet connection. Pairing and exchange are fully offline capable.

## Principle 5: The protocol is independent from local storage

The exchange package is a versioned document format. It does not leak the local storage schema. Future clients can implement the protocol without coupling to SwiftData or SQLite internals.

---

# 8. Business Model

## 8.1 Freemium

* Free tier: unlimited notes, categories, pairing, exchange, recovery, encrypted backup export. The entire 1.0 product plus backup.
* Paid tier: Attachments, a single nonconsumable unlock (photos, scans, documents attached to notes). Ships in 1.1.

## 8.2 StoreKit

* StoreKit 2, local AppTransaction validation. No server side receipt verification, no account.
* No subscription in 1.x. Local storage costs nothing recurring, so a one time purchase is honest.
* Launch price $9.99 USD, one time, regional pricing via App Store. No intro offers (nonconsumable IAP has none); price can be raised for new buyers later without affecting existing ones.
* No attachment storage cap. The only limit is per file size (around 250MB) for AirDrop and memory sanity. Copy: "Your free space is the limit."
* Partner unlock relies on Family Sharing (nonconsumable IAPs support it). No custom entitlement sync between devices. Paywall copy: "One purchase, shared with your partner via Family Sharing."
* Safety features are never paywalled: encrypted backup export is free for everyone.

## 8.3 Pricing rationale

* No marginal cost (zero cloud) means a subscription is unjustifiable and would erode trust with the privacy aware audience.
* Under GPL the code is free. The purchase pays for updates, App Store publishing, and distribution, not for the code itself. Copy says this plainly.
* The value frame is peace of mind ("life documents, encrypted, findable in an emergency"), and attachments are the concrete trade.
* Below $10 keeps the purchase impulse friendly and defensible: cheaper than a subscription month elsewhere, one time, forever.
* Purchase data from App Store Connect (aggregate sales, not behavioral analytics) informs future price adjustments.

## 8.4 Open source

* License: GPLv3. Forks must stay open; nobody can close the code into a proprietary app.
* Open from day 1. Openness is the trust engine: the privacy aware audience pays precisely because they can verify the code.
* The repository also publishes the `.nvlt` protocol specification as an independent document (PROTOCOL.md), decoupled from the iOS app internals.
* Funding channels: the App Store one time unlock, plus GitHub Sponsors. Goal: cover costs and coffee, not a foundation. No server costs exist, so the burn rate is near zero.
* Piracy of the entitlement check in forks is expected and accepted; the audience that pays is paying for trust, updates, and distribution.
* Community security audits are a stated benefit of the open model; an independently reviewed codebase is the primary marketing asset.
* No analytics applies to the repository too: no crash trackers, no telemetry, no tracking links.

## 8.3 Discovery without analytics

No analytics SDK. Product feedback comes from user research, App Store reviews, and voluntary feedback.

---

# 9. High Level Architecture

```text
┌──────────────────────────────────────────────┐
│                  SwiftUI                     │
├──────────────────────────────────────────────┤
│              Application Layer               │
│                                              │
│ VaultService                                 │
│ NoteService                                  │
│ ExchangeService                              │
│ PartnerService                               │
│ AuthenticationService                       │
├──────────────────────────────────────────────┤
│                 Domain                       │
│                                              │
│ Vault                                        │
│ Note                                         │
│ Category                                     │
│ Partner                                      │
│ Exchange                                     │
├──────────────────────────────────────────────┤
│              Security Core                   │
│                                              │
│ CryptoEngine                                 │
│ KeyManager                                   │
│ SecureStorage                                │
├──────────────────────────────────────────────┤
│              Persistence                     │
│                                              │
│ SwiftData (SQLite backing)                   │
│ Repository Layer                             │
├──────────────────────────────────────────────┤
│                   iOS                        │
│                                              │
│ Keychain                                     │
│ Face ID / Touch ID                           │
│ Data Protection                              │
└──────────────────────────────────────────────┘
```

---

# 10. Technology Stack

## Application

* Swift
* SwiftUI
* Swift Concurrency
* Swift Testing
* XCTest where required

## Security

* CryptoKit
* Security framework
* LocalAuthentication
* Keychain

## Storage

* SwiftData (SQLite backing)
* Application level encryption for all record content

## Transport

* Share Sheet
* AirDrop
* Encrypted file package (`.nvlt`)

Future: MultipeerConnectivity for direct nearby transfer.

## External dependencies

Apple frameworks only. No cloud SDK, no analytics SDK, no third party crypto.

---

# 11. Cryptographic Architecture

The application must never implement cryptographic primitives itself. Use CryptoKit.

## 11.1 Keys

```text
vaultKey (per device)
    └── encrypts every record at rest (AES-GCM)

pairKey (per couple)
    ├── encrypts exchange packages (AES-GCM)
    └── binds packages to sender, recipient, and exchange
```

* `vaultKey`: random 256 bit, generated at first launch, held in Keychain with `ThisDeviceOnly` accessibility and biometric access control.
* `pairKey`: random 256 bit, generated by the pairing initiator, transferred to the partner inside the pairing QR, held in Keychain on both devices.
* All keys are random. No passphrase derived keys, no stored plaintext.

## 11.2 Primitives

* AES-GCM (256 bit) for authenticated encryption at rest and in transit
* HKDF for subkey derivation where separate keys are needed
* SHA-256 for the pairing verification code
* CryptoKit random generation for all keys and nonces

---

# 12. Device Identity

Each installation has a random device ID, generated at first launch.

```text
Device Identity
├── device_id (random UUID)
└── relationship state (unpaired / paired)
```

There are no per device signing or exchange key pairs. The pair key is the shared secret of the couple, held by exactly two devices.

The partner relationship is established by explicitly pairing the two installations.

---

# 13. Pairing

Pairing requires explicit action and visual confirmation from both people.

```text
Device A: [Pair with Partner]
        ↓
A generates pairKey, shows QR:
  pairKey + device_id(A) + recovery blob(A)
        ↓
Device B scans
        ↓
Both devices display: 481 923
        ↓
User confirms matching code
        ↓
B shows QR: device_id(B) + recovery blob(B)
        ↓
A scans
        ↓
Relationship established
```

Details:

* The six digit verification code is derived from the pair key and both device IDs. It protects against accidental pairing and shoulder surfed QR capture.
* The QR is ephemeral, exchanged in person, and never reused.
* Pairing works fully offline.
* `recovery blob(X)` is X's vault key wrapped under the pair key. By design, a paired partner holds the ability to recover the other's vault. This is the trust model, stated openly in the partner screen.

Unpairing revokes the relationship: both pair keys are deleted, recovery blobs are discarded, and previously shared objects keep their last state.

---

# 14. Partner Record

```text
Partner
├── device_id
├── fingerprint (pairing verification code)
├── paired_at
└── relationship state
```

The fingerprint is displayed in the Partner screen so users can verify the partner remains the same pairing.

---

# 15. Vault Encryption at Rest

Every note is encrypted with the vault key before it touches storage.

```text
SwiftData / SQLite
        │
   category metadata (names, IDs, state)
        │
   encrypted record (title + body, AES-GCM)
        │
   vaultKey held in Keychain, never in the database
```

* The nonce travels inside the ciphertext blob.
* Categories carry no content, so plaintext category names leak only structure, nothing sensitive.
* iOS Data Protection (`NSFileProtectionComplete`) covers the database file itself.

One correctly applied layer is preferred over redundant layering. SQLCipher is intentionally not used.

---

# 16. Data Model

```text
category
├── id
├── name
└── sort

note
├── id
├── category_id
├── state (private / sealed / shared)
├── version
├── base_version
├── ciphertext (title + body)
├── created_at
└── updated_at

partner
├── device_id
├── fingerprint
├── paired_at
└── state

exchange_log
├── exchange_id
├── direction
└── imported_at
```

`base_version` is the version the partner's copy was based on at the last exchange. It is the only bookkeeping needed for conflict detection; no operation log.

---

# 17. Exchange Protocol

An exchange is a single encrypted package containing the full current snapshots of the chosen objects.

```text
Sealed notes
       │
       ▼
Package header
       │
       ▼
Serialize items (JSON)
       │
       ▼
AES-GCM under pairKey
   with AAD binding protocol version, sender, recipient, exchange ID
       │
       ▼
.nvlt file
```

## 17.1 Package format (protocol version 1)

```text
NVLT
├── protocol_version = 1
├── sender_device_id
├── recipient_device_id
├── exchange_id
├── created_at
├── items[]
│   ├── object_id
│   ├── category_id
│   ├── base_version
│   ├── version
│   ├── updated_at
│   ├── title
│   └── body
└── ciphertext (AES-GCM, AAD binds the header fields)
```

The title and body are plaintext inside the package but the package itself is one end to end encrypted blob. The transport never sees content.

## 17.2 Import validation

```text
Receive file
  ↓
Validate format and protocol version
  ↓
Verify recipient device ID matches this device
  ↓
Verify AEAD (key, tamper, corruption)
  ↓
Dedupe by exchange ID
  ↓
Per item conflict check
  ↓
Apply atomically
```

The entire import is atomic. Either the complete valid exchange is applied or nothing is applied.

---

# 18. Conflict Resolution

The application is not a real time collaborative editor. Versions make divergence detectable without an operation log.

On import of an item:

* No local copy: create it.
* Local version equals incoming version: no-op.
* Incoming version is newer and its base version equals the local version: fast forward.
* Otherwise: conflict.

```text
Conflict detected

[Keep mine]
[Keep partner's]
[Keep both as copy]
```

Destructive resolution never silently discards information. "Keep both" preserves both edits as separate objects.

---

# 19. Transport Independence

```text
              Exchange Package
                     │
      ┌──────────────┼──────────────┐
      │              │              │
   AirDrop        Files         Nearby
```

The package remains equally secure regardless of transport, because it is encrypted before transport and authenticated against sender, recipient, and exchange ID.

---

# 20. Trusted Partner Recovery

Recovery has two parts: the key and the data.

## 20.1 The key

The partner holds a copy of your vault key, wrapped under the pair key.

```text
Lost phone
   ↓
New phone: install app, pair again with partner (fresh pairKey v2)
   ↓
Partner exports your recovery blob (wrapped under the old pairKey v1)
   ↓
Partner's app unwraps with v1, re-wraps under v2, sends
   ↓
New phone unwraps with v2, obtains your original vault key
```

No passphrase, no server, no central secret.

## 20.2 The data

* If the user had iCloud device backup enabled, the restored app data is unlocked by the recovered vault key.
* Notes previously exchanged with the partner survive on the partner's device regardless.
* Private notes survive only through a device backup. This limitation is stated in the UI.

## 20.3 Honest limits

* Both phones lost at once with no backups: the vault is gone. This is the price of zero cloud and is documented.
* The partner can, by design, recover the vault. This is the trust model, not a vulnerability, and is stated openly.

---

# 21. Authentication

```text
Open App
   ↓
Face ID
   ↓
Vault unlocked
```

Fallback: vault passcode.

Biometrics authorize access to the Keychain held key material. They are not used as the encryption key itself.

---

# 22. Application Lock

The application locks automatically when:

* entering background
* the device is locked
* a configurable timeout expires
* the user explicitly locks the vault

The background snapshot must never expose vault contents.

---

# 23. Sensitive Data Leakage Prevention

### Notifications

Never expose sensitive content. Use "New encrypted item available", never "Piotr shared the bank password."

### Clipboard

Copying sensitive information supports automatic clipboard clearing.

### Logging

Sensitive data must never appear in console logs, crash reports, or diagnostics.

### App switcher

Sensitive screens are obscured before the application enters the background.

### Search

Sensitive vault content does not appear in global system search. In app search over encrypted content is out of scope for 1.0.

---

# 24. Backup Strategy

* Device backup: the encrypted database and files are covered by standard iOS device backup, still unreadable without the vault key.
* Vault backup: encrypted vault export to a device or drive of the user's choice. Free for everyone. Targets 1.1 alongside attachments, since both share the file export machinery.

The application never uploads the vault automatically.

---

# 25. Security Threat Model

The system explicitly defends against:

* lost device
* stolen device
* filesystem extraction
* unauthorized app access
* malicious transport
* intercepted exchange packages
* package modification
* replay attacks
* wrong recipient
* corrupted exchange packages
* accidental duplicate imports
* shoulder surfed pairing codes

The system does not attempt to protect against:

* a fully compromised iOS installation
* a malicious or jailbroken device with complete runtime control
* a user intentionally sharing information outside the application
* screenshots or photographs taken by an authorized recipient
* a pairing QR captured by a sophisticated attacker during the brief in person window

The threat model is documented publicly.

---

# 26. Privacy Model

The application collects effectively zero user data.

There is no account ID, email, phone number, contact list, location, analytics identifier, advertising identifier, or relationship metadata leaving the device.

The only identity that matters is the local device ID and the pair key of the couple.

---

# 27. No Analytics

The initial release contains no analytics SDK and no behavioral tracking.

Crash information may be considered later only through a privacy preserving mechanism.

---

# 28. UX Structure

Primary navigation:

```text
Vault
Exchange
Partner
Settings
```

Vault:

```text
Emergency
Home
Documents
Finance
Personal
Other
```

Objects carry their state badge:

```text
Private
Sealed
Shared
```

Exchange:

```text
Waiting for me
Ready to send
Recently exchanged
```

The interface should feel closer to Files + Notes + a password manager than a traditional couples application.

---

# 29. Exchange UX

```text
EXCHANGE

3 items ready to send

[Review]

        ↓

REVIEW

Emergency
 ├── Insurance
 ├── Bank
 └── Contact

        ↓

[Encrypt & Share]

        ↓

iOS Share Sheet

        ↓

Partner receives package

        ↓

IMPORT

3 items from Partner

[Review]

        ↓

[Accept]
```

There should never be ambiguity about what is leaving the device.

---

# 30. Product Language

Avoid "100% secure", "unhackable", "military grade", "anonymous".

Prefer factual language:

* "No cloud storage"
* "No automatic synchronization"
* "End to end encrypted exchange"
* "Stored locally on your device"
* "You control when information is shared"
* "Your partner can recover your vault by design"

---

# 31. Development Architecture

```text
CoupleVault/
│
├── LICENSE (GPLv3)
├── PROTOCOL.md (exchange package specification)
├── App/
│
├── Features/
│   ├── Vault/
│   ├── Notes/
│   ├── Exchange/
│   ├── Partner/
│   └── Settings/
│
├── Domain/
│   ├── Vault/
│   ├── Objects/
│   ├── Partner/
│   └── Exchange/
│
├── Security/
│   ├── Crypto/
│   ├── KeyManagement/
│   └── Authentication/
│
├── Persistence/
│   ├── Database/
│   ├── Repositories/
│   └── Migrations/
│
├── Protocol/
│   ├── Model/
│   ├── Serialization/
│   └── Validation/
│
└── Tests/
    ├── Security/
    ├── Protocol/
    ├── Persistence/
    └── Exchange/
```

Security and protocol components must be independently testable from the UI.

---

# 32. Testing Requirements

### Cryptography

* encryption / decryption round trips
* tampered ciphertext rejection
* wrong key rejection
* corrupted package rejection

### Protocol

* malformed packages
* unsupported protocol versions
* wrong recipient
* duplicate exchange IDs
* invalid items

### Persistence

* migrations
* transaction rollback
* interrupted imports
* payload decryption failures

### Exchange

* clean exchange
* repeated exchange
* conflicting modifications (all three resolutions)
* interrupted import
* corrupted import

### Security

* lock / unlock
* backgrounding
* biometric failure
* device lock
* clipboard handling
* notification handling

---

# 33. Protocol Versioning

```text
protocol_version = 1
```

The application rejects unsupported protocol versions safely. Future versions (deltas, attachments, multi device) roll out behind new version numbers without forcing simultaneous updates.

---

# 34. Roadmap

## 1.0 (free)

Notes only: vault, categories, states, pairing with QR and code, Face ID lock, snapshot exchange via share sheet, atomic import, conflict resolution, trusted partner recovery. No analytics, no cloud.

## 1.1 (paid unlock)

Attachments: encrypted files and photos attached to notes, share sheet import, per file size limit only, no storage cap. Encrypted vault backup export (free for everyone). Nonconsumable IAP at $9.99, StoreKit 2, local receipt validation.

## Later

* Direct nearby exchange via MultipeerConnectivity
* Delta exchange (protocol version 2) if transfer sizes grow
* Multi device ownership (iPhone + iPad per person)
* In app search over encrypted content

---

# 35. Explicit Non-Goals

The first versions must not become:

* a messaging application
* a social network
* a couples journal
* a cloud drive
* a password manager replacement
* a real time collaborative editor
* a family management application
* an automatic synchronization service

The product remains intentionally narrow.

---

# 36. MVP Definition

### Local vault

* SwiftData persistence
* categories
* notes with private / sealed / shared states
* encrypted records
* Face ID lock
* privacy blur on background

### Pairing

* QR pairing
* six digit verification code
* fingerprint display

### Exchange

* object selection and review
* encrypted package generation
* share sheet handoff
* package validation
* atomic import
* conflict resolution

### Recovery

* partner held vault key
* device backup unlock

### Business

* notes free
* attachments paid (1.1)

---

# 37. Core Product Invariants

> **A vault must never communicate with another vault unless the owner explicitly initiates an exchange.**

> **Every exchanged object must be cryptographically bound to the intended recipient and authenticated against tampering.**

> **The transport must never be trusted with the contents of an exchange.**

These three principles guide the architecture, protocol, and UX.

---

# 38. Long-Term Vision

The long term product is not simply an encrypted notes application.

It is a **private digital relationship layer**.

Two people can maintain independent digital lives while intentionally creating a shared cryptographic space between them.

The central idea remains deliberately simple:

> **Private by default. Shared by choice. No cloud required.**

That principle remains intact even as the product grows.
