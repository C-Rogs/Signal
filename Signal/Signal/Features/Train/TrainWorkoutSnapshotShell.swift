import SwiftUI

struct TrainWorkoutSnapshotShell: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            TrainChrome.screenBackground(colorScheme: colorScheme)
                .ignoresSafeArea()
            TrainSecureSnapshotField()
                .ignoresSafeArea()
        }
        .accessibilityHidden(true)
    }
}
