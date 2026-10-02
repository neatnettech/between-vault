# Between Vault

[![CI](https://github.com/neatnettech/between-vault/actions/workflows/ci.yml/badge.svg)](https://github.com/neatnettech/between-vault/actions/workflows/ci.yml)
[![Pages](https://github.com/neatnettech/between-vault/actions/workflows/pages.yml/badge.svg)](https://github.com/neatnettech/between-vault/actions/workflows/pages.yml)
[![Version](https://img.shields.io/github/v/tag/neatnettech/between-vault?sort=semver&label=version)](https://github.com/neatnettech/between-vault/tags)
[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-lightgrey.svg)](ios/project.yml)
[![Swift](https://img.shields.io/badge/swift-6.0-orange.svg)](ios/project.yml)
[![Buy Me a Coffee](https://img.shields.io/badge/buy%20me%20a%20coffee-support-yellow.svg?logo=buymeacoffee)](https://buymeacoffee.com/neatnettech)

**Private by default. Shared by choice. No cloud required.**

A notes vault for two people. It lives on your iPhones, and nothing leaves them unless you send it.

No server. No account. No analytics. No automatic sync. Open source.

## What it is

* Two independent vaults, one per phone, joined by a single pairing
* Every note carries an explicit state: Private, Sealed, or Shared
* Sharing is an exchange: one encrypted file you hand over yourself, through AirDrop, Messages or Files
* Works fully offline. Pairing and exchange never need a network

## How an exchange works

1. **Store.** Notes stay encrypted on your device.
2. **Seal.** Mark what your partner should have, then review exactly what leaves.
3. **Exchange.** One encrypted `.nvlt` file. Your partner reviews, then accepts. Import is atomic: all items land, or none do.

## Principles

* Nothing leaves a device unless its owner explicitly sends it
* Encryption happens before transport; the transport is never trusted
* No server dependency: there is no backend to breach or trust
* The exchange format is an open document, independent of the app's storage

## Security at a glance

* AES-GCM throughout: each record is encrypted at rest with a per device vault key, each exchange package is encrypted end to end with the couple's pair key
* Pairing: QR handoff plus a six digit verification code, compared in person
* Recovery: your partner holds an encrypted copy of your vault key, by design
* Honest limit: if both phones are lost and there is no backup, the data is gone. We cannot restore it, because we never had it

## Threat model

Protects against: a lost or stolen locked device, intercepted or tampered exchange files, wrong recipient, replay and duplicate imports.

Does not protect against: a fully compromised iOS installation, someone who knows your vault passcode, your partner (who can recover your vault by design), screenshots taken by the recipient.

## Protocol

The exchange package is a versioned format (`protocol_version = 1`). The full PROTOCOL.md specification ships with the first app release.

## Repository layout

* `web/` the website and waiting list
* `ios/` the iOS app (xcodegen project, SwiftUI, SwiftData)
* `.github/workflows/` deploys `web/` to GitHub Pages

Detailed specs and design files stay private and local, outside this repository.

## Status

In development. Website and waiting list: [Between Vault](https://neatnettech.github.io/between-vault/).

## Contributing

`main` is the trunk. Work on short lived `feat/`, `fix/` or `chore/` branches and
merge through a pull request with CI green. Releases are cut by tagging
`vX.Y.Z-rc.N` first, then promoting the accepted candidate to `vX.Y.Z` on the same
commit. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full flow and the local
setup.

Found a security problem? Please report it privately. See [SECURITY.md](SECURITY.md).

Like the project? [Buy me a coffee](https://buymeacoffee.com/neatnettech) or [sponsor on GitHub](https://github.com/sponsors/neatnettech).

## License

GPLv3. See [LICENSE](LICENSE).
