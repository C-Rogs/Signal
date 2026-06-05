import SwiftUI
import WidgetKit

struct RecoveryGaugeComplicationView: View {
    @Environment(\.showsWidgetLabel) private var showsWidgetLabel
    let snapshot: RecoveryWidgetSnapshot

    var body: some View {
        Group {
            if showsWidgetLabel {
                utilityArcGauge
            } else {
                circularGauge
            }
        }
        .containerBackground(for: .widget) {
            AccessoryWidgetBackground()
        }
    }

    /// Full circle slots (corners on Utility). Not the arc under the digital time.
    private var circularGauge: some View {
        ProgressView(value: snapshot.gaugeProgress, total: 1) {
            Text(snapshot.bodyBatteryPercentText)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .progressViewStyle(.circular)
        .tint(RecoveryWidgetSnapshot.gaugeTintColor(for: snapshot.scoreValue))
    }

    /// Utility arc under the time: score in the dial, filled ring in the curved label.
    private var utilityArcGauge: some View {
        Text(snapshot.bodyBatteryPercentText)
            .font(.system(.title3, design: .rounded).weight(.bold))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .widgetLabel {
                Gauge(value: snapshot.gaugeProgress, in: 0 ... 1) {
                    Image(systemName: snapshot.batterySymbolName)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(RecoveryWidgetSnapshot.gaugeTintColor(for: snapshot.scoreValue))
            }
    }
}

struct BodyBatteryComplicationWidget: Widget {
    static let kind = BodyBatteryComplicationKind.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: RecoveryComplicationProvider()) { entry in
            RecoveryGaugeComplicationView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Body Battery Ring")
        .description("Charge ring with percent in the center. Use corner circle slots.")
        .supportedFamilies([.accessoryCircular])
    }
}
