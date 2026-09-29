# Security policy

Between Vault stores personal information and encrypts it on device. Please treat
security reports seriously, and we will do the same.

## Reporting a vulnerability

**Do not open a public issue for a security problem.**

Report privately through GitHub:

1. Go to the [Security tab](https://github.com/neatnettech/between-vault/security/advisories/new)
2. Open a draft security advisory

That channel is private between you and the maintainers until a fix is published.

Please include:

* what the problem is, and what an attacker gains
* the steps to reproduce it
* the app version or commit, and the iOS version
* anything you already tried that did not work

You will get a first response within seven days. If the report is confirmed, we
will agree a disclosure date with you and credit you in the advisory unless you
prefer otherwise.

## Scope

In scope:

* the exchange protocol and the `.nvlt` package format
* the crypto core: key derivation, AES-GCM usage, the pairing code
* key storage and the Keychain configuration
* the lock screen, the privacy overlay, and anything that leaks vault contents
* anything that causes a vault to be readable by someone who is not the owner or
  their paired partner

Out of scope:

* attacks that need an unlocked, physically held device that is already yours
* the website, which stores nothing but forwards email addresses to Buttondown
* social engineering of the app's users
* the paired partner reading what you deliberately sent them, which is the
  product working as designed

## What this app deliberately does not protect against

These are documented design decisions, not vulnerabilities:

* **Your partner can recover your vault.** Pairing grants that by design. It is
  stated plainly in the app and on the website.
* **No cloud backup.** The app never uploads your vault. An iPhone backup can
  hold the encrypted store but not the vault key, so on its own it cannot be
  opened. Lose both phones without a backup export and the data is gone. There
  is no server to recover it from and no account to reset.
* **A compromised device.** If iOS itself is compromised, or the device is
  jailbroken, the vault key is reachable once the device is unlocked.

## Supported versions

The app has not shipped yet. Until the first release, the supported version is
whatever is on `main`.
