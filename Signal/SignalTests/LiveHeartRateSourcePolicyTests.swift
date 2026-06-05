import Foundation
import Testing
@testable import Signal

struct LiveHeartRateSourcePolicyTests {
    @Test func watchWhenAllConditionsMet() {
        let source = LiveHeartRateSourcePolicy.resolve(
            LiveHeartRateSourceSnapshot(
                isWatchConnectivitySupported: true,
                isSessionActivated: true,
                isPaired: true,
                isWatchAppInstalled: true
            )
        )
        #expect(source == .watch)
    }

    @Test func phoneWhenWatchConnectivityUnsupported() {
        let source = LiveHeartRateSourcePolicy.resolve(
            LiveHeartRateSourceSnapshot(
                isWatchConnectivitySupported: false,
                isSessionActivated: true,
                isPaired: true,
                isWatchAppInstalled: true
            )
        )
        #expect(source == .phoneHealthKit)
    }

    @Test func phoneWhenSessionNotActivated() {
        let source = LiveHeartRateSourcePolicy.resolve(
            LiveHeartRateSourceSnapshot(
                isWatchConnectivitySupported: true,
                isSessionActivated: false,
                isPaired: true,
                isWatchAppInstalled: true
            )
        )
        #expect(source == .phoneHealthKit)
    }

    @Test func phoneWhenNotPaired() {
        let source = LiveHeartRateSourcePolicy.resolve(
            LiveHeartRateSourceSnapshot(
                isWatchConnectivitySupported: true,
                isSessionActivated: true,
                isPaired: false,
                isWatchAppInstalled: true
            )
        )
        #expect(source == .phoneHealthKit)
    }

    @Test func phoneWhenWatchAppNotInstalled() {
        let source = LiveHeartRateSourcePolicy.resolve(
            LiveHeartRateSourceSnapshot(
                isWatchConnectivitySupported: true,
                isSessionActivated: true,
                isPaired: true,
                isWatchAppInstalled: false
            )
        )
        #expect(source == .phoneHealthKit)
    }

    @Test func phoneWhenNoConditionMet() {
        let source = LiveHeartRateSourcePolicy.resolve(
            LiveHeartRateSourceSnapshot(
                isWatchConnectivitySupported: false,
                isSessionActivated: false,
                isPaired: false,
                isWatchAppInstalled: false
            )
        )
        #expect(source == .phoneHealthKit)
    }
}
