import Foundation
import Combine
#if !SKIP
import EventKit
#endif

/// Exports a goal's estimated completion date to the user's Apple
/// Calendar as a single all-day event with a same-day reminder.
///
/// Uses "write-only" calendar access (iOS 17+) since the app only ever
/// needs to CREATE an event — it never reads the user's existing
/// calendar — which shows a less scary system permission prompt than
/// full read/write access. Falls back to the older full-access API on
/// iOS 16 and earlier, where write-only access doesn't exist yet.
@MainActor
final class CalendarSyncManager: ObservableObject {
    @Published var isSyncing = false
    @Published var lastResultMessage: String?
    @Published var lastSyncSucceeded: Bool = false
    
    #if !SKIP
    private let store = EKEventStore()
    #endif

    /// Creates (or updates in place, if already synced once) an all-day
    /// event on the user's default calendar for the goal's estimated
    /// completion date.
    ///
    /// `goalMarker` should be something stable for this goal (e.g. its
    /// title) — it's stashed in the event's notes so a repeat tap updates
    /// the same event instead of creating duplicates every sync.
    func addGoalToCalendar(goalMarker: String, title: String, targetDate: Date, remainingAmount: Double) async {
        #if !SKIP
        isSyncing = true
        defer { isSyncing = false }

        let granted = await requestAccess()
        guard granted else {
            lastSyncSucceeded = false
            lastResultMessage = "Calendar access was denied. Enable it in Settings → Pocket Vault → Calendars."
            return
        }

        let marker = "pocketvault-goal-\(goalMarker)"
        let existing = findExistingEvent(marker: marker)

        let event = existing ?? EKEvent(eventStore: store)
        event.title = "🎯 \(title.isEmpty ? "Savings Goal" : title) — Target Date"
        event.notes = "\(marker)\nRemaining to save as of last sync: $\(Int(remainingAmount))\nCreated by Pocket Vault."
        event.isAllDay = true
        event.startDate = Calendar.current.startOfDay(for: targetDate)
        event.endDate = event.startDate
        event.calendar = localOrDefaultCalendar()

        // A same-day reminder so the date doesn't just silently pass by.
        if event.alarms == nil || event.alarms?.isEmpty == true {
            event.addAlarm(EKAlarm(relativeOffset: 0))
        }

        do {
            try store.save(event, span: .thisEvent)
            print("Saved to calendar:", event.calendar?.title ?? "nil", event.calendar?.type.rawValue ?? "nil")
            lastSyncSucceeded = true
            lastResultMessage = existing != nil ? "Updated in Apple Calendar." : "Added to Apple Calendar."
        } catch {
            lastSyncSucceeded = false
            lastResultMessage = "Couldn't save to Apple Calendar. Try again."
        }
        
        #else
        
        // Android fallback to prevent UI hanging
        lastSyncSucceeded = false
        lastResultMessage = "Calendar sync is currently only supported on iOS."
        
        #endif
    }

    // Completely hide the Apple-specific helper functions from Android
    #if !SKIP
    
    /// Prefers a local (on-device) calendar over iCloud/Exchange ones —
    /// in the Simulator especially, iCloud calendars often aren't signed
    /// in, so an event saved to `defaultCalendarForNewEvents` can succeed
    /// silently but never actually show up anywhere visible. Falls back
    /// to the system default if no local calendar exists.
    private func localOrDefaultCalendar() -> EKCalendar? {
        let local = store.calendars(for: .event).first { $0.type == .local }
        return local ?? store.defaultCalendarForNewEvents
    }

    private func findExistingEvent(marker: String) -> EKEvent? {
        // Wide search window since the target date could be months out,
        // or (if the user pushed it back since last sync) now in the past.
        let start = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let end = Calendar.current.date(byAdding: .year, value: 5, to: Date()) ?? Date()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).first { $0.notes?.contains(marker) == true }
    }

    private func requestAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await store.requestWriteOnlyAccessToEvents()
            } catch {
                print("Calendar access request failed:", error)
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, error in
                    if let error {
                        print("Calendar access request failed:", error)
                    }
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    #endif
}
