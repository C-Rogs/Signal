# Watch shared types

## Identifiers (signing)

| Kind | Value |
|------|--------|
| iOS app | `com.cameronro.Signal` |
| iOS widget | `com.cameronro.Signal.SignalWidget` |
| watch app | `com.cameronro.Signal.watchkitapp` |
| watch complication widget | `com.cameronro.Signal.watchkitapp.SignalWatch-Widget-Extension` |
| App Group (all targets above) | `group.com.cameronro.signal` |

Code: `SignalIdentifiers.swift`. Bundle IDs use capital **S**; the App Group uses lowercase **signal** on purpose.

`WatchPayload.swift` in this folder is the single source of truth for the iPhone-to-Watch recovery DTO (watch-safe; no iOS-only types).

`WatchPayload+Signal.swift` adds iOS-only encoding and `RecoveryScore` mapping. Add it only to the main Signal target, not the watch target.

`RecoveryWidgetSnapshot.swift` and `WatchPayloadCache.swift` are watch-safe display and App Group cache helpers. Add them to **SignalWidget**, **SignalWatch Widget Extension**, and **SignalWatch Watch App** as well as the main Signal target.

## Xcode target membership

Most watch Swift uses folder sync under `SignalWatch Watch App/`. Shared files in this folder may need explicit multi-target membership in `project.pbxproj`.

**Agent:** edit `project.pbxproj` when build fails on missing target membership. Follow `.cursor/rules/xcode-project-setup.mdc`. Verify with `build_device` and `./scripts/install-watch-app.sh` when watch or widget targets change.

1. `WatchPayload.swift`: Signal iOS, SignalWidget, SignalWatch Watch App, SignalWatch Widget Extension.
2. `RecoveryWidgetSnapshot.swift` and `WatchPayloadCache.swift`: same four targets.
3. The watch folder may contain a **symlink** at `SignalWatch Watch App/WatchPayload.swift` pointing here so existing target references keep working. Do not maintain a second copy of the struct.

## App Group

`group.com.cameronro.signal` must be on Signal, SignalWidget, watch app, and watch widget entitlements.

**Agent:** edit entitlements when capability is already on the team profile. **Human:** Apple Developer portal if provisioning blocks.

`WatchConnectivityService` writes the latest plist-safe payload to this suite at push time; the Lock Screen widget reads it.

## WidgetKit extensions

**Agent-owned** when milestone requires it:

1. **SignalWatch Widget Extension**: widget target on watchOS; `RecoveryComplicationWidget.swift` in that target only. Remove duplicate `@main` from Xcode templates.
2. **SignalWidget**: `SignalWidget/SignalRecoveryWidget.swift` in SignalWidget target. Remove duplicate `@main` from templates.

Log project edits in `AGENT-BUILD-UPDATES.md` under **Xcode project**.
