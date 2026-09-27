# Design Handoff: Website + iOS App

**For:** the design agent
**Source of truth:** SYSTEM_SPEC.md (read sections 2, 5, 8, 13, 18, 20, 28, 30 before starting)
**Status:** approved direction, ready to execute
**Scope:** one brand, two surfaces: a static website (waiting list) and the iOS app UI. Shared tokens, shared copy, shared principles.

---

# Part A: Brand (applies to both surfaces)

## A1. Voice

Calm, direct, factual. Written like a careful engineer, not a marketer.

* Promise line (the brand line): "Private by default. Shared by choice. No cloud required."
* Banned words (from spec section 30): "100% secure", "unhackable", "military grade", "anonymous".
* Approved vocabulary: "No cloud storage", "No automatic synchronization", "End to end encrypted exchange", "Stored locally on your device", "You control when information is shared", "Your partner can recover your vault by design".
* Honesty is a feature: limitations are stated plainly (both phones lost with no backup means data is gone).

## A2. Shared tokens

* Product name: TBD. Working name "Private Couple Vault". All designs must keep the wordmark trivially changeable.
* Accent color: one, used sparingly. Deep teal. No red, no hacker green.
* Neutral palette: near white background, near black text, one mid gray for secondary.
* Dark mode: supported on both surfaces via system preference.
* Type: system stacks only. Web: `-apple-system, "SF Pro", "Segoe UI", "Helvetica Neue", Arial, sans-serif`. iOS: SF Pro, with SF rounded or New York allowed for hero moments only. No third party fonts, ever.
* State badge language (app only, but consistent meaning): Private = neutral gray, Sealed = amber, Shared = teal.

## A3. Shared copy deck

Deliver one strings file usable by both surfaces containing at minimum: the promise line, the three trust pillars, the three steps, pricing copy, FAQ, and app onboarding copy. English only. Strings centralized for future localization.

---

# Part B: Website (waiting list)

## B1. Goal

Measure interest. Collect emails into a waiting list. Link the repo and threat model. Success metric: signups, nothing else.

## B2. Hard constraints

1. **No analytics, no trackers, no cookies, no third party requests.** System fonts only, no captcha, no social embeds, no CDN. The page itself proves the claim: "this page makes zero third party requests."
2. **Static HTML + CSS.** JS only for the form embed. No framework, no bundler.
3. **GitHub Pages** deployable, all relative links.
4. **Privacy policy page required** (email collection means GDPR/CCPA consent).
5. **Honest pricing copy:** app is free, one $9.99 one time unlock for attachments, GPLv3 means the code is free. Say so.

## B3. Page structure

```text
1. Header: wordmark + [GitHub] + [Join the waiting list]
2. Hero: name, promise line, email field + [Get early access],
   secondary: "Free. Open source. No cloud."
3. Trust strip: No cloud. No account. No analytics.
   End to end encrypted exchange. Open source (GPLv3), verifiable code.
4. What it is: two sentences from the spec vision.
5. How it works: Store. Seal. Exchange. (three steps, one line each)
6. Why it is different: factual list, no competitor names,
   includes the plain statement about data loss limits
7. Pricing: Free: notes, pairing, exchange, backup, forever.
   One time $9.99: attachments. Pays for updates and publishing.
8. Open source callout: GPLv3, repo link, PROTOCOL.md, "audits welcome"
9. FAQ: five questions (no server, lost phone, why open source,
   launch date, do you track me: "not even on this website")
10. Final CTA: email + button
11. Footer: privacy policy, license, threat model
```

## B4. Visual direction

* Mood references: signal.org, standardnotes.com, strongboxsafe.com, proton.me. Calm, not hype.
* Single column, max width around 720px, centered. A letter, not a dashboard.
* No gradients, no 3D, no stock photos of couples. Optional monochrome schematic of the exchange flow.
* Headline: serif (system New York/Georgia) allowed, body sans.
* Contrast AA minimum, one h1, semantic landmarks, focus states, visible form errors.

## B5. Waiting list

* Recommended provider: **Buttondown** (privacy friendly, tracking can be disabled). Alternative: **Tally.so**.
* Form: email only, unchecked consent checkbox linking the privacy policy, no captcha, POST submission.

## B6. Privacy policy page

Collects: email only. Purpose: launch notifications only. Processor: named provider. No cookies, no analytics, no pixels. Data never connected to the app (the app collects nothing). Deletion on request. Plain language, no boilerplate padding.

---

# Part C: iOS App Design Handoff

## C1. Platform baseline

* iOS 17 minimum, SwiftUI, SF Symbols
* Dark mode first class, Dynamic Type to accessibility sizes
* The privacy promise must be visible in the UI, not just the marketing

## C2. Navigation

```text
TabView
├── Vault
├── Exchange
├── Partner
└── Settings
```

## C3. Screen inventory

