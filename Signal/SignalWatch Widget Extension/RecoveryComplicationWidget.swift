import SwiftUI
import WidgetKit

@main
struct SignalWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecoveryComplicationWidget()
        BodyBatteryComplicationWidget()
    }
}

struct RecoveryComplicationWidget: Widget {
    static let kind = RecoveryComplicationKind.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: RecoveryComplicationProvider()) { entry in
            RecoveryComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Recovery")
        .description("Today's recovery score from Signal.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct RecoveryComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: RecoveryWidgetSnapshot
}

struct RecoveryComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecoveryComplicationEntry {
        RecoveryComplicationEntry(date: Date(), snapshot: .waiting)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecoveryComplicationEntry) -> Void) {
        completion(RecoveryComplicationEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecoveryComplicationEntry>) -> Void) {
        let snapshot = loadSnapshot()
        let entry = RecoveryComplicationEntry(date: Date(), snapshot: snapshot)
        let refresh = snapshot == .waiting
            ? Date().addingTimeInterval(60)
            : Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func loadSnapshot() -> RecoveryWidgetSnapshot {
        RecoveryWidgetSnapshot.make(from: WatchPayloadCache.readPayload())
    }
}

struct RecoveryComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecoveryComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            RecoveryCircularComplicationView(snapshot: entry.snapshot)
        case .accessoryRectangular:
            RecoveryRectangularComplicationView(snapshot: entry.snapshot)
        default:
            RecoveryCircularComplicationView(snapshot: entry.snapshot)
        }
    }
}

struct RecoveryCircularComplicationView: View {
    let snapshot: RecoveryWidgetSnapshot

    var body: some View {
        Text(displayScore)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .containerBackground(for: .widget) {
                AccessoryWidgetBackground()
            }
    }

    private var displayScore: String {
        let text = snapshot.scoreText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "—" : text
    }
}

struct RecoveryRectangularComplicationView: View {
    let snapshot: RecoveryWidgetSnapshot

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recovery")
                    .font(.caption2)
                Text(snapshot.hrvLabel)
                    .font(.caption2)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(displayScore)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .containerBackground(for: .widget) {
            AccessoryWidgetBackground()
        }
    }

    private var displayScore: String {
        let text = snapshot.scoreText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "—" : text
    }
}
