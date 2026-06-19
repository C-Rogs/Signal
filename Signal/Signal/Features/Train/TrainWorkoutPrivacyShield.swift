import SwiftUI

struct TrainWorkoutPrivacyShield: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TrainChrome.screenBackground(colorScheme: colorScheme)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
