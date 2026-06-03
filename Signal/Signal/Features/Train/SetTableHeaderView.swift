import SwiftUI

struct SetTableHeaderView: View {
    let mode: ExerciseLoggingMode
    let massColumnTitle: String
    let distanceColumnTitle: String

    var body: some View {
        HStack(spacing: 8) {
            Text("SET")
                .frame(width: 28, alignment: .center)
            Text("PREVIOUS")
                .frame(maxWidth: .infinity, alignment: .leading)
            if mode == .strength {
                Text(massColumnTitle)
                    .frame(width: 56, alignment: .trailing)
                Text("REPS")
                    .frame(width: 44, alignment: .trailing)
            } else {
                Text(distanceColumnTitle)
                    .frame(width: 52, alignment: .trailing)
                Text("TIME")
                    .frame(width: 44, alignment: .trailing)
            }
            Color.clear
                .frame(width: 28)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color("TextSecondary"))
        .textCase(.uppercase)
        .accessibilityHidden(true)
    }
}
