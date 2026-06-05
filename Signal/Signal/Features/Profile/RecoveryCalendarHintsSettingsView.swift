import SwiftUI

struct RecoveryCalendarHintsSettingsView: View {
    @Environment(RecoveryPreferences.self) private var recoveryPreferences
    @State private var draftPhrase = ""

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    TextField("Add phrase", text: $draftPhrase)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Add") {
                        recoveryPreferences.addCalendarHintPhrase(draftPhrase)
                        draftPhrase = ""
                    }
                    .disabled(draftPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if recoveryPreferences.calendarHintPhrases.isEmpty {
                    Text("No custom phrases yet.")
                        .font(.metadataCaption)
                        .foregroundStyle(Color("TextSecondary"))
                } else {
                    ForEach(Array(recoveryPreferences.calendarHintPhrases.enumerated()), id: \.offset) { index, phrase in
                        HStack {
                            Text(phrase)
                                .foregroundStyle(Color("TextPrimary"))
                            Spacer()
                            Button(role: .destructive) {
                                recoveryPreferences.removeCalendarHintPhrase(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                Text("Calendar hints")
            } footer: {
                Text(
                    "Signal matches last night's calendar event titles against these phrases on device. Examples: pub night, beer o'clock."
                )
            }
        }
        .navigationTitle("Recovery")
        .navigationBarTitleDisplayMode(.inline)
    }
}
