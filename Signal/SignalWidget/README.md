# SignalWidget (iPhone Lock Screen)

Recovery score + HRV band on the Lock Screen and Home Screen. **No watch required** to develop or test this.

## Xcode target

The **SignalWidgetExtension** target is in the project (embedded in Signal). Bundle ID: `com.cameronro.Signal.SignalWidget`. Shared types are symlinks into `Signal/Data/Watch/`.

**Agent:** edit `project.pbxproj` and entitlements when setup or target membership is required. Follow `.cursor/rules/xcode-project-setup.mdc`. Verify with `build_device`.

If you recreate the target:

1. File → New Target → Widget Extension (iOS), name `SignalWidget`, uncheck Configuration App Intent.
2. Delete the Xcode template widget file if it duplicates `@main`.
3. Add these files to the **SignalWidget** target:
   - `SignalWidget/SignalRecoveryWidget.swift`
   - `Signal/Data/Watch/WatchPayload.swift`
   - `Signal/Data/Watch/RecoveryWidgetSnapshot.swift`
   - `Signal/Data/Watch/WatchPayloadCache.swift`
4. App Groups → `group.com.cameronro.signal` (same as main Signal target).
5. Build Settings → **Code Signing Entitlements** → `SignalWidget/SignalWidget.entitlements`.

Optional: add `Resources/Colors.xcassets` (Positive, Warning, Negative) to SignalWidget for Home Screen color tokens.

## How data flows

1. Dashboard loads → `WatchConnectivityService.push(score:)` runs.
2. **Always** writes App Group cache + reloads iOS widget (even if watch is offline).
3. SignalWidget timeline reads `WatchPayloadCache.readPayload()`.

## Test without reinstalling the watch

1. Run **Signal** to iPhone from Xcode (⌘R). Widget extension installs with the app.
2. Open **Dashboard**, pull to refresh.
3. Long-press Lock Screen → Customize → add **Recovery** widget.
4. Console filter: `category:watch` → look for `ios widget cache updated score=…`.

Watch complication is independent; you do not need to touch the watch for Lock Screen widget work.
