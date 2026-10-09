# Fork-Only Publication Assets

Keep publication-only material here so it can be excluded from upstream contributions:

- `docs/`: feature guide, commit ledger, showcase checklist, roadmap, contribution notes, and resource audit.
- `presets/`: reviewed example preferences for optional release assets.
- `package.sh` and `packaging/`: isolated DockFork packaging and installation instructions.
- `dist/`: ignored local package outputs. Future showcase media should also live under this directory.

Application features stay in the existing DockDoor source locations. Excluding this directory does not make an arbitrary feature patch suitable for upstream; each contribution still needs its own scope, compatibility review, and testing. Omit the fork-specific root README introduction from those PRs too.

## Build a DockFork Package

The packaging script is a fork-only CLI distribution workflow, not a replacement for upstream's Xcode development instructions. Building requires macOS 27 and Xcode 27 or later, with Xcode selected as the active developer directory. Initial dependency resolution requires network access. No Apple account is required for this ad-hoc-signing workflow.

```sh
./fork/package.sh
# Optional release version override:
./fork/package.sh --version 1.0.0
# Inspect the isolated source overlay without building:
./fork/package.sh --prepare-only
# Local testing of tracked, uncommitted source changes (not a release):
./fork/package.sh --include-working-tree
```

By default the script uses **committed HEAD**, not uncommitted application changes or the local Dev project identity. `--include-working-tree` is an explicit local-test exception: it applies tracked changes in `DockDoor`, `Assets`, `BuildTools`, and `DockDoorTests`, records them in `WORKING-TREE.patch`, and labels the output `working`. It excludes untracked files and project-file changes. Do not publish these test builds; commit reviewed changes and rebuild normally for release. The script reads the packaging patch, entitlements, installation guide, and optional preset from this checkout. Commit and review those assets before publishing a release. A future upstream change that invalidates the overlay stops packaging rather than silently skipping it.

Each invocation creates a unique directory under `fork/dist/` (or `--output DIRECTORY`). Temporary build sources and derived data are deleted afterward. The original project is not edited. Packaging does not install, launch, import preferences, publish, or push anything.

The resulting app uses `DockFork.app`, executable `DockFork`, and bundle/preference identity `io.github.hexcrete.DockFork`. Its Swift module and scripting command names remain DockDoor-compatible. The overlay disables Sparkle construction and replaces update checks with manual fork-release downloads; upstream feed/signing keys are removed. Diagnostics use a separate DockFork directory. See [installation and signing limitations](packaging/INSTALL.md).

### Window State and Spaces Defaults

The application's preference declarations supply these defaults for the added features in both DockDoor and DockFork builds, with existing preference key names unchanged:

- Dock, Window Switcher, and Cmd+Tab: window state/Space indicator dock styling enabled; swap with traffic lights enabled, limited to Compact Mode.
- Spaces dropdown: show the Current badge and unavailable Spaces.

These are fallbacks for unset preferences, not a migration or forced configuration. Saved or imported choices take precedence; resetting the corresponding settings restores these defaults. The packaging overlay does not override them.

### Stable Local Development Build

```sh
./fork/package.sh --dev
# If multiple Apple Development certificates are available:
./fork/package.sh --dev --signing-identity CERTIFICATE_SHA1
```

This local-only mode builds Debug with tracked working-tree source changes and uses your installed Apple Development certificate. With exactly one valid development identity, selection is automatic; otherwise select its SHA-1 from `security find-identity -v -p codesigning`. No account name or certificate fingerprint is stored in tracked files, and no certificates or private keys are exported. macOS may request access to the signing key.

After successful build and signature verification, the script gracefully quits any running DockFork instance, replaces `fork/dist/dev/DockFork.app`, and launches that fixed app path. It does not quit DockDoor, clear preferences, or modify the source project. The whole `fork/dist/` directory is gitignored. Quit DockDoor yourself if it is running, to avoid competing shortcuts.

Changing from ad-hoc signing may require granting permissions once again. Later builds should retain them while the signing certificate, designated requirement, bundle ID, and installed path remain compatible. Replacing or expiring the certificate, changing identity, or returning to an ad-hoc package can require approval again. A development certificate is not Developer ID distribution signing or notarization.