```text
1.  Lock screen (Face ID prompt, passcode fallback, privacy blurred)
2.  Onboarding (3 screens max: promise, no cloud, your data yours)
    then create vault + biometric opt in
3.  Vault home: category tiles + state filter chips
4.  Category list: notes in a category
5.  Note detail: title, body, state badge, seal/share actions
6.  Note editor: title + body, category picker, state control
7.  Outbox ("Ready to send"): sealed items + [Review] + [Encrypt & Share]
8.  Review sheet: exactly what leaves the device, [Cancel] prominent
9.  Inbox ("Waiting for me"): incoming package, [Review] + [Accept]
10. Conflict sheet: [Keep mine] [Keep partner's] [Keep both as copy]
11. Pairing A: [Pair with Partner] -> QR display
12. Pairing B: scanner -> six digit code display
13. Code verify: both devices show 481 923, [Confirm]
14. Partner profile: fingerprint display, trust statement,
    recovery export, unpair (destructive, double confirm)
15. Recovery: new device flow (pair again, import blob from partner)
16. Paywall (1.1): attachments unlock, honest copy, Family Sharing note
17. Settings: lock timeout, clipboard auto clear, backup export (1.1),
    unlock (1.1), privacy policy, threat model, about/license
18. Exchange history ("Recently exchanged"): sent/received log, no content
```

## C4. Core flows (design these as diagrams, then as screens)

### Pairing

```text
A: Partner tab -> Pair -> QR shown
B: Partner tab -> Scan -> reads QR -> code shown on both
Both confirm matching six digits
B shows return QR -> A scans -> relationship established
```

### Sending an exchange

```text
Note detail -> Seal (state -> sealed)
Exchange tab -> Ready to send -> Review -> Encrypt & Share
-> system share sheet (.nvlt file via AirDrop/Messages/Files)
-> item becomes Shared
```

### Receiving an exchange

```text
Tap .nvlt file -> app opens -> Review (decrypted titles, count)
-> Accept -> atomic import -> conflicts if any -> history entry
```

### Conflict

```text
Conflict sheet per diverged item, all three options visible,
"keep both" creates a copy named clearly, nothing silently discarded
```

### Recovery (new phone)

```text
Install -> fresh identity -> Pair with partner (new pairKey)
-> Partner exports your recovery blob
-> import on new phone -> vault unlocked
```

## C5. Component library (deliver as named components)

* NoteRow: title, two line preview, state badge, relative date
* StateBadge: Private (gray, lock), Sealed (amber, envelope), Shared (teal, two persons)
* CategoryTile: icon + name + count
* PrimaryButton / DestructiveButton (unpair, clear clipboard confirm)
* CodeDisplay: six digits, grouped 3+3, monospaced, large
* ReviewRow: name + category, used in send and import review
* PrivacyOverlay: full blur + lock glyph, shown on backgrounding (design it, the app implements it)
* EmptyStates: for empty inbox and outbox, friendly one liners
* Toast copy: "Exchange ready", "3 items imported", never content previews

## C6. Typography and color

* SF Pro throughout. LargeTitle 34 / Title2 22 / Title3 20 / Body 17 / Footnote 13.
* Vault content text is user content, never resized or stylized aggressively.
* Light: system background, near black primary text, teal accent.
* Dark: same tokens flipped, teal accent brightened one step.
* Badge colors must work in grayscale (VoiceOver + colorblind): add icons, not color only.

## C7. App icon direction

* Flat, single glyph, dark background, no text, no photo.
* Direction options: two interlocking rounded shapes (the couple, the shared space), or a vault door with a single keyhole. Avoid the padlock cliché and anything heart shaped.
* Must read at 1024px and at 29px badge size.

## C8. Accessibility minimum

* VoiceOver labels on all state badges, buttons, and the pairing code
* Dynamic Type to XXXL without truncating the code display
* contrast AA everywhere, including dark mode badges
* Reduce Motion: no decorative animation anywhere anyway
* Haptics: success on import, warning on conflict, confirmation on unpair

## C9. Copy notes (app)

* Onboarding must state the three invariants in plain language, no jargon.
* Pairing screen states the trust model openly: "Your partner can recover your vault. This is by design."
* Exchange review states counts and names, never contents of body text.
* Paywall copy: "Attachments unlock. One time. Pays for updates and publishing. The code is free (GPLv3)."
* Settings includes the threat model link and license page.

---

# Part D: Shared Deliverables Checklist

1. Brand tokens file: colors, type scale, spacing, wordmark (web + app, one source)
2. Shared copy deck (English strings)
3. Website: `index.html`, `privacy.html`, `styles.css`, zero third party requests, 320px to desktop
4. App: complete screen inventory (18 screens), component library, 4 flow diagrams, paywall design
5. App icon concept, exported test renders at 1024 and 29px
6. Accessibility pass on both surfaces (contrast, labels, focus)
7. Everything text based stays in plain text formats (CSS, strings, markdown), no proprietary file formats required to review

## Out of scope

* blog, changelog, docs site, multi language, custom domain, SEO beyond basic meta tags
* screenshot gallery until the app exists
