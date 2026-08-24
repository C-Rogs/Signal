# Builder handoff: Custom numpad (live workout blank after typing)

**Date:** 2026-07-05  
**Priority:** Gate B blocker (only remaining Train blank repro per human verify)  
**Depends on:** `HANDOFF-HK-WORKOUT-TEARDOWN.md` (HK await-stop + wellness dismiss shipped)

---

## Human verify (2026-07-05 evening)

| Repro | Status |
|-------|--------|
| Complete set with **pre-filled** weight/reps (no editor / no typing) | **PASS** |
| Wellness finish (Save / Skip; swipe fix shipped) | **PASS** |
| Open weight/reps sheet, **type a digit**, then home or continue workout | **FAIL** (blank as before) |

**Conclusion:** System `decimalPad` / `numberPad` on `SetValueEditorSheet` is the remaining trigger. Keyboard dismiss on background was not enough.

---

## Problem

`SetValueEditorSheet` uses `TextField` + `@FocusState` + `.keyboardType(.decimalPad|.numberPad)`. iOS attaches UIKit keyboard (`KeyboardArbiter`, `keyboardFocus` deferring). Background or return with that keyboard active leaves workout overlay / main tab unpainted (same pid; not jetsam).

Console evidence: `drafts/console-capture-20260705-212450.log` (`keyboardFocus` detach on pid 7800 at background).

Pre-filled path works because user can mark set complete **without opening** the value editor sheet.

---

## Required fix: in-app numpad (no system keyboard)

Replace system keyboard with SwiftUI-only digit entry. Strong/Hevy pattern.

### Do

1. **`TrainNumpadView`** (new, under `Signal/Signal/Features/Train/`):
   - Props: `allowsDecimal: Bool`, `displayText: String` (binding or callback), optional max length.
   - Buttons: 0-9, decimal (only if `allowsDecimal`), backspace, clear optional.
   - Large display line (monospaced) matching current sheet typography.
   - No `TextField`, no `@FocusState`, no `.keyboardType`, no `TrainKeyboard.dismiss()` in this path.

2. **`SetValueEditorSheet.swift`** refactor:
   - Remove `TextField` and `@FocusState private var isFieldFocused`.
   - Remove `onAppear { isFieldFocused = true }` and keyboard release helpers tied to UIKit keyboard.
   - Embed `TrainNumpadView`; keep Done / Cancel toolbar, `.presentationDetents([.medium])`.
   - **Done:** apply `text` via `onSave`, then `dismiss()`.
   - **Do not** set `AppLifecycleBroker.shared.isLiveWorkoutSetFieldEditing = true` for numpad (no system keyboard). Remove or gate that flag so background policy does not treat numpad like UIKit editing.
   - Keep `.onChange(of: scenePhase)` background dismiss if sheet still open (set `dismiss()` only).

3. **`SetRowView.swift`**:
   - Background handler that clears `valueEditorPresentation` can stay; remove redundant `TrainKeyboard.dismiss()` if nothing uses system keyboard on this path.
   - Keep `setValueEditor open` / `dismissedFromRow` diagnostics.

4. **Diagnostics**
   - `setValueEditor open field=... mode=customNumpad`
   - `setValueEditor done field=...`
   - Optional: drop `keyboardReleased` lines or repurpose for sheet lifecycle only.

5. **Tests** (lightweight)
   - Unit test numpad logic: append digit, backspace, decimal rules (extract pure functions if needed). No HK device required.

### Do not

- Revert to inline `TextField` in `SetRowView` scroll (Phase 3 regression).
- Add third-party keyboard libs.
- MLX unload / workout overlay rewrite in this milestone.
- Change wellness sheet (already fixed).

### Optional small follow-up (only if custom numpad still fails)

- `.interactiveDismissDisabled(true)` on value editor sheet.
- Gate `LiveWorkoutPhoneSessionManager.start` when HK auth not determined (`Error(7)` at beginCollection in `212450.log`).

---

## Key files

| Area | Path |
|------|------|
| Value editor sheet | `Signal/Signal/Features/Train/SetValueEditorSheet.swift` |
| Set row + sheet presentation | `Signal/Signal/Features/Train/SetRowView.swift` |
| Legacy keyboard helper | `Signal/Signal/Features/Train/TrainKeyboard.swift` |
| Lifecycle flags | `Signal/Signal/App/AppLifecycleBroker.swift` |
| Prior handoff (context) | `HANDOFF-HK-WORKOUT-TEARDOWN.md` |

---

## Verify (Gate A agent)

Device: iPhone 16 Pro `00008140-001E34E10A01801C`

1. `build_device` → `install_app_device` → `launch_app` (or human tap icon)
2. **Primary repro (must pass):**
   - Start workout → tap weight or reps → **tap several numpad digits** → Done
   - Home → 15s → return → **tabs visible, not blank**
3. **Secondary:**
   - Type reps → finish workout → wellness Save → home → return
   - Complete set using **only** pre-filled values (regression)
4. **Diagnostics:** no `keyboardReleased`; `setValueEditor open ... mode=customNumpad`; same pid after background

---

## Handover log

Append to `AGENT-BUILD-UPDATES.md` per `.cursor/rules/agent-build-handover.mdc`.

Declare: **MILESTONE COMPLETE: Train custom numpad, READY TO COMMIT** and wait for human commit.

If keypad pass but **new pid** on long background without typing: open Gate 2A (MLX park) as separate handoff.
