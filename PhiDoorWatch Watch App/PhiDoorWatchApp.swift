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
                Spacer()

                Button(action: {
                    DoorAccessManager.shared.openDoor()
                }) {
                    Text("Open Door")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(12)
                }

                Spacer()

                NavigationLink(destination: WatchSettingsView()) {
                    Image(systemName: "gearshape")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .padding(.top, 8)
                }
            }
            .padding()
        }
        .onOpenURL { url in
            if url.scheme == "phidoor", url.host == "open" {
                DoorAccessManager.shared.openDoor()
            }
        }
    }
}

struct WatchSettingsView: View {
    @AppStorage("serverURL") private var serverURL: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TextField("Server URL", text: $serverURL)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                Button(action: {
                    DoorAccessManager.shared.register()
                }) {
                    Text("Register")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .cornerRadius(10)
                }

                Button(action: {
                    DoorAccessManager.shared.reset()
                }) {
                    Text("Reset")
                        .font(.footnote)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.red)
                        .cornerRadius(8)
                }
            }
            .padding()
        }
        .navigationTitle("Settings")
    }
}
