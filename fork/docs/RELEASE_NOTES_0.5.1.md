# DockFork 0.5.1 Release Record

Status: stable candidate built and verified locally. Awaiting manual testing and publication approval. DockFork 0.5.0 remains the latest published release.

## Candidate

- [Release notes](RELEASE_BODY_0.5.1.md), compared with published 0.5.0.
- Source: `fd6989d1f9104cdc6106ec5463d970c3dd6d6239`.
- Upstream: DockDoor 1.42.4, with the merged tip at `6d3c0db804bb4c5ef3ee1d2e31bfed2ec76b85a9`.
- Local output: `fork/dist/DockFork-fd6989d-cVwYq0`.
- Package: `DockFork-0.5.1-fd6989d-arm64.zip`.
- ZIP SHA-256: `f9d7676905a6e13b2dcd894ad57afaddbd749906ac82fb789fdf28ff4b0f6448`.
- Preset SHA-256: `8717867b9a0bdc3fdeb18d1d140354723ad2c9a71c5d22c57cfe308fba7e7ed0`.

The November 9 preset enables no initial highlight in persistent sessions and keeps the auto-hidden Dock visible during previews. It contains 271 preferences and 15 generic-ID shortcut rows, with assignments unchanged from 0.5.0. The original export and published presets are untouched.

## Verification

The Release build used committed source and the standard packaging overlay. ZIP integrity and all nine checksum entries pass. The extracted app matches the signed build across 220 bundle entries, including file contents, modes and symlinks. The main executable is arm64; all seven Mach-O files are ad-hoc signed and the extracted bundle passes strict signature verification. The version, bundle identity, source and upstream metadata match. Automatic updates are disabled; no upstream feed, development marker, coverage sections or checked private build paths are present.

The source archive matches Git's archive of the candidate commit. The overlay applies cleanly, and the preset, install guide, license and patch match the committed files. Focused search, keyboard, hover, Settings, quit policy, upstream integration and preset checks passed, as did all three packaging fixtures, SwiftFormat and diff checks.

Old development outputs were cleaned without replacing the installed development app or removing existing Release packages. No Release installation, launch, preference import, tag, push or publication was performed.

## Manual Checks Before Publication

- Test the exact ZIP: first launch, Gatekeeper approval, Accessibility and Screen Recording.
- Check the menu-bar icon's top and bottom edges and the initial highlight in a persistent session.
- Confirm that search clears without losing focus and fades without leaving a shadow.
- With Dock auto-hide on, open a Dock preview, then invoke Cmd+Tab. Confirm the Dock hides normally.

The app is not notarized. If testing the optional preset, export a backup first; import replaces settings.
