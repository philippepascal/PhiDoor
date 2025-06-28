//
//  PhiDoorWatchApp.swift
//  PhiDoorWatch Watch App
//
//  Created by Philippe Pascal on 2025/6/26.
//

import SwiftUI
import CryptoKit
import WatchKit
import ClockKit

@main
struct PhiDoorWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}

struct WatchContentView: View {
    var body: some View {
        NavigationView {
            VStack {
//                Spacer()

                Button(action: {
                    WKInterfaceDevice.current().play(.click)

                }) {
                    Label("Open Door", systemImage: "lock.open.fill")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)

                Spacer()

                NavigationLink(destination: WatchSettingsView()) {
                    Label("Settings", systemImage: "gearshape")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
                .tint(.blue.opacity(0.7))
            }
//            .padding()
        }
        .onOpenURL { url in
            if url.scheme == "phidoor", url.host == "open" {
                DoorAccessManager.shared.openDoor() { success in
                    if success {
                        WKInterfaceDevice.current().play(.success)
                    } else {
                        WKInterfaceDevice.current().play(.failure)
                    }
                }
            }
        }
    }
}

struct WatchSettingsView: View {
    @AppStorage("serverURL") private var serverURL: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                TextField("Server URL", text: $serverURL)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                Button(action: {
                    DoorAccessManager.shared.register()
                }) {
                    Label("Register", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button(action: {
                    DoorAccessManager.shared.reset()
                }) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
//            .padding()
        }
//        .navigationTitle("Settings")
    }
}
#Preview {
    WatchContentView()
}

#Preview {
    WatchSettingsView()
}
