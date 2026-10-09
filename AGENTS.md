# DockFork (DockDoor Fork)

macOS dock enhancement app — window previews on dock hover, Alt+Tab window switcher, Cmd+Tab overlay. Menu bar only (`LSUIElement: true`). Swift 5.10 / SwiftUI / AppKit. GPL-3.0.

## Before Doing Anything on GitHub

Read [CONTRIBUTING.md](CONTRIBUTING.md) before you open, edit or comment on a pull request, and follow it, including its "If you are an AI agent" section. PRs that ignore it are closed without discussion. The rules that agents break most often:

- Start every PR and issue body from its template in `.github/`. `gh pr create --body`, `gh pr create --fill` and `gh issue create --body` skip the templates.
- Fill in the AI disclosure. Don't tick checkboxes or write "Describe your changes" for your human.
- One issue per PR, with no unrelated changes.

These rules are for contributors. The maintainer (@ejbills) is exempt.

## Upstream PR Gate (Required)

**Never submit or merge the complete fork branch as an upstream PR.** Start a focused branch from current upstream and include only the agreed issue and its necessary dependencies.

- Exclude all of `fork/`, fork-specific changes to root `AGENTS.md` and `README.md`, local identity/signing configuration, private notes, and generated outputs.
- Do not cherry-pick mixed feature/fork-only commits wholesale. Extract the relevant changes without discarding required fixes.
- Keep upstream's README and agent instructions by default. Necessary upstream documentation and source registrations are allowed only within the agreed issue's scope, without fork branding or development configuration.
- **Review the complete final PR diff against its upstream base. Commit titles or a filtered commit list are not sufficient.**

Follow the detailed [upstream contribution checklist](fork/docs/UPSTREAM_CONTRIBUTIONS.md#fork-only-exclusions). These are PR exclusions, not instructions to delete files from the working fork or rewrite its history.

## Build

Requires Xcode 27 or later on macOS 27 or later. For this fork, use the included script from the repository root:

```sh
./fork/package.sh --dev
```

Build and relaunch after implementation changes unless the user explicitly says otherwise. This command builds Debug, signs with a local Apple Development certificate, gracefully replaces the running DockFork instance, and launches `fork/dist/dev/DockFork.app`. That location is gitignored. Verify the exact executable is running; do not launch older builds from other folders. Do not use computer-use automation for builds.

Keep application identity and signing configuration in the fork build script rather than modifying the source project. The script applies DockFork identity in an isolated build snapshot. Preserve existing preferences and permissions. Certificate selection and limitations are documented in [fork/README.md](fork/README.md#stable-local-development-build).

The development script includes tracked working-tree source changes but excludes untracked files and project-file changes. Flag that limitation when adding source files or project registrations rather than silently testing an incomplete snapshot.

For release packaging, use `./fork/package.sh` separately. Release mode builds committed sources, uses ad-hoc signing, and does not install or launch the app. Do not distribute development builds.

Upstream contributions still require the upstream Xcode validation workflow. Exclude these fork-specific build instructions from upstream PRs and follow [fork/docs/UPSTREAM_CONTRIBUTIONS.md](fork/docs/UPSTREAM_CONTRIBUTIONS.md).

## Adding Files to the Project

Every new `.swift` file must be registered in `DockDoor.xcodeproj/project.pbxproj`:

1. Generate two UUIDs: `for i in 1 2; do uuidgen | tr -d '-'; done`
2. Add a `PBXFileReference` entry
3. Add a `PBXBuildFile` entry referencing it
4. Add the file ref to the correct `PBXGroup`
5. Add the build file to `PBXSourcesBuildPhase`

## Adding Settings

All user preferences are declared in `consts.swift` under `extension Defaults.Keys`.

**Every new setting must be indexed in the search system:**

1. Add a `.settingsSearchTarget("tab.settingName")` modifier to the control in the view:
   ```swift
   Toggle(isOn: $mySetting) {
       Text("My Setting")
   }
   .settingsSearchTarget("general.mySetting")
   ```

2. Add a catalog entry in `Views/Settings/Search/SettingsSearchCatalog.swift`:
   ```swift
   SettingsSearchItem(
       id: "general.mySetting",          // must match the search target
       title: String(localized: "My Setting"), // exact string from the view
       description: String(localized: "Optional description text"),
       keywords: ["internal", "search", "tokens"],
       tab: "General",                   // matches sidebar tab tag
       section: String(localized: "Section Header"),
       icon: "sf.symbol.name"
   )
   ```

3. If adding a new settings tab, also update `SettingsSearchEngine.swift` — add to `tabDisplayOrder` and `tabDisplayNames`.

### Rules

- `title` and `description` use `String(localized:)` with the **exact same literal** as the view — reuses existing translations
- `keywords` are internal English tokens only (not translated, not displayed)
- The `id` must match between the catalog entry and `.settingsSearchTarget()` call

## Localization

- Use `String(localized:comment:)` for user-facing strings
- Do not edit `Localizable.xcstrings` directly — managed via Crowdin
- macOS 13.0 minimum — use single-parameter `onChange { newValue in }` form

## Code Style

- No verbose comments — only comment non-obvious logic
- No doc comments unless the API is public and non-obvious
- UI state belongs in coordinators, not views
- Window operations go through `WindowUtil` static methods
- Reusable settings UI goes in `Views/Settings/Shared Components/`

## Key Files

| File | Purpose |
|------|---------|
| `consts.swift` | All user preference keys |
| `WindowUtil.swift` | Window discovery/manipulation (Accessibility APIs) |
| `DockObserver.swift` | Dock hover detection and event routing |
| `SharedPreviewWindowCoordinator.swift` | Preview panel lifecycle |
| `Views/Settings/Search/SettingsSearchCatalog.swift` | Settings search index |
