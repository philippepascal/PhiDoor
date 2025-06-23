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

        URLSession.shared.dataTask(with: request) { [self] data, response, error in
            guard let data = data, error == nil else { return }
            print("repsonse: \(String(data: data, encoding: .utf8) ?? "No data"))")
            if let responseJSON = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let secretBase64 = responseJSON["encrypted_secret"],
               let encryptedSecret = Data(base64Encoded: secretBase64) {
                print("🔒 Encrypted secret (base64): \(secretBase64)")
                var error: Unmanaged<CFError>?
                guard let decryptedSecret = SecKeyCreateDecryptedData(
                    privateKey,
                    .rsaEncryptionPKCS1,
                    encryptedSecret as CFData,
                    &error
                ) as Data? else {
                    print("Failed to decrypt secret: \(error!.takeRetainedValue() as Error)")
                    return
                }
                let decryptedBase64 = decryptedSecret.base64EncodedString()
                print("🔓 Decrypted secret (base64): \(decryptedBase64)")

                guard let base32String = String(data: decryptedSecret, encoding: .utf8) else {
                    print("Failed to decode secret as UTF-8 string")
                    return
                }

                print("Decoded Base32: \(base32String)")
                
                guard let rawSecret = self.base32DecodeToData(base32String) else {
                    print("Failed to decode Base32 TOTP secret")
                    return
                }

                UserDefaults.standard.set(rawSecret, forKey: "totpSecret")
                print("🔐 Decrypted and decoded TOTP secret stored.")
            }
        }.resume()
    }

    func reset() {
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
        print("Sending open request to: \(serverURL)/operate")
        
        // 1. Generate TOTP
        let secret = loadSharedSecret()
        let totp = TOTPGenerator.generateTOTP(secret: secret)
        print("🔢 Generated TOTP: \(totp)")
        
        // 2. Generate random salt
        var saltBytes = [UInt8](repeating: 0, count: 16)
        let result = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        guard result == errSecSuccess else {
            print("Failed to generate salt")
            return
        }
        let salt = Data(saltBytes)
        let saltBase64 = salt.base64EncodedString()
        
        // 3. Sign the message
        guard let uuid = UserDefaults.standard.string(forKey: "deviceUUID") else { return }
        let jsonToSign: [String: String] = [
            "token": totp,
            "_salt": saltBase64
        ]
        guard let messageData = try? JSONSerialization.data(withJSONObject: jsonToSign, options: [.sortedKeys]) else {
            print("Failed to create JSON message")
            return
        }

        let tag = "philippe.phidoor.keypair".data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            print("Private key not found")
            return
        }
        let privateKey = item as! SecKey

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            messageData as CFData,
            &error
        ) as Data? else {
            print("Signature failed: \(error!.takeRetainedValue() as Error)")
            return
        }

        let signatureBase64 = signature.base64EncodedString()
        print("✍️ Signature (base64): \(signatureBase64)")
        
        // 4. Send signed request
        guard let url = URL(string: "\(serverURL)/operate") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let totpMessage = String(data: messageData, encoding: .utf8) ?? ""
        let body: [String: String] = [
            "id": uuid,
            "totp_message": totpMessage,
            "signature": signatureBase64
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        if let httpBody = request.httpBody, let jsonString = String(data: httpBody, encoding: .utf8) {
            print("📦 Request body to /operate:\n\(jsonString)")
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Error sending request: \(error)")
            } else {
                print("✅ Request sent successfully")
            }
        }.resume()
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
    
    private func base32DecodeToData(_ base32String: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var cleaned = base32String.uppercased().replacingOccurrences(of: "=", with: "")
        var bits = ""
        for c in cleaned {
            guard let index = alphabet.firstIndex(of: c) else { return nil }
            let val = alphabet.distance(from: alphabet.startIndex, to: index)
            let binary = String(val, radix: 2).leftPadding(toLength: 5, withPad: "0")
            bits += binary
        }

        var data = Data()
        for i in stride(from: 0, to: bits.count, by: 8) {
            let chunk = bits.dropFirst(i).prefix(8)
            if chunk.count == 8, let byte = UInt8(chunk, radix: 2) {
                data.append(byte)
            }
        }
        return data
    }
    
}

// MARK: - TOTP Generator
struct TOTPGenerator {
    static func generateTOTP(secret: Data, timeInterval: TimeInterval = 30, digits: Int = 6) -> String {
        let counter = UInt64(Date().timeIntervalSince1970 / timeInterval)
        var counterBigEndian = counter.bigEndian
        let counterData = Data(bytes: &counterBigEndian, count: MemoryLayout.size(ofValue: counterBigEndian))

        let hmac = HMAC<SHA256>.authenticationCode(for: counterData, using: SymmetricKey(data: secret))
        let hash = Data(hmac)

        let offset = Int(hash.last! & 0x0f)
        let truncatedHash = hash.subdata(in: offset..<offset+4)
        var number = UInt32(bigEndian: truncatedHash.withUnsafeBytes { $0.load(as: UInt32.self) })
        number &= 0x7fffffff

        let otp = number % UInt32(pow(10, Float(digits)))
        return String(format: "%0*u", digits, otp)
    }
}

private extension String {
    func leftPadding(toLength: Int, withPad: String) -> String {
        if self.count < toLength {
            return String(repeating: withPad, count: toLength - self.count) + self
        } else {
            return String(self.suffix(toLength))
        }
    }
}
