//
//  ContentView.swift
//  SignalWatch Watch App
//
//  Created by Cameron Rogers on 03/06/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            Text("Signal")
                .font(.headline)
            Text("Open Signal on your iPhone to sync.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
