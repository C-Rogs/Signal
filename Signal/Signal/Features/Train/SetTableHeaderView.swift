import SwiftUI

struct SetTableHeaderView: View {
    let mode: ExerciseLoggingMode
    let massColumnTitle: String
    let distanceColumnTitle: String

    var body: some View {
        HStack(spacing: 6) {
            Text("SET")
                .frame(width: 26, alignment: .center)
            Text("PREVIOUS")
                .frame(minWidth: 56, maxWidth: .infinity, alignment: .leading)
            if mode == .strength {
                Text(massColumnTitle)
                    .frame(width: 48, alignment: .trailing)
                Text("REPS")
                    .frame(width: 36, alignment: .trailing)
            } else {
                Text(distanceColumnTitle)
                    .frame(width: 44, alignment: .trailing)
                Text("TIME")
                    .frame(width: 36, alignment: .trailing)
            }
            Text("RPE")
                .frame(width: 44, alignment: .center)
            Color.clear
                .frame(width: 26)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color("TextSecondary"))
        .textCase(.uppercase)
        .accessibilityHidden(true)
    }
}
