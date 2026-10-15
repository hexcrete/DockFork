# Installing DockFork

This Apple Silicon package is ad-hoc signed, not Developer ID signed or notarized. It contains no automatic updater. Download future versions manually from the fork's releases. Do not treat a successful code-signature verification as Apple approval or malware scanning.

1. Download the ZIP from the reviewed release and compare its SHA-256 with the published checksum. A checksum checks integrity, not trust in its publisher.
2. Unzip and move `DockFork.app` to Applications. Quit any other running DockDoor/DockFork instance first: separate identities do not prevent competing global shortcuts or Dock monitoring.
3. Open DockFork. macOS may block an unidentified or unnotarized application. If you trust this release, follow [Apple's documented Privacy & Security approval procedure](https://support.apple.com/en-us/102445). Do not disable Gatekeeper globally. Managed devices may prohibit approval.
4. Complete onboarding and grant Accessibility and Screen Recording permissions to DockFork, then restart when prompted. Calendar and Automation access may be requested when those features are used.
5. Configure your own preferences, or explicitly import the optional `DockFork-Showcase.json` after exporting any settings you want to preserve. Import replaces settings; it is not an automatic or partial merge.

## Identity and Isolation

- Application: `DockFork.app`; bundle ID and preference domain: `io.github.hexcrete.DockFork`.
- Diagnostics: `~/Library/Application Support/DockFork/Diagnostics`.
- Existing DockDoor preferences and diagnostics are not migrated or modified by packaging.
- The source project and Swift module retain DockDoor naming. Some inherited UI, scripting terminology, donation links, and acknowledgments still refer to the upstream project.
- AppleScript can address the installed app as `tell application "DockFork"`; existing command names and event codes are unchanged. Permission prompts and automation must be tested on the installed build.

## Upgrading and New Optional Features

Before replacing an installed version, export a settings backup and quit every running DockDoor/DockFork instance. Keep the DockFork name, bundle ID and installation path consistent. Existing DockFork preferences are not reset by packaging, but a rebuilt ad-hoc release can require granting permissions again.

The 0.2.0 feature set includes multi-window selection under **Keybinds > Window Selection & Tiling**. Selection and selection-driven keep-open behavior default Off. Show selection summary defaults On, but appears only after enabling selection and checking windows. Maximum tiling rows defaults to 2; columns defaults to 3. Drag-to-tile is a separate default-Off option under **Mouse Actions**. Installation does not enable these default-Off features. An optional preset can enable them, so review the supplied configuration before importing it; the preset is never applied automatically. Check the release notes for the version you actually downloaded; local development documentation does not establish that a package contains later features.

Support > Updates shows DockFork's own version and its incorporated DockDoor release/commit separately. `+ upstream changes` means the base includes commits after that release, not that newer upstream releases are automatically installed. `BUILD-METADATA.json` accompanies release assets with the full upstream and source hashes. These values describe the built package and require no online check.

A free Apple account is not needed for the ad-hoc build. It does not provide the Developer ID distribution identity used for ordinary notarized Mac releases. A later Developer ID/notarized release needs a separate signing and notarization workflow; switching signing identities can require users to grant permissions again. See [Apple's Developer ID guidance](https://developer.apple.com/developer-id/).

Ad-hoc signing ties the app's designated requirement to that particular build. Updating to a rebuilt release can therefore require granting permissions again even when its name and bundle ID are unchanged. Installing at a fixed path alone does not solve this. The certificate-signed `--dev` workflow is for local testing only, not distribution.

DockFork is GPL-3.0 software based on [DockDoor](https://github.com/ejbills/DockDoor). Release assets include the license, committed source archive, source commit, and packaging patch. Apply `DockFork.patch` to the unpacked source to reproduce the application overlay; the packaging script in the published repository also applies the identity and signing configuration. Publish the corresponding source and packaging files with the release; an app ZIP alone is not the source distribution.
