import SwiftUI

struct MuscleChipRow: View {
    let primary: [Muscle]
    let secondary: [Muscle]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(primary, id: \.self) { muscle in
                muscleChip(muscle, isPrimary: true)
            }
            ForEach(secondary.filter { !primary.contains($0) }, id: \.self) { muscle in
                muscleChip(muscle, isPrimary: false)
            }
        }
    }

    private func muscleChip(_ muscle: Muscle, isPrimary: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: MuscleVisual.symbol(for: muscle))
                .font(.caption2)
            Text(MuscleVisual.shortLabel(for: muscle))
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(isPrimary ? Color("Primary") : Color("TextSecondary"))
        .background(
            (isPrimary ? Color("Primary") : Color("TextSecondary"))
                .opacity(isPrimary ? 0.18 : 0.12)
        )
        .clipShape(Capsule())
    }
}

enum MuscleVisual {
    static func symbol(for muscle: Muscle) -> String {
        switch muscle {
        case .chest: "figure.arms.open"
        case .lats, .upperBack, .traps: "figure.climbing"
        case .quads, .hamstrings, .glutes, .calves: "figure.walk"
        case .biceps, .triceps, .forearms: "figure.strengthtraining.functional"
        case .frontDelts, .sideDelts, .rearDelts: "figure.boxing"
        case .abs, .obliques: "figure.core.training"
        case .lowerBack: "figure.cooldown"
        case .fullBody: "figure.run"
        }
    }

    static func shortLabel(for muscle: Muscle) -> String {
        switch muscle {
        case .upperBack: "Upper back"
        case .lowerBack: "Lower back"
        case .frontDelts: "Front delts"
        case .sideDelts: "Side delts"
        case .rearDelts: "Rear delts"
        default:
            muscle.rawValue.capitalized
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

struct ExerciseIllustrationView: View {
    let catalogEntry: ExerciseCatalog?
    let title: String
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 10 : 12) {
            artwork
            if !compact {
                muscleColumn
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color("Primary").opacity(0.12))
            VStack(spacing: 4) {
                Image(systemName: equipmentSymbol)
                    .font(compact ? .title3 : .title2)
                    .foregroundStyle(Color("Primary"))
                if compact, let catalogEntry {
                    Text(catalogEntry.equipment.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: compact ? 52 : 72, height: compact ? 52 : 72)
        .accessibilityLabel("\(title) illustration")
    }

    @ViewBuilder
    private var muscleColumn: some View {
        if let catalogEntry, !catalogEntry.primaryMuscles.isEmpty {
            MuscleChipRow(
                primary: catalogEntry.primaryMuscles,
                secondary: catalogEntry.secondaryMuscles
            )
        } else {
            Text("Muscles unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var equipmentSymbol: String {
        guard let equipment = catalogEntry?.equipment else {
            return "figure.strengthtraining.traditional"
        }
        switch equipment {
        case .barbell: return "figure.strengthtraining.traditional"
        case .dumbbell: return "dumbbell.fill"
        case .machine: return "gearshape.2.fill"
        case .cable: return "cable.connector"
        case .bodyweight: return "figure.walk"
        case .kettlebell: return "figure.strengthtraining.functional"
        case .band: return "lasso"
        case .smith: return "arrow.up.and.down"
        case .other: return "figure.mixed.cardio"
        }
    }
}
