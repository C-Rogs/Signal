import SwiftUI
import WidgetKit

@main
struct SignalWidgetBundle: WidgetBundle {
    var body: some Widget {
        SignalRecoveryWidget()
    }
}

struct SignalRecoveryWidget: Widget {
    static let kind = WatchPayloadCache.iosWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SignalRecoveryProvider()) { entry in
            SignalRecoveryWidgetView(entry: entry)
        }
        .configurationDisplayName("Recovery")
        .description("Today's recovery score and HRV band.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}

struct SignalRecoveryEntry: TimelineEntry {
    let date: Date
    let snapshot: RecoveryWidgetSnapshot
}

struct SignalRecoveryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SignalRecoveryEntry {
        SignalRecoveryEntry(date: Date(), snapshot: .waiting)
    }

    func getSnapshot(in context: Context, completion: @escaping (SignalRecoveryEntry) -> Void) {
        completion(SignalRecoveryEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SignalRecoveryEntry>) -> Void) {
        let snapshot = loadSnapshot()
        let entry = SignalRecoveryEntry(date: Date(), snapshot: snapshot)
        let refresh = snapshot == .waiting
            ? Date().addingTimeInterval(60)
            : Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func loadSnapshot() -> RecoveryWidgetSnapshot {
        RecoveryWidgetSnapshot.make(from: WatchPayloadCache.readPayload())
    }
}

struct SignalRecoveryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SignalRecoveryEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            LockScreenCircularRecoveryView(snapshot: entry.snapshot)
        case .accessoryRectangular:
            LockScreenRectangularRecoveryView(snapshot: entry.snapshot)
        default:
            HomeScreenRecoveryView(snapshot: entry.snapshot)
        }
    }
}

struct LockScreenCircularRecoveryView: View {
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

struct LockScreenRectangularRecoveryView: View {
    let snapshot: RecoveryWidgetSnapshot

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Signal Recovery")
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

struct HomeScreenRecoveryView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let snapshot: RecoveryWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recovery")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(displayScore)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(scoreForeground)
            Text(snapshot.hrvLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            Color.black
        }
    }

    private var displayScore: String {
        let text = snapshot.scoreText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "—" : text
    }

    private var scoreForeground: Color {
        guard snapshot != .waiting, renderingMode == .fullColor else { return .primary }
        return recoveryColor(for: snapshot.colorToken)
    }
}

private func recoveryColor(for token: String) -> Color {
    switch token {
    case "Positive":
        .green
    case "Warning":
        .orange
    case "Negative":
        .red
    default:
        .primary
    }
}
