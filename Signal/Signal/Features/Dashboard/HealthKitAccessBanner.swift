import SwiftUI
import UIKit

struct HealthKitAccessBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(HealthKitManager.self) private var healthKitManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.cardLabel)
                .foregroundStyle(Color("TextPrimary"))

            Text(message)
                .font(.metadataCaption)
                .foregroundStyle(Color("TextSecondary"))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                if healthKitManager.accessState == .notDetermined {
                    Button("Allow Health access") {
                        Task {
                            await healthKitManager.requestAuthorization()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("Primary"))
                }

                if healthKitManager.accessState == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("Primary"))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bannerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var title: String {
        switch healthKitManager.accessState {
        case .unavailable:
            "Health data unavailable"
        case .notDetermined:
            "Connect Apple Health"
        case .denied:
            "Health access denied"
        case .ready:
            ""
        }
    }

    private var message: String {
        switch healthKitManager.accessState {
        case .unavailable:
            "This device cannot read HealthKit data. You can still import an Apple Health export from Profile > Import."
        case .notDetermined:
            "Grant read access to load recovery trends and keep daily metrics in sync."
        case .denied:
            "Turn on categories for Signal under Settings > Health > Data Access & Devices, then return and pull to refresh."
        case .ready:
            ""
        }
    }

    private var bannerBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color("SurfaceElevated")
    }
}
