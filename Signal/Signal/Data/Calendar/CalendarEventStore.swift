import EventKit
import Foundation
import os

actor CalendarEventStore {
    static let shared = CalendarEventStore()

    private let eventStore = EKEventStore()

    private init() {}

    func currentAccessState() -> CalendarAccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return .authorized
        case .writeOnly, .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func requestAccessIfNeeded() async -> CalendarAccessState {
        let state = currentAccessState()
        guard case .notDetermined = state else { return state }

        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            Log.calendar.info("calendar access requested granted=\(granted, privacy: .public)")
            return currentAccessState()
        } catch {
            Log.calendar.error(
                "calendar access request failed: \(error.localizedDescription, privacy: .public)"
            )
            return currentAccessState()
        }
    }

    func fetchEvents(in window: DateInterval) -> [CalendarEventSnapshot] {
        guard case .authorized = currentAccessState() else { return [] }

        let predicate = eventStore.predicateForEvents(
            withStart: window.start,
            end: window.end,
            calendars: nil
        )
        let ekEvents = eventStore.events(matching: predicate)
        return ekEvents.map { event in
            CalendarEventSnapshot(
                title: event.title ?? "Untitled",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay
            )
        }
    }
}
