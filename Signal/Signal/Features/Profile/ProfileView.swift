import SwiftUI

enum ProfileDestination: Hashable {
    case settings
    case importData
    case diagnostics
}

struct ProfileView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var path: [ProfileDestination] = []

    var body: some View {
        ZStack {
            screenBackground
                .ignoresSafeArea()

            List {
                Section {
                    NavigationLink(value: ProfileDestination.settings) {
                        profileRow(
                            title: "Settings",
                            subtitle: "Units, notifications, data, and about",
                            symbol: "gearshape"
                        )
                    }
                }

                Section("Data") {
                    NavigationLink(value: ProfileDestination.importData) {
                        profileRow(
                            title: "Import",
                            subtitle: "Health export, Hevy CSV, and live sync",
                            symbol: "square.and.arrow.down"
                        )
                    }
                    NavigationLink(value: ProfileDestination.diagnostics) {
                        profileRow(
                            title: "Diagnostics",
                            subtitle: "Store health, retrieval tests, and sync",
                            symbol: "stethoscope"
                        )
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: ProfileDestination.self) { destination in
            switch destination {
            case .settings:
                SettingsView()
            case .importData:
                ImportView()
            case .diagnostics:
                DiagnosticsView()
            }
        }
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }

    private func profileRow(title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color("Primary"))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.cardLabel)
                    .foregroundStyle(Color("TextPrimary"))
                Text(subtitle)
                    .font(.metadataCaption)
                    .foregroundStyle(Color("TextSecondary"))
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
    .environment(HealthKitManager(modelContainer: try! SignalModelContainer.make(inMemoryOnly: true)))
    .environment(UnitPreferences.shared)
}
