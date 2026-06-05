import SwiftUI
import WidgetKit

struct RecoveryBatteryInlineComplicationWidget: Widget {
    static let kind = RecoveryBatteryInlineComplicationKind.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: RecoveryComplicationProvider()) { entry in
            RecoveryBatteryInlineComplicationView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Body Battery")
        .description("Battery icon and charge percent. Best for Utility large bar.")
        .supportedFamilies([.accessoryInline])
    }
}

struct RecoveryBatteryInlineComplicationView: View {
    let snapshot: RecoveryWidgetSnapshot

    var body: some View {
        Group {
            if snapshot.scoreValue != nil {
                Text("\(Image(systemName: snapshot.batterySymbolName)) \(snapshot.bodyBatteryPercentText)")
            } else {
                Text("\(Image(systemName: "battery.0percent")) —")
            }
        }
        .containerBackground(for: .widget) {
            AccessoryWidgetBackground()
        }
    }
}
