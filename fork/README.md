# Fork-Only Publication Assets

Keep publication-only material here so it can be excluded from upstream contributions:

- `docs/`: feature guide, commit ledger, showcase checklist, roadmap, contribution notes, and resource audit.
- `presets/`: reviewed example preferences for optional release assets.
- Future packaging scripts and showcase media should also live under this directory.

Application features stay in the existing DockDoor source locations. Excluding this directory does not make an arbitrary feature patch suitable for upstream; each contribution still needs its own scope, compatibility review, and testing. Omit the fork-specific root README introduction from those PRs too.

## Optional Showcase Preset

[DockFork-Showcase.json](presets/DockFork-Showcase.json) provides a sanitized example configuration. It is not the application's default configuration and must not be imported automatically. Attach this same JSON as a separate optional asset when creating the release; no release has been published yet.

To try it, first export your existing settings, then use **General > Backup & Restore > Import Settings** in the fork build. Import replaces the current preference domain rather than merging only the included settings, and the app asks to restart. Omitted settings return to their defaults. Use a separately identified DockFork build when packaging is ready; this preset alone does not isolate preferences from DockDoor.

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
