import SwiftData
import SwiftUI

struct CoachPlaceholderView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            screenBackground
                .ignoresSafeArea()

            List {
                Section {
                    NavigationLink {
                        InsightsView()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "lightbulb")
                                .font(.title3)
                                .foregroundStyle(Color("Primary"))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Insights")
                                    .font(.cardLabel)
                                    .foregroundStyle(Color("TextPrimary"))
                                Text("Rule-based training and recovery notes")
                                    .font(.metadataCaption)
                                    .foregroundStyle(Color("TextSecondary"))
                            }
                        }
                    }
                }

                Section {
                    ContentUnavailableView {
                        Label("Coach", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("On-device coaching chat arrives in a later milestone.")
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.large)
    }

    private var screenBackground: Color {
        colorScheme == .dark ? .black : Color("Background")
    }
}

#Preview {
    NavigationStack {
        CoachPlaceholderView()
    }
    .modelContainer(try! SignalModelContainer.make(inMemoryOnly: true))
}