Development mode creates no release ZIP and must not be distributed; its signature identifies your development account. Run the ordinary packaging command separately for the initial ad-hoc release workflow.

The local Debug build, nested certificate-signature checks, fixed-path replacement, and launch have passed. Its designated requirement is certificate-based, not tied to a binary hash. Permission retention across subsequent builds still needs verification after granting access to this signed build.

### Release Assets and Validation

Publish these together after testing the package:

- `DockFork-<version>-<commit>-arm64.zip`: ad-hoc-signed Apple Silicon app.
- `DockFork-<commit>-source.tar.gz`, `DockFork.patch`, and `SOURCE-COMMIT.txt`: exact committed source and the applied overlay.
- `INSTALL.md`, `LICENSE`, `SHA256SUMS.txt`, and `PACKAGING-PATCH-SHA256.txt`.
- `DockFork-Showcase.json`: optional preferences, never automatically imported.

Keep `build.log` local: it can contain developer paths and is not a release asset. Do not publish the entire output directory indiscriminately. A successful signature verification establishes package integrity, not Developer ID trust or notarization.

Before release, quit the Dev instance and test DockFork's fresh permissions, independent preferences, all three preview modes, shortcuts, widgets, diagnostics export, and `tell application "DockFork"` scripting. Verify the update button opens the fork releases rather than upstream. Test the downloaded/quarantined ZIP on another Mac as well. Building with a macOS 13 deployment target does not itself prove compatibility with macOS 13; supported versions require runtime testing.

No release has been published. Source-only preparation, the complete Release build, nested ad-hoc signature verification, ZIP integrity, checksums, and local launch have passed. Manual feature testing and downloaded/quarantined installation validation remain pending.

## Optional Showcase Preset

[DockFork-Showcase.json](presets/DockFork-Showcase.json) provides a sanitized example configuration. It is not the application's default configuration and must not be imported automatically. Attach this same JSON as a separate optional asset when creating the release; no release has been published yet.

To try it, first export your existing settings, then use **General > Backup & Restore > Import Settings** in the fork build. Import replaces the current preference domain rather than merging only the included settings, and the app asks to restart. Omitted settings return to their defaults. Use a separately identified DockFork build; this preset alone does not isolate preferences from DockDoor.

### Privacy Review

The sanitized preset retains 234 recognized preference keys from the supplied export. Review included nested JSON stored inside shortcut strings, not just the outer JSON.

- Removed 36 private-state, system, updater, or obsolete keys, including saved window order, folder-specific sort dictionaries, the saved-directory bookmark, permission/UI-state flags, and system window geometry.
- Removed the exact export timestamp. Retained the nonpersonal format identifier and application version used for compatibility information.
- Replaced 15 original shortcut-row UUIDs with generic stable IDs; key combinations, actions, and scopes are unchanged.
- Set debug logging off instead of carrying over the development logging choice.
- Retained the generic `launched: true` flag to avoid replaying first-run onboarding after import. It contains no identifying information and does not grant macOS permissions; permission history remains excluded.
- No remaining file paths, bookmarks, binary payloads, account identifiers, email addresses, URLs, or window titles were found in the prepared preset.

The envelope intentionally retains `"app": "DockDoor"` because the current importer requires that marker. It does not select the destination preference domain or change the installed application's identity.

### Behavior to Review Before Importing

This is an opinionated showcase configuration, not a recommended setup for everyone. In particular, it configures Left Option + Tab, side-specific Command double taps, preview action shortcuts (including Close and Quit), numbered Spaces shortcuts, and trackpad swipe launching. Review **Gestures & Keybinds** after import and resolve conflicts with macOS gestures or other applications. Some appearance choices use newer macOS capabilities; results can differ by system version, display configuration, and Reduce Motion settings.

Privacy and import-format checks do not prove every interaction is appropriate on another person's Mac. Re-exported preferences must be reviewed again before publication: exports can include new private state and system metadata.
