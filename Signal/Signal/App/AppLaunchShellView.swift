import SwiftUI

struct AppLaunchShellView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color("Background"))
                .ignoresSafeArea()

            ProgressView("Opening Signal…")
                .controlSize(.regular)
                .tint(Color("Primary"))
        }
    }
}
