// DoorControlApp.swift
// High-level app scaffold for iOS + watchOS

import SwiftUI
import CryptoKit

@main
struct DoorControlApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Main View
struct ContentView: View {
    var body: some View {
        NavigationView {
            ZStack(alignment: .topLeading) {
                VStack {
                    Spacer()

                    Button(action: {
                        let tapFeedback = UIImpactFeedbackGenerator(style: .light)
                        tapFeedback.impactOccurred()

                        DoorAccessManager.shared.openDoor { success in
                            let feedback = UINotificationFeedbackGenerator()
                            if success {
                                feedback.notificationOccurred(.success)
                            } else {
                                feedback.notificationOccurred(.error)
                            }
                        }
                    }) {
                        Text("Open Door")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(20)
                            .padding(.horizontal, 40)
                    }

                    Spacer()
                }

                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .padding()
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @AppStorage("serverURL") private var serverURL: String = ""

    var body: some View {
        VStack {
            Spacer().frame(height: 20)

            TextField("Server URL", text: $serverURL)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal, 40)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)

            Spacer()

            Button(action: {
                DoorAccessManager.shared.register()
            }) {
                Text("Register")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green)
                    .cornerRadius(12)
                    .padding(.horizontal, 40)
            }

            Spacer()

            Button(action: {
                DoorAccessManager.shared.reset()
            }) {
                Text("Reset")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.red)
                    .cornerRadius(8)
            }
            .padding(.bottom, 20)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
