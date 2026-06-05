import SwiftUI
import WidgetKit

@main
struct SignalWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecoveryComplicationWidget()
        RecoveryBatteryInlineComplicationWidget()
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
        .description("Recovery score and HRV band. For battery percent use Body Battery.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct RecoveryComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: RecoveryWidgetSnapshot
}

struct RecoveryComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecoveryComplicationEntry {
        RecoveryComplicationEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecoveryComplicationEntry) -> Void) {
        let snapshot = context.isPreview ? .preview : loadSnapshot()
        completion(RecoveryComplicationEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecoveryComplicationEntry>) -> Void) {
        let now = Date()
        let snapshot = loadSnapshot()
        let entry = RecoveryComplicationEntry(date: now, snapshot: snapshot)
        let refresh = WatchComplicationTimelinePolicy.nextReloadDate(
            after: now,
            isWaiting: snapshot == .waiting
        )
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func loadSnapshot() -> RecoveryWidgetSnapshot {
        RecoveryWidgetSnapshot.make(from: WatchPayloadCache.readPayloadHydratingFromSession())
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
        case .accessoryInline:
            RecoveryInlineComplicationView(snapshot: entry.snapshot)
        default:
            RecoveryCircularComplicationView(snapshot: entry.snapshot)
        }
    }
}

struct RecoveryCircularComplicationView: View {
    @Environment(\.showsWidgetLabel) private var showsWidgetLabel
    let snapshot: RecoveryWidgetSnapshot

    var body: some View {
        Group {
            if showsWidgetLabel {
                Text(displayScore)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .widgetLabel {
                        Text(snapshot.hrvLabel)
                            .font(.caption2)
                            .lineLimit(1)
                    }
            } else {
                Text(displayScore)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
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

struct RecoveryInlineComplicationView: View {
    let snapshot: RecoveryWidgetSnapshot

    var body: some View {
        Group {
            if snapshot.scoreValue != nil {
                Text("\(Image(systemName: "waveform.path.ecg")) \(displayScore) · \(snapshot.hrvLabel)")
            } else {
                Text("\(Image(systemName: "waveform.path.ecg")) Waiting for Signal")
            }
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
