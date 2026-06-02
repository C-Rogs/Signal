import SwiftUI

struct DashboardWindowPicker: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        Picker("Range", selection: $viewModel.selectedWindow) {
            ForEach(RecoveryWindow.allCases) { window in
                Text(window.label).tag(window)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: viewModel.selectedWindow) { _, _ in
            viewModel.recomputeSeriesForSelectedWindow()
        }
    }
}
