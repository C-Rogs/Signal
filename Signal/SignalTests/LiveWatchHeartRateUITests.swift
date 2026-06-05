import Foundation
import Testing
@testable import Signal

struct LiveWatchHeartRateUITests {
    @Test func hiddenWhenLiveHeartRateNotRequested() {
        let state = LiveWatchHeartRateUIStateBuilder.make(
            isLiveHeartRateRequested: false,
            source: .watch,
            latestHeartRateBPM: 120,
            lastHeartRateAt: Date(),
            now: Date()
        )
        #expect(!state.showsHeartRateSlot)
        #expect(state.statusChipTitle == nil)
    }

    @Test func reservedSlotWhileWaitingOnWatch() {
        let now = Date()
        let state = LiveWatchHeartRateUIStateBuilder.make(
            isLiveHeartRateRequested: true,
            source: .watch,
            latestHeartRateBPM: nil,
            lastHeartRateAt: nil,
            now: now
        )
        #expect(state.showsHeartRateSlot)
        #expect(state.bpm == nil)
        #expect(!state.isStale)
        #expect(state.statusChipTitle == "Waiting for watch HR")
    }

    @Test func reservedSlotWhileWaitingOnPhone() {
        let now = Date()
        let state = LiveWatchHeartRateUIStateBuilder.make(
            isLiveHeartRateRequested: true,
            source: .phoneHealthKit,
            latestHeartRateBPM: nil,
            lastHeartRateAt: nil,
            now: now
        )
        #expect(state.showsHeartRateSlot)
        #expect(state.bpm == nil)
        #expect(!state.isStale)
        #expect(state.statusChipTitle == "Waiting for heart rate")
    }

    @Test func phoneAccessFailureShowsChip() {
        let state = LiveWatchHeartRateUIStateBuilder.make(
            isLiveHeartRateRequested: true,
            source: .phoneHealthKit,
            latestHeartRateBPM: nil,
            lastHeartRateAt: nil,
            accessStatusMessage: "Health access needed for live HR",
            now: Date()
        )
        #expect(state.statusChipTitle == "Health access needed for live HR")
    }

    @Test func liveStateClearsChip() {
        let now = Date()
        let state = LiveWatchHeartRateUIStateBuilder.make(
            isLiveHeartRateRequested: true,
            source: .watch,
            latestHeartRateBPM: 128,
            lastHeartRateAt: now,
            now: now
        )
        #expect(state.showsHeartRateSlot)
        #expect(state.bpm == 128)
        #expect(!state.isStale)
        #expect(state.statusChipTitle == nil)
    }

    @Test func staleWatchSampleShowsChipAndFlag() {
        let now = Date()
        let sampledAt = now.addingTimeInterval(-60)
        let state = LiveWatchHeartRateUIStateBuilder.make(
            isLiveHeartRateRequested: true,
            source: .watch,
            latestHeartRateBPM: 140,
            lastHeartRateAt: sampledAt,
            now: now
        )
        #expect(state.isStale)
        #expect(state.statusChipTitle == "Watch HR signal lost")
    }

    @Test func stalePhoneSampleShowsChipAndFlag() {
        let now = Date()
        let sampledAt = now.addingTimeInterval(-60)
        let state = LiveWatchHeartRateUIStateBuilder.make(
            isLiveHeartRateRequested: true,
            source: .phoneHealthKit,
            latestHeartRateBPM: 140,
            lastHeartRateAt: sampledAt,
            now: now
        )
        #expect(state.isStale)
        #expect(state.statusChipTitle == "HR signal lost")
    }
}
