import SwiftUI

struct TrainPlaceholderView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            screenBackground
                .ignoresSafeArea()

            ContentUnavailableView {
                Label("Train", systemImage: "figure.strengthtraining.traditional")
            } description: {
                Text("Routines, live workouts, and session history are coming in a later milestone.")
            }
        }
        .navigationTitle("Train")
        .navigationBarTitleDisplayMode(.large)
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }
}

#Preview {
    NavigationStack {
        TrainPlaceholderView()
    }
}
