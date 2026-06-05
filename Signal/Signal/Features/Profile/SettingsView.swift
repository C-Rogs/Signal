import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(UnitPreferences.self) private var unitPreferences
    @Environment(TrainPreferences.self) private var trainPreferences
    @Environment(NotificationPreferences.self) private var notificationPreferences
    @Environment(RecoveryPreferences.self) private var recoveryPreferences
    @Environment(CoachPreferences.self) private var coachPreferences
    @Bindable private var downloadState = EmbeddingDownloadState.shared
    @State private var backupViewModel: SettingsBackupViewModel?

    var body: some View {
        ZStack {
            screenBackground
                .ignoresSafeArea()

            List {
                Section {
                    NavigationLink {
                        ProfileGoalsView()
                    } label: {
                        HStack {
                            Text("Profile and goals")
                                .foregroundStyle(Color("TextPrimary"))
                            Spacer()
                            Text("About you, training focus")
                                .font(.metadataCaption)
                                .foregroundStyle(Color("TextSecondary"))
                        }
                    }
                }

                Section {
                    NavigationLink {
                        RecoveryCalendarHintsSettingsView()
                    } label: {
                        HStack {
                            Text("Calendar hints")
                                .foregroundStyle(Color("TextPrimary"))
                            Spacer()
                            Text(recoveryCalendarHintsDetail)
                                .font(.metadataCaption)
                                .foregroundStyle(Color("TextSecondary"))
                        }
                    }
                } header: {
                    Text("Recovery")
                } footer: {
                    Text(
                        "Optional phrases help Signal infer social drinking from last night's calendar events. All matching stays on device."
                    )
                }

                Section {
                    Toggle("Smart context routing", isOn: Bindable(coachPreferences).smartContextEnabled)
                    Toggle("Deep reasoning", isOn: Bindable(coachPreferences).deepReasoningEnabled)
                    Toggle("Compound queries", isOn: Bindable(coachPreferences).compoundQueriesEnabled)
                        .disabled(!coachPreferences.smartContextEnabled)
                    Toggle("Conversation memory", isOn: Bindable(coachPreferences).conversationMemoryEnabled)
                } header: {
                    Text("Coach")
                } footer: {
                    Text(
                        "Smart context loads only relevant metrics per question (faster, tighter answers). Deep reasoning adds a planning step before answering. Turn either off if responses feel slow. Compound queries blend context when a question spans two topics (e.g. recovery and calendar). Conversation memory keeps follow-ups in the same thread so you can refine plans; turn off for isolated one-shot answers."
                    )
                }

                Section {
                    Toggle("Suggest warmup sets", isOn: Bindable(trainPreferences).suggestWarmupSets)
                    Toggle("Workout haptics", isOn: Bindable(trainPreferences).hapticsEnabled)
                    Toggle("Rest timer bell", isOn: Bindable(trainPreferences).restBellEnabled)
                } header: {
                    Text("Train")
                } footer: {
                    Text(
                        "During a workout, Signal can suggest ramp sets for early compound lifts. Ramp percentages follow your training goal from Profile. Workout haptics give tactile feedback on sets and rest. The rest timer bell plays when rest ends."
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

                Section {
                    placeholderRow(
                        title: "Workout reminders",
                        detail: "Coming soon"
                    )
                    Toggle("Daily briefing", isOn: Bindable(notificationPreferences).dailyBriefingEnabled)
                        .onChange(of: notificationPreferences.dailyBriefingEnabled) { _, _ in
                            refreshDailyBriefingSchedule()
                        }
                    if notificationPreferences.dailyBriefingEnabled {
                        DatePicker(
                            "Morning time",
                            selection: briefingTimeBinding,
                            displayedComponents: .hourAndMinute
                        )
                        .onChange(of: notificationPreferences.briefingHour) { _, _ in
                            refreshDailyBriefingSchedule()
                        }
                        .onChange(of: notificationPreferences.briefingMinute) { _, _ in
                            refreshDailyBriefingSchedule()
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text(
                        "A local morning summary from your recovery score and latest insights. No data leaves your device."
                    )
                }

                dataSection

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
        .onAppear {
            if backupViewModel == nil {
                backupViewModel = SettingsBackupViewModel(container: modelContext.container)
            }
        }
        .sheet(isPresented: backupShareBinding) {
            if let url = backupViewModel?.exportShareURL {
                ShareSheet(items: [url])
            }
        }
        .fileImporter(
            isPresented: backupImportPickerBinding,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            guard let backupViewModel else { return }
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await backupViewModel.importBackup(from: url)
                }
            case .failure(let error):
                backupViewModel.errorMessage = error.localizedDescription
                backupViewModel.showError = true
            }
        }
        .alert(
            "Backup imported",
            isPresented: backupImportSuccessBinding
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if let message = backupViewModel?.importSuccessMessage {
                Text(message)
            }
        }
        .alert(
            "Backup failed",
            isPresented: backupErrorBinding
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if let message = backupViewModel?.errorMessage {
                Text(message)
            }
        }
    }

    @ViewBuilder
    private var dataSection: some View {
        Section {
            if let backupViewModel {
                Button {
                    Task {
                        await backupViewModel.exportBackup()
                    }
                } label: {
                    HStack {
                        Text("Export backup")
                            .foregroundStyle(Color("TextPrimary"))
                        Spacer()
                        if backupViewModel.isExporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(backupViewModel.isExporting)

                Button {
                    backupViewModel.showImportPicker = true
                } label: {
                    HStack {
                        Text("Import backup")
                            .foregroundStyle(Color("TextPrimary"))
                        Spacer()
                        if backupViewModel.isImporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(backupViewModel.isImporting)

                HStack {
                    Text("Last exported")
                        .foregroundStyle(Color("TextPrimary"))
                    Spacer()
                    Text(backupViewModel.lastExportedLabel)
                        .font(.metadataCaption)
                        .foregroundStyle(Color("TextSecondary"))
                }

                placeholderRow(
                    title: "Re-import health data",
                    detail: "Use Profile > Import"
                )
                placeholderRow(
                    title: "Reset local store",
                    detail: "Coming soon"
                )
            }
        } header: {
            Text("Data")
        } footer: {
            Text(
                "Export saves workouts, profile, goals, bodyweight log, and custom exercises. Health metrics and embeddings are not included."
            )
        }
    }

    private var backupShareBinding: Binding<Bool> {
        Binding(
            get: { backupViewModel?.showExportShare ?? false },
            set: { isPresented in
                guard let backupViewModel else { return }
                if isPresented {
                    backupViewModel.showExportShare = true
                } else {
                    backupViewModel.clearExportShare()
                }
            }
        )
    }

    private var backupImportPickerBinding: Binding<Bool> {
        Binding(
            get: { backupViewModel?.showImportPicker ?? false },
            set: { backupViewModel?.showImportPicker = $0 }
        )
    }

    private var backupImportSuccessBinding: Binding<Bool> {
        Binding(
            get: { backupViewModel?.showImportSuccess ?? false },
            set: { backupViewModel?.showImportSuccess = $0 }
        )
    }

    private var backupErrorBinding: Binding<Bool> {
        Binding(
            get: { backupViewModel?.showError ?? false },
            set: { backupViewModel?.showError = $0 }
        )
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }

    private var recoveryCalendarHintsDetail: String {
        let count = recoveryPreferences.calendarHintPhrases.count
        if count == 0 { return "None" }
        return "\(count) phrase\(count == 1 ? "" : "s")"
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

    private var briefingTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = notificationPreferences.briefingHour
                components.minute = notificationPreferences.briefingMinute
                return Calendar.current.date(from: components)
                    ?? Calendar.current.startOfDay(for: Date())
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                notificationPreferences.briefingHour = parts.hour ?? NotificationPreferences.defaultHour
                notificationPreferences.briefingMinute = parts.minute ?? NotificationPreferences.defaultMinute
            }
        )
    }

    private func refreshDailyBriefingSchedule() {
        Task {
            await DailyBriefingScheduler.shared.refreshSchedule(in: modelContext)
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
    .environment(NotificationPreferences.shared)
    .environment(RecoveryPreferences.shared)
    .environment(CoachPreferences.shared)
    .modelContainer(try! SignalModelContainer.make(inMemoryOnly: true))
}
