import SwiftData
import SwiftUI

struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    private let existingRoutine: Routine?

    @State private var workingRoutine: Routine?
    @State private var name: String
    @State private var showPicker = false
    @State private var errorMessage: String?

    init(routine: Routine?) {
        existingRoutine = routine
        _workingRoutine = State(initialValue: routine)
        _name = State(initialValue: routine?.name ?? "")
    }

    private var slots: [RoutineExercise] {
        (workingRoutine?.exercises ?? []).sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Routine name", text: $name)
                }

                Section("Exercises") {
                    if slots.isEmpty {
                        Text("No exercises yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(slots, id: \.persistentModelID) { slot in
                        NavigationLink {
                            RoutineExerciseEditorView(slot: slot)
                        } label: {
                            exerciseRowLabel(slot)
                        }
                    }
                    .onDelete(perform: deleteSlots)
                    .onMove(perform: moveSlots)

                    Button {
                        showPicker = true
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                    }
                    .frame(minHeight: 44)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(screenBackground.ignoresSafeArea())
            .navigationTitle(existingRoutine == nil ? "New Routine" : "Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView { catalog in
                    addSlot(catalog: catalog)
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseRowLabel(_ slot: RoutineExercise) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(slot.catalogEntry?.canonicalName ?? slot.exerciseTitleFallback ?? "Exercise")
                .font(.body)
            if slot.hasPresets {
                Text("\(slot.presetSetCount) sets · \(slot.restDurationSeconds)s rest")
                    .font(.metadataCaption)
                    .foregroundStyle(Color("TextSecondary"))
            }
        }
    }

    private var screenBackground: Color {
        TrainChrome.screenBackground(colorScheme: colorScheme)
    }

    private func ensureRoutine() -> Routine {
        if let workingRoutine {
            return workingRoutine
        }
        let created = Routine(name: name)
        modelContext.insert(created)
        workingRoutine = created
        return created
    }

    private func addSlot(catalog: ExerciseCatalog) {
        let target = ensureRoutine()
        let order = (target.exercises.map(\.order).max() ?? -1) + 1
        let slot = RoutineExercise(order: order, catalogEntry: catalog)
        slot.routine = target
        target.exercises.append(slot)
        try? modelContext.save()
    }

    private func deleteSlots(at offsets: IndexSet) {
        guard let workingRoutine else { return }
        var ordered = slots
        let removed = offsets.map { ordered[$0] }
        ordered.remove(atOffsets: offsets)
        for slot in removed {
            modelContext.delete(slot)
        }
        for (index, slot) in ordered.enumerated() {
            slot.order = index
        }
        workingRoutine.exercises = ordered
        try? modelContext.save()
    }

    private func moveSlots(from source: IndexSet, to destination: Int) {
        guard workingRoutine != nil else { return }
        var ordered = slots
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, slot) in ordered.enumerated() {
            slot.order = index
        }
        try? modelContext.save()
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let target = ensureRoutine()
        target.name = trimmed
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
