import Foundation
import Testing
@testable import Signal

struct LiveWatchHeartRateUITests {
    @Test func hiddenWhenWatchWorkoutNotRequested() {
        let state = LiveWatchHeartRateUIStateBuilder.make(
            isWatchWorkoutRequested: false,
            latestHeartRateBPM: 120,
            lastHeartRateAt: Date(),
            now: Date()
        )
        #expect(!state.showsHeartRateSlot)
        #expect(state.statusChipTitle == nil)
    }

    @Test func reservedSlotWhileWaiting() {
        let now = Date()
        let state = LiveWatchHeartRateUIStateBuilder.make(
            isWatchWorkoutRequested: true,
            latestHeartRateBPM: nil,
            lastHeartRateAt: nil,
            now: now
        )
        #expect(state.showsHeartRateSlot)
        #expect(state.bpm == nil)
        #expect(!state.isStale)
        #expect(state.statusChipTitle == "Waiting for watch HR")
    }

    @Test func liveStateClearsChip() {
        let now = Date()
        let state = LiveWatchHeartRateUIStateBuilder.make(
            isWatchWorkoutRequested: true,
            latestHeartRateBPM: 128,
            lastHeartRateAt: now,
            now: now
        )
        #expect(state.showsHeartRateSlot)
        #expect(state.bpm == 128)
        #expect(!state.isStale)
        #expect(state.statusChipTitle == nil)
    }

    @Test func staleSampleShowsChipAndFlag() {
        let now = Date()
        let sampledAt = now.addingTimeInterval(-60)
        let state = LiveWatchHeartRateUIStateBuilder.make(
            isWatchWorkoutRequested: true,
            latestHeartRateBPM: 140,
            lastHeartRateAt: sampledAt,
            now: now
        )
        #expect(state.isStale)
        #expect(state.statusChipTitle == "Watch HR signal lost")
    }
}
