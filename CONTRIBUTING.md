# Contributing

Thanks for looking. This is a small, opinionated app, so the fastest way to get a
change merged is to open an issue first and agree on the shape of it.

## Getting set up

You need macOS with Xcode 16 or newer, and [xcodegen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
cd ios
xcodegen generate
open BetweenVault.xcodeproj
```

`ios/project.yml` is the source of truth for the Xcode project. The generated
`BetweenVault.xcodeproj/project.pbxproj` is committed so that a fresh clone opens
without extra tooling. **If you add, move or delete a file, run `xcodegen generate`
and commit the regenerated project.** CI fails if the committed project does not
match what `project.yml` produces.

Run the tests from the command line with:

```sh
cd ios
xcodebuild test \
  -project BetweenVault.xcodeproj \
  -scheme BetweenVault \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Branching

`main` is the trunk and is always releasable. Work happens on short lived branches
that are merged back through a pull request. Avoid long running branches.

Name branches by intent:

| Prefix | For |
|---|---|
| `feat/` | a new capability |
| `fix/` | a bug fix |
| `chore/` | tooling, CI, dependencies, housekeeping |
| `docs/` | documentation only |
| `refactor/` | behaviour preserving restructuring |
| `test/` | tests only |

## Pull requests

* Keep them small and focused on one thing.
* CI must be green. It builds, checks the project file is current, and runs the
  full test suite.
* New logic needs a test. The suite uses
  [swift-testing](https://github.com/swiftlang/swift-testing), not XCTest, so
  write `@Test` functions with `#expect`, matching the existing files under
  `ios/BetweenVaultTests`.
* Do not add third party dependencies without discussing it first. The app
  currently has none, and that is deliberate for an app that handles private data.

## Releases

Semantic versions are tagged on `main`. Tags are the build trigger.

1. Merge to `main`.
2. Set `MARKETING_VERSION` in `ios/project.yml` to the version you are releasing.
   The release workflow fails if the tag and that value disagree.
3. Tag a release candidate: `vX.Y.Z-rc.1`. This drafts a prerelease with an
   unsigned archive attached.
4. Test it. If it needs fixes, land them and tag `-rc.2`, `-rc.3` and so on.
5. When a candidate is accepted, tag **that same commit** `vX.Y.Z`.

A production tag is rejected by CI unless a matching `-rc.*` tag already points at
the same commit. Never tag a release version without a preceding accepted
candidate.

```sh
git tag v1.0.0-rc.1 && git push origin v1.0.0-rc.1
# once accepted, on the same commit:
git tag v1.0.0 && git push origin v1.0.0
```

## Design

The UI follows a design handoff. Design tokens live in
`ios/BetweenVault/Design/Theme.swift` and the shared components in
`Components.swift`. Use the tokens rather than literal colours, spacing or font
sizes, and keep Dynamic Type working: prefer the semantic font styles, and use
`@ScaledMetric` where a size has no semantic equivalent.

State badges must always show an icon and a word, never colour alone, so they stay
readable in grayscale and for colourblind users.

## Security

Please do not open a public issue for a security problem. See [SECURITY.md](SECURITY.md).

## Licence

By contributing you agree that your contributions are licensed under the GPLv3,
the same licence as the project.
