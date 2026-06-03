import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(UnitPreferences.self) private var unitPreferences
    @Environment(TrainPreferences.self) private var trainPreferences
    @Bindable private var downloadState = EmbeddingDownloadState.shared

    var body: some View {
        ZStack {
            screenBackground
                .ignoresSafeArea()

            List {
                Section {
                    Toggle("Suggest warmup sets", isOn: Bindable(trainPreferences).suggestWarmupSets)
                } header: {
                    Text("Train")
                } footer: {
                    Text(
                        "During a workout, Signal can suggest ramp sets for early compound lifts. Hypertrophy defaults to about 45% and 65% of your first working weight when load is known."
                    )
                }

                Section {
                    Picker("Weight", selection: Bindable(unitPreferences).massUnit) {
                        ForEach(MassUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    Picker("Distance", selection: Bindable(unitPreferences).distanceUnit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                } header: {
                    Text("Unit preference")
                } footer: {
                    Text("Signal stores kg and km internally. Charts and labels convert for display only.")
                }

                Section("Notifications") {
                    placeholderRow(
                        title: "Workout reminders",
                        detail: "Coming soon"
                    )
                    placeholderRow(
                        title: "Daily briefing",
                        detail: "Coming soon"
                    )
                }

                Section("Data management") {
                    placeholderRow(
                        title: "Export app data",
                        detail: "Coming soon"
                    )
                    placeholderRow(
                        title: "Import app data",
                        detail: "Coming soon"
                    )
                    placeholderRow(
                        title: "Re-import health data",
                        detail: "Use Profile > Import"
                    )
                    placeholderRow(
                        title: "Reset local store",
                        detail: "Coming soon"
                    )
                }

                Section("Embedding model") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(embeddingStatusLabel)
                            .foregroundStyle(Color("TextSecondary"))
                    }
                    if downloadState.phase == .failed, let message = downloadState.errorMessage {
                        Text(message)
                            .font(.metadataCaption)
                            .foregroundStyle(.orange)
                        Button("Retry download") {
                            downloadState.requestRetry()
                        }
                    }
                }

                Section("About") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Signal")
                            .font(.cardLabel)
                            .foregroundStyle(Color("TextPrimary"))
                        Text(
                            "Signal is a training and recovery companion, not a medical device. It does not diagnose conditions or replace care from a qualified clinician. Talk to your doctor about chest pain, breathing problems, sustained high blood pressure, or any symptom that worries you."
                        )
                        .font(.metadataCaption)
                        .foregroundStyle(Color("TextSecondary"))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }

    private var embeddingStatusLabel: String {
        if EmbeddingBackend.useNLContextualEmbeddingFallback {
            return "System embeddings (fallback)"
        }
        switch downloadState.phase {
        case .idle:
            return "Not started"
        case .downloading:
            return "Downloading"
        case .ready:
            return "Ready"
        case .failed:
            return "Failed"
        }
    }

    private func placeholderRow(title: String, detail: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color("TextPrimary"))
            Spacer()
            Text(detail)
                .font(.metadataCaption)
                .foregroundStyle(Color("TextSecondary"))
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(UnitPreferences.shared)
    .environment(TrainPreferences.shared)
    .modelContainer(try! SignalModelContainer.make(inMemoryOnly: true))
}
