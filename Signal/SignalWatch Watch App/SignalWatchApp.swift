//
//  SignalWatchApp.swift
//  SignalWatch Watch App
//
//  Created by Cameron Rogers on 03/06/2026.
//

import SwiftUI

@main
struct SignalWatch_Watch_AppApp: App {
    @State private var receiver = WatchConnectivityReceiver()

    var body: some Scene {
        WindowGroup {
            ContentView(receiver: receiver)
                .onAppear {
                    receiver.activate()
                }
        }
    }
}
