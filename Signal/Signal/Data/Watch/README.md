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

## Xcode target membership (human step)

1. In Xcode, select `Signal/Signal/Data/Watch/WatchPayload.swift`.
2. Enable **SignalWatch Watch App** and **SignalWatch Widget Extension** in Target Membership (in addition to Signal iOS and SignalWidget).
3. Enable **RecoveryWidgetSnapshot.swift** and **WatchPayloadCache.swift** for Signal iOS, SignalWidget, SignalWatch Watch App, and SignalWatch Widget Extension.
4. The watch folder may contain a **symlink** at `SignalWatch Watch App/WatchPayload.swift` pointing here so existing target references keep working. Do not maintain a second copy of the struct.

## App Group (human step, iOS Lock Screen widget)

1. Select the **Signal** target → Signing & Capabilities → **+ Capability** → App Groups.
2. Add `group.com.cameronro.signal`.
3. Repeat for the **SignalWidget** extension target (same group id).
4. `WatchConnectivityService` writes the latest plist-safe payload to this suite at push time; the Lock Screen widget reads it.

## WidgetKit extensions (human step)

1. **SignalWatch Widget Extension**: File → New Target → Widget Extension on watchOS, name `SignalWatch Widget Extension`. Add `RecoveryComplicationWidget.swift` to that target only. Remove the template `@main` if Xcode generates one.
2. **SignalWidget**: Add `SignalWidget/SignalRecoveryWidget.swift` to the existing empty SignalWidget target. Remove duplicate `@main` from any Xcode template.

The agent does not edit `.pbxproj`. After you add target membership, complications and the Lock Screen widget share the same `WatchPayload` as the watch app.
