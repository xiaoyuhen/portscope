# Contributing to PortScope

Thanks for looking. This is a small, opinionated tool; the fastest way to get a
change in is to match what is already there.

## Before you start

- **Bugs**: open an issue with your macOS version, what you expected, and what
  happened. If the app misidentified a service, include the output of
  `PortScope --list` — that is the same data the UI shows.
- **Features**: open an issue first. PortScope is deliberately small; "what is
  this port" and "stop it" are the whole product, and a feature that widens that
  needs a conversation before code.
- **Security**: do not open a public issue. See [SECURITY.md](SECURITY.md).

## Building

```bash
git clone https://github.com/xiaoyuhen/portscope.git
cd portscope
./scripts/build.sh
open dist/PortScope.app
```

Xcode is **not** required — Apple's Command Line Tools are enough. Several
SwiftUI APIs behave differently without it; see the toolchain notes in the
[README](README.md#toolchain-notes) before assuming a view is broken.

## Before opening a pull request

Run all three. The first two must pass; the third needs Accessibility
permission for your terminal and a GUI session.

```bash
swift build
PortScope --selftest              # logic checks, exit 1 on failure
./scripts/validate.sh             # 20 UI checks, drives the real app
```

If you changed the scanner or the identifier, also run the compatibility
matrix:

```bash
./scripts/compat/fixtures.sh      # starts real servers, stops them through PortScope
```

CI runs the build, the self-tests, the compatibility matrix, the bundle
verification and the lint job. It does not run `validate.sh` — a CI runner has
no GUI session to drive — so run that one yourself if you touched the window,
the menu bar or the language path.

## Style

- **Comments explain why.** The code says what it does; a comment that repeats
  it is noise. The ones worth writing record a decision, a constraint, or a
  thing that surprised you. Several existing comments exist because a piece of
  code looked wrong until the reason was written down.
- **No new dependencies.** The engine uses only the standard library and
  Darwin. That is what makes the app a 4 MB download that builds with CLT.
- **Localization.** Any new user-facing string needs a key in both
  `en.lproj/Localizable.strings` and `zh-Hans.lproj/Localizable.strings`. CI
  fails if they disagree.
- **Tests.** Logic goes in `Sources/PortScopeKit/SelfTest/`. If you fix a bug,
  add the check that would have caught it — every bug in this project's history
  has one now.

## Commits

- English, imperative mood, one logical change per commit.
- Explain *why* in the body when the change is not obvious from the diff.
- Link the issue when there is one.

## Releasing

Maintainer only. Bump `VERSION`, then:

```bash
git tag -a v0.2.0 -m "What changed in this release"
git push origin v0.2.0
```

The release workflow builds, tests, packages and publishes it.
