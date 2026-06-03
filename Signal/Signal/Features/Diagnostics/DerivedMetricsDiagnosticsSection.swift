import SwiftUI

struct DerivedMetricsDiagnosticsSection: View {
    let snapshot: DerivedMetricsSnapshot
    let onShowDataQualityFlags: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Derived metrics")
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))

            Text("Current week volume")
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))
                .padding(.top, 4)

            if snapshot.weeklyVolume.isEmpty {
                Text("No working sets logged this week.")
            } else {
                ForEach(snapshot.weeklyVolume, id: \.muscleGroup) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.muscleGroup.rawValue)
                        Spacer(minLength: 8)
                        Text("\(VolumeCalculator.integerSetCount(from: row.fractionalSets)) sets")
                            .font(.system(.caption, design: .monospaced))
                        Text(row.status.badgeLabel)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(statusColor(row.status))
                    }
                }
            }

            if let acwr = snapshot.acwr {
                HStack(alignment: .firstTextBaseline) {
                    Text("Total ACWR")
                    Spacer()
                    Text(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), acwr.acwr))
                        .font(.system(.caption, design: .monospaced))
                    Text(acwr.zone.badgeLabel)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(acwrZoneColor(acwr.zone))
                }
                .padding(.top, 8)
            } else {
                Text("Total ACWR: unavailable (no chronic load)")
                    .padding(.top, 8)
            }

            Text("Recent e1RM")
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))
                .padding(.top, 8)

            if snapshot.recentE1RM.isEmpty {
                Text("No exercise progress rows yet.")
            } else {
                ForEach(snapshot.recentE1RM, id: \.exerciseID) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.exerciseID)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(
                            String(
                                format: "%.1f kg",
                                locale: Locale(identifier: "en_US_POSIX"),
                                row.e1RMKg
                            )
                        )
                        .font(.system(.caption, design: .monospaced))
                    }
                }
            }

            if let protein = snapshot.proteinTarget {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Protein target")
                        .font(.cardLabel)
                        .foregroundStyle(Color("TextPrimary"))
                        .padding(.top, 8)
                    Text(
                        "Target \(Int(protein.targetMinGrams.rounded())) to \(Int(protein.targetMaxGrams.rounded())) g/day"
                    )
                    if let actual = protein.actualGrams {
                        Text("Latest logged: \(Int(actual.rounded())) g")
                        if let ratio = protein.gramsPerKgActual {
                            Text(
                                String(
                                    format: "%.2f g/kg",
                                    locale: Locale(identifier: "en_US_POSIX"),
                                    ratio
                                )
                            )
                        }
                    } else {
                        Text("No dietary protein in DailyNutrition yet.")
                    }
                }
            }

            Button {
                onShowDataQualityFlags()
            } label: {
                HStack {
                    Text("Data quality flags")
                    Spacer()
                    Text("\(snapshot.dataQualityFlagCount)")
                        .font(.system(.body, design: .monospaced))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .disabled(snapshot.dataQualityFlagCount == 0)
        }
    }

    private func statusColor(_ status: VolumeStatus) -> Color {
        switch status {
        case .belowMEV:
            return .orange
        case .mevToMAV:
            return .green
        case .mavToMRV:
            return Color("Primary")
        case .aboveMRV:
            return .orange
        }
    }

    private func acwrZoneColor(_ zone: ACWRZone) -> Color {
        switch zone {
        case .belowOptimal, .caution, .overreach:
            return .orange
        case .optimal:
            return .green
        }
    }
}

struct DataQualityFlagsListView: View {
    let flags: [DataQualityFlagRow]

    var body: some View {
        List(flags) { flag in
            VStack(alignment: .leading, spacing: 4) {
                Text(flag.metricKind)
                    .font(.headline)
                Text(flag.dateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("value=\(flag.valueLabel) issue=\(flag.issue)")
                    .font(.system(.caption, design: .monospaced))
                if flag.wasCorrected {
                    Text("Corrected in store")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Data quality")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DataQualityFlagRow: Identifiable {
    let id: String
    let metricKind: String
    let dateLabel: String
    let valueLabel: String
    let issue: String
    let wasCorrected: Bool
}
