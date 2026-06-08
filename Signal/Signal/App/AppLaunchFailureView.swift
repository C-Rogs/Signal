import SwiftUI

struct AppLaunchFailureView: View {
    @Environment(\.colorScheme) private var colorScheme

    let message: String
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color("Background"))
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Signal could not open your saved data.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(Color("Primary"))
            }
            .padding(24)
        }
    }
}
