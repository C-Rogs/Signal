import SwiftUI
import WidgetKit

struct RecoveryGaugeComplicationView: View {
    let snapshot: RecoveryWidgetSnapshot

    var body: some View {
        Gauge(value: snapshot.gaugeProgress, in: 0 ... 1) {
            Text("Recovery")
        } currentValueLabel: {
            Text(displayScore)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(RecoveryWidgetSnapshot.gaugeTintColor(for: snapshot.scoreValue))
    }

    private var displayScore: String {
        guard snapshot.scoreValue != nil else { return "—" }
        let text = snapshot.scoreText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "—" : text
    }
}

struct BodyBatteryComplicationWidget: Widget {
    static let kind = BodyBatteryComplicationKind.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: RecoveryComplicationProvider()) { entry in
            RecoveryGaugeComplicationView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Body Battery")
        .description("Recovery energy from Signal.")
        .supportedFamilies([.accessoryCircular])
    }
}
