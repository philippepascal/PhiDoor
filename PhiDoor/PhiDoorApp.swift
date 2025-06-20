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
                        DoorAccessManager.shared.openDoor()
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

// MARK: - Core Access Manager
class DoorAccessManager {
    static let shared = DoorAccessManager()
    @AppStorage("serverURL") private var serverURL: String = ""

    func register() {
        // 1. Generate or reuse UUID & save
        let uuid: String
        if let savedUUID = UserDefaults.standard.string(forKey: "deviceUUID") {
            uuid = savedUUID
            print("Using existing UUID: \(uuid)")
        } else {
            uuid = UUID().uuidString
            UserDefaults.standard.set(uuid, forKey: "deviceUUID")
            print("Generated new UUID: \(uuid)")
        }
        let tag = "philippe.phidoor.keypair".data(using: .utf8)!

        guard let (privateKey, publicKeyData) = getOrCreateKeyPair(tag: tag) else {
            return
        }

        let fullKeyData = spkiEncodeRSAPublicKey(pkcs1Key: publicKeyData)
        let base64 = fullKeyData.base64EncodedString(options: [.lineLength64Characters])
        let publicKeyPEM = """
        -----BEGIN PUBLIC KEY-----
        \(base64)
        -----END PUBLIC KEY-----
        """
        print("📤 Public key PEM:\n\(publicKeyPEM)")

        // 3. Send public key and UUID to serverURL/register
        guard let url = URL(string: "\(serverURL)/register") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "id": uuid,
            "pem_public_key": publicKeyPEM
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        if let httpBody = request.httpBody, let jsonString = String(data: httpBody, encoding: .utf8) {
            print("📦 Request body to /register:\n\(jsonString)")
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else { return }
            if let responseJSON = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let secretBase64 = responseJSON["secret"],
               let secretData = Data(base64Encoded: secretBase64) {
                UserDefaults.standard.set(secretData, forKey: "totpSecret")
                print("Received and stored TOTP secret.")
            }
        }.resume()
    }

    func reset() {
        // 1. Delete UUID
        // 1. Delete UUID and TOTP secret
        UserDefaults.standard.removeObject(forKey: "deviceUUID")
        // 2. Delete keypair from Keychain
        let tag = "philippe.phidoor.keypair".data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            print("🗑️ Deleted key pair from keychain")
        } else if status == errSecItemNotFound {
            print("ℹ️ Key pair not found in keychain")
        } else {
            print("⚠️ Failed to delete key pair: \(status)")
        }
    }

    func openDoor() {
        // Use serverURL for operate endpoint
        print("Sending open request to: \(serverURL)/operate")
        // 1. Generate TOTP
        // 2. Generate salt
        // 3. Sign the message with Secure Enclave key
        // 4. Send signed JSON to server
        let secret = loadSharedSecret()
        let totp = TOTPGenerator.generateTOTP(secret: secret)
        print("TOTP: \(totp)")
    }

    private func loadSharedSecret() -> Data {
        return UserDefaults.standard.data(forKey: "totpSecret") ?? Data()
    }
    
    private func getOrCreateKeyPair(tag: Data) -> (SecKey, Data)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess {
            let existingPrivateKey = item as! SecKey
            if let existingPublicKey = SecKeyCopyPublicKey(existingPrivateKey),
               let publicKeyData = SecKeyCopyExternalRepresentation(existingPublicKey, nil) as Data? {
                print("✅ Reusing existing key pair")
                return (existingPrivateKey, publicKeyData)
            }
        }

        let accessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessible as String: accessible
            ]
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            print("Error generating private key: \(error!.takeRetainedValue() as Error)")
            return nil
        }
        print("✅ Private key generated and stored in key chain")

        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            print("Failed to get public key: \(error!.takeRetainedValue() as Error)")
            return nil
        }

        return (privateKey, publicKeyData)
    }

    
    func spkiEncodeRSAPublicKey(pkcs1Key: Data) -> Data {
        // SPKI header for rsaEncryption {OID + NULL}
        let spkiPrefix: [UInt8] = [
            0x30, 0x0D,                         // SEQUENCE (13 bytes)
            0x06, 0x09,                         // OID (9 bytes)
            0x2A, 0x86, 0x48, 0x86, 0xF7,
            0x0D, 0x01, 0x01, 0x01,             // rsaEncryption OID
            0x05, 0x00                          // NULL
        ]

        let bitStringPrefix: [UInt8] = [0x00]  // required 0 padding in BIT STRING

        // Build BIT STRING with padding byte
        let bitString = bitStringPrefix + [UInt8](pkcs1Key)

        // Encode the inner SEQUENCE (spkiPrefix + BIT STRING)
        let innerSequence = derEncodeSequence(Data(spkiPrefix), derEncodeBitString(bitString))

        return innerSequence
    }
    
    func derEncodeSequence(_ components: Data...) -> Data {
        let body = components.reduce(Data(), +)
        return Data([0x30]) + derEncodeLength(body.count) + body
    }

    func derEncodeBitString(_ bytes: [UInt8]) -> Data {
        return Data([0x03]) + derEncodeLength(bytes.count) + Data(bytes)
    }

    func derEncodeLength(_ length: Int) -> Data {
        if length < 128 {
            return Data([UInt8(length)])
        } else {
            let lengthBytes = withUnsafeBytes(of: UInt32(length).bigEndian, Array.init).drop { $0 == 0 }
            return Data([0x80 | UInt8(lengthBytes.count)]) + lengthBytes
        }
    }
    
}

// MARK: - TOTP Generator
struct TOTPGenerator {
    static func generateTOTP(secret: Data, timeInterval: TimeInterval = 30, digits: Int = 6) -> String {
        let counter = UInt64(Date().timeIntervalSince1970 / timeInterval)
        var counterBigEndian = counter.bigEndian
        let counterData = Data(bytes: &counterBigEndian, count: MemoryLayout.size(ofValue: counterBigEndian))

        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: SymmetricKey(data: secret))
        let hash = Data(hmac)

        let offset = Int(hash.last! & 0x0f)
        let truncatedHash = hash.subdata(in: offset..<offset+4)
        var number = UInt32(bigEndian: truncatedHash.withUnsafeBytes { $0.load(as: UInt32.self) })
        number &= 0x7fffffff

        let otp = number % UInt32(pow(10, Float(digits)))
        return String(format: "%0*u", digits, otp)
    }
}
