import SwiftUI
import UIKit

enum ProfileDestination: Hashable {
    case profileGoals
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
                if TrainWorkoutDiagnostics.hasEntries {
                    Section {
                        Text("Workout debug log")
                            .font(.headline)
                        Text(TrainWorkoutDiagnostics.exportText())
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                        Button("Copy workout debug log") {
                            _ = TrainWorkoutDiagnostics.copyToPasteboardAndReset()
                        }
                    }
                }

                Section {
                    NavigationLink(value: ProfileDestination.profileGoals) {
                        profileRow(
                            title: "Profile and goals",
                            subtitle: "About you and training focus",
                            symbol: "person.crop.circle"
                        )
                    }
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
            case .profileGoals:
                ProfileGoalsView()
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
