import os
import SwiftUI

struct RootView: View {
    var body: some View {
        ZStack {
            Color("Background")
                .ignoresSafeArea()
            Text("Signal")
                .font(.displayLarge)
                .foregroundStyle(Color("TextPrimary"))
        }
        .onAppear {
            Log.ui.info("Root view appeared")
        }
    }
}

#Preview("Light") {
    RootView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    RootView()
        .preferredColorScheme(.dark)
}
