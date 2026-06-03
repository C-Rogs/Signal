# Watch shared types

`WatchPayload.swift` in this folder is the single source of truth for the iPhone-to-Watch recovery DTO (watch-safe; no iOS-only types).

`WatchPayload+Signal.swift` adds iOS-only encoding and `RecoveryScore` mapping. Add it only to the main Signal target, not the watch target.

## Xcode target membership (human step)

1. In Xcode, select `Signal/Signal/Data/Watch/WatchPayload.swift`.
2. Enable **SignalWatch Watch App** in Target Membership (in addition to the main Signal iOS target).
3. The watch folder may contain a **symlink** at `SignalWatch Watch App/WatchPayload.swift` pointing here so existing target references keep working. Do not maintain a second copy of the struct.

The agent does not edit `.pbxproj`. After you add target membership, the watch app should import the shared struct from this path only.
