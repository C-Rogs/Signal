import os
import SwiftData
import SwiftUI

struct RecoveryDisruptorTagButton: View {
    @Environment(\.modelContext) private var modelContext

    let onTagged: () -> Void

    @State private var showUndo = false

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    var body: some View {
        Group {
            if showUndo {
                Button("Undo") {
                    undoTag()
                }
                .font(.metadataCaption.weight(.semibold))
                .foregroundStyle(Color("Primary"))
            } else if !hasTagForYesterday {
                Button("Drank last night") {
                    tagAlcohol()
                }
                .font(.metadataCaption.weight(.semibold))
                .foregroundStyle(Color("TextSecondary"))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color("Background"))
                .clipShape(Capsule())
            }
        }
        .onAppear {
            refreshState()
        }
    }

    private var hasTagForYesterday: Bool {
        RecoveryDisruptorEngine.hasUserAlcoholTagForYesterday(
            in: modelContext,
            calendar: calendar
        )
    }

    private func refreshState() {
        showUndo = RecoveryDisruptorEngine.canUndoTodayAlcoholTag(
            in: modelContext,
            calendar: calendar
        )
    }

    private func tagAlcohol() {
        do {
            try RecoveryDisruptorEngine.tagAlcoholLastNight(in: modelContext, calendar: calendar)
            refreshState()
            onTagged()
        } catch {
            Log.recovery.error("disruptor tag failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func undoTag() {
        do {
            _ = try RecoveryDisruptorEngine.undoTodayUserTag(
                kind: .alcohol,
                in: modelContext,
                calendar: calendar
            )
            refreshState()
            onTagged()
        } catch {
            Log.recovery.error("disruptor undo failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
