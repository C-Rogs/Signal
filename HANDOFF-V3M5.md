# V3 M5 handoff: Recovery on watch face + Lock Screen widget

## What shipped

- iPhone calls `transferCurrentComplicationUserInfo` after a successful `updateApplicationContext` push when `isComplicationEnabled` is true.
- watchOS WidgetKit complication source: circular + rectangular families, reads `WCSession.default.receivedApplicationContext`.
- iOS Lock Screen widget reads the same payload from App Group cache written when Dashboard loads (watch optional).
- Shared display logic in `RecoveryWidgetSnapshot.swift`; single DTO in `Data/Watch/WatchPayload.swift`.

## Human steps before Gate B

### 1. App Group

Signal target and SignalWidget target → Capabilities → App Groups → `group.com.cameronro.signal`.

### 2. SignalWatch Widget Extension target

File → New Target → Widget Extension (watchOS). Name: `SignalWatch Widget Extension`.

Add to that target:

- `SignalWatch Widget Extension/RecoveryComplicationWidget.swift`
- `Signal/Data/Watch/WatchPayload.swift`
- `Signal/Data/Watch/RecoveryWidgetSnapshot.swift`

Remove any duplicate `@main` from the Xcode template.

### 3. SignalWidget target

Add to existing SignalWidget target (or create via File → New Target → Widget Extension):

- `SignalWidget/SignalRecoveryWidget.swift`
- `SignalWidget/SignalWidget.entitlements` → Code Signing Entitlements
- `Signal/Data/Watch/WatchPayload.swift`
- `Signal/Data/Watch/RecoveryWidgetSnapshot.swift`
- `Signal/Data/Watch/WatchPayloadCache.swift`

Remove duplicate `@main` from template if present.

See `Signal/SignalWidget/README.md` for Lock Screen testing **without** reinstalling the watch.

## iPhone-only widget test (no watch reinstall)

1. Complete SignalWidget target setup above.
2. Run **Signal** to iPhone from Xcode (⌘R).
3. Open Dashboard, pull to refresh.
4. Lock Screen → Customize → add **Recovery** widget.
5. Console: `ios widget cache updated score=…` (written even when watch is offline).

## Install watch app (physical device, complication only)

After building Signal to iPhone from Xcode:

```bash
./scripts/install-watch-app.sh
```

Optional env overrides:

- `SIGNAL_IPHONE_DEVICE_ID` (default: paired iPhone UDID in script)
- `SIGNAL_WATCH_DEVICE_ID` (default: paired Watch UDID in script)
- `SIGNAL_DERIVED_DATA` if DerivedData path differs

## Gate B checklist (iPhone + Watch)

1. Build and run **Signal** on Cameron's iPhone from Xcode.
2. Run `./scripts/install-watch-app.sh` to install the embedded watch app.
3. Open **Signal Dashboard** on iPhone and wait for metrics to load.
4. On Apple Watch: long-press face → Edit → add **Signal** complication (circular or rectangular slot).
5. Confirm the score appears on the face without opening SignalWatch.
6. On iPhone Lock Screen: long-press → Customize → add **Signal Recovery** widget.

| Check | Pass |
|-------|------|
| Watch app score | Opens with number after Dashboard visit |
| Complication | Updates within ~1 min of Dashboard load |
| Lock Screen widget | Shows score after Dashboard load (iPhone Run only) |
| Console iPhone | `ios widget cache updated score=…`; watch lines optional |
| Console watch | `watch received context score=…` |

Console filter: `category:watch`

## Gate A (agent)

```bash
./scripts/build-and-test.sh
```

Focused:

```bash
xcodebuild -scheme Signal -destination 'platform=iOS Simulator,id=20DDD35B-812A-49BE-9DCF-0685401ACC15' test -only-testing:SignalTests/WatchPayloadTests
```

Widget extension targets are not required for Gate A; logic tests cover `WatchPayload` and `RecoveryWidgetSnapshot` only.

## Files created or modified

| Path | Role |
|------|------|
| `Signal/Data/Watch/WatchConnectivityService.swift` | Complication push, App Group cache, widget reload |
| `Signal/Data/Watch/RecoveryWidgetSnapshot.swift` | Shared widget display snapshot |
| `Signal/Data/Watch/WatchPayloadCache.swift` | App Group read/write |
| `SignalWatch Widget Extension/RecoveryComplicationWidget.swift` | watchOS complication |
| `SignalWidget/SignalRecoveryWidget.swift` | iOS Lock Screen widget |
| `SignalTests/WatchPayloadTests.swift` | Snapshot + payload tests |
| `scripts/install-watch-app.sh` | Device watch install helper |
