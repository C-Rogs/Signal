import SwiftUI

struct CoachPlaceholderView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            screenBackground
                .ignoresSafeArea()

            ContentUnavailableView {
                Label("Coach", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("On-device coaching chat arrives in a later milestone.")
            }
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.large)
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }
}

#Preview {
    NavigationStack {
        CoachPlaceholderView()
    }
}
