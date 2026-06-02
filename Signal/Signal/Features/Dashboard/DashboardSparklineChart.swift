import Charts
import SwiftUI

struct DashboardSparklineChart: View {
    @Environment(UnitPreferences.self) private var unitPreferences
    let points: [DashboardChartPoint]
    let valueStyle: DashboardChartValueStyle
    var tint: Color = Color("Primary")

    @State private var selectedDate: Date?

    private static let selectionDateFormat = Date.FormatStyle()
        .weekday(.abbreviated)
        .month(.abbreviated)
        .day()

    private var unitFormatter: DisplayUnitFormatter {
        DisplayUnitFormatter(preferences: unitPreferences)
    }

    private var selectedPoint: DashboardChartPoint? {
        guard let selectedDate else { return nil }
        return points.nearest(to: selectedDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            selectionCallout
            chartBody
        }
    }

    @ViewBuilder
    private var selectionCallout: some View {
        if let point = selectedPoint {
            HStack(spacing: 6) {
                Text(point.date, format: Self.selectionDateFormat)
                Text("·")
                Text(valueStyle.formattedValue(point.value, formatter: unitFormatter))
            }
            .font(.cardLabel)
            .foregroundStyle(Color("TextPrimary"))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color("SurfaceElevated"))
            .clipShape(Capsule())
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private var chartBody: some View {
        Group {
            if points.count >= 2 {
                Chart {
                    ForEach(points) { point in
                        AreaMark(
                            x: .value("Day", point.date),
                            y: .value("Value", point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [tint.opacity(0.28), tint.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Day", point.date),
                            y: .value("Value", point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }

                    if let point = selectedPoint {
                        RuleMark(x: .value("Day", point.date))
                            .foregroundStyle(Color("TextSecondary").opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                        PointMark(
                            x: .value("Day", point.date),
                            y: .value("Value", point.value)
                        )
                        .symbolSize(64)
                        .foregroundStyle(tint)

                        PointMark(
                            x: .value("Day", point.date),
                            y: .value("Value", point.value)
                        )
                        .symbolSize(140)
                        .foregroundStyle(tint.opacity(0.2))
                    }
                }
                .id(points.chartRenderIdentity)
                .chartXScale(domain: points.chartDateDomain)
                .chartYScale(domain: points.chartValueDomain)
                .chartXSelection(value: $selectedDate)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: gridStroke)
                            .foregroundStyle(gridColor)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.metadataCaption)
                            .foregroundStyle(Color("TextSecondary"))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: gridStroke)
                            .foregroundStyle(gridColor)
                        if let numeric = value.as(Double.self) {
                            AxisValueLabel {
                                Text(valueStyle.yAxisLabel(numeric, formatter: unitFormatter))
                                    .font(.metadataCaption)
                                    .foregroundStyle(Color("TextSecondary"))
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .animation(.easeOut(duration: 0.2), value: selectedPoint?.id)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .overlay {
                        Text("Not enough data")
                            .font(.metadataCaption)
                            .foregroundStyle(Color("TextSecondary"))
                    }
            }
        }
        .frame(height: 112)
        .onChange(of: points.chartRenderIdentity) { _, _ in
            selectedDate = nil
        }
    }

    private var gridColor: Color {
        Color("TextSecondary").opacity(0.22)
    }

    private var gridStroke: StrokeStyle {
        StrokeStyle(lineWidth: 0.5, lineCap: .round, dash: [2, 4])
    }
}

extension Array where Element == DashboardChartPoint {
    func nearest(to date: Date) -> DashboardChartPoint? {
        guard !isEmpty else { return nil }
        return self.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }
}
