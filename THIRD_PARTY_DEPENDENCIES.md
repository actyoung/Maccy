# Third-party dependencies

The local privacy build downloads eight Swift package source archives at exact
upstream revisions. Before extraction, each archive is verified against the
SHA-256 recorded in `scripts/bootstrap-local-dependencies.sh`.

Downloaded sources live under `.swiftpm-local/dependencies/`, which is ignored
by Git. The build does not resolve mutable package versions.

Two compatibility patches are applied:

- `Settings` excludes its localization resource bundle and uses static window
  labels so it can compile with the standalone Command Line Tools toolchain.
- `KeyboardShortcuts` excludes SwiftUI preview macros from Release builds made
  without Xcode.

For an offline build, set `MACCY_ARCHIVE_DIR` to a directory containing the
verified archives named `defaults.tar.gz`, `fuse-swift.tar.gz`,
`keyboardshortcuts.tar.gz`, `launchatlogin-modern.tar.gz`, `sauce.tar.gz`,
`settings.tar.gz`, `swift-log.tar.gz`, and `swifthexcolors.tar.gz`.
