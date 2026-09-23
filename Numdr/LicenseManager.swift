import Foundation
import SwiftUI
import Combine
import Security

/// Lemon Squeezy license key licensing (activate / validate / deactivate).
/// Public License API — no API secret required. Feature gating: trial OR licensed.
@MainActor
final class LicenseManager: ObservableObject {
    /// Replace with your Lemon Squeezy checkout URL (Store → Product → Share).
    static let checkoutURLString = "https://YOUR_STORE.lemonsqueezy.com/checkout/buy/YOUR_VARIANT_ID"

    /// Days the app stays unlocked offline after a successful activate/validate.
    private let offlineGraceDays = 21

    @Published var isProUnlocked: Bool = false // Licensed (or offline grace)
    @Published var isPresentingPaywall: Bool = false
    @Published var isBusy: Bool = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var licenseKeyInput: String = ""

    /// Masked key preview for Settings (never show full key in UI by default).
    @Published private(set) var hasStoredLicense: Bool = false

    private let keychain = LicenseKeychain()
    private let lastValidatedKey = "NumdrLicenseLastValidatedAt"
    private let instanceIDKey = "NumdrLicenseInstanceID"
    private let unlockedFlagKey = "NumdrProUnlocked"

    init() {
        hasStoredLicense = (keychain.loadLicenseKey() != nil)
        isProUnlocked = UserDefaults.standard.bool(forKey: unlockedFlagKey)
        Task { await refreshLicenseStatus() }
    }

    func showPaywall() {
        isPresentingPaywall = true
        errorMessage = nil
        statusMessage = nil
        if licenseKeyInput.isEmpty, let existing = keychain.loadLicenseKey() {
            licenseKeyInput = existing
        }
    }

    func openCheckout() {
        guard let url = URL(string: Self.checkoutURLString) else {
            errorMessage = "Checkout URL is not configured. See MONETIZATION.md."
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Activate a pasted license key against Lemon Squeezy.
    func activateLicense(key rawKey: String? = nil) async {
        let key = (rawKey ?? licenseKeyInput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorMessage = "Please enter a license key."
            return
        }

        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        statusMessage = nil

        // If this exact key is already activated on this Mac, validate instead of consuming another seat.
        if let existing = keychain.loadLicenseKey(),
           existing == key,
           UserDefaults.standard.string(forKey: instanceIDKey) != nil {
            await refreshLicenseStatus()
            if isProUnlocked {
                statusMessage = "License validated."
                isPresentingPaywall = false
            }
            return
        }

        let instanceName = Self.defaultInstanceName()
        do {
            let response = try await LemonSqueezyLicenseAPI.activate(
                licenseKey: key,
                instanceName: instanceName
            )
            if response.activated == true, let instanceID = response.instance?.id {
                keychain.saveLicenseKey(key)
                UserDefaults.standard.set(instanceID, forKey: instanceIDKey)
                recordSuccessfulValidation()
                setUnlocked(true)
                hasStoredLicense = true
                statusMessage = "License activated."
                isPresentingPaywall = false
            } else {
                errorMessage = response.error ?? "Activation failed."
                setUnlocked(false)
            }
        } catch {
            errorMessage = friendlyNetworkError(error)
        }
    }

    /// Validate stored license (or pasted key) with Lemon Squeezy; applies offline grace on network failure.
    func refreshLicenseStatus() async {
        guard let key = keychain.loadLicenseKey() else {
            // No key — not licensed (trial may still apply elsewhere).
            if !isWithinOfflineGrace() {
                setUnlocked(false)
            }
            hasStoredLicense = false
            return
        }
        hasStoredLicense = true

        let instanceID = UserDefaults.standard.string(forKey: instanceIDKey)
        do {
            let response = try await LemonSqueezyLicenseAPI.validate(
                licenseKey: key,
                instanceID: instanceID
            )
            if response.valid == true {
                recordSuccessfulValidation()
                setUnlocked(true)
                statusMessage = nil
            } else {
                // Explicit invalid from server — revoke local unlock (not offline).
                setUnlocked(false)
                clearOfflineGrace()
                errorMessage = response.error ?? "License is no longer valid."
            }
        } catch {
            // Offline / network error: keep unlocked within grace window.
            if isWithinOfflineGrace() {
                setUnlocked(true)
            } else {
                setUnlocked(false)
                errorMessage = "Could not validate license online, and offline grace has expired."
            }
        }
    }

    /// Deactivate this device's instance on Lemon Squeezy and clear local license.
    func deactivateLicense() async {
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        statusMessage = nil

        guard let key = keychain.loadLicenseKey() else {
            clearLocalLicense()
            statusMessage = "No license stored."
            return
        }
        guard let instanceID = UserDefaults.standard.string(forKey: instanceIDKey) else {
            // No instance id — clear locally anyway.
            clearLocalLicense()
            statusMessage = "Local license cleared."
            return
        }

        do {
            let response = try await LemonSqueezyLicenseAPI.deactivate(
                licenseKey: key,
                instanceID: instanceID
            )
            if response.deactivated == true {
                clearLocalLicense()
                statusMessage = "License deactivated on this Mac."
            } else {
                errorMessage = response.error ?? "Deactivation failed."
            }
        } catch {
            errorMessage = friendlyNetworkError(error)
        }
    }

    // MARK: - Persistence helpers

    private func setUnlocked(_ unlocked: Bool) {
        UserDefaults.standard.set(unlocked, forKey: unlockedFlagKey)
        isProUnlocked = unlocked
    }

    private func recordSuccessfulValidation() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastValidatedKey)
    }

    private func clearOfflineGrace() {
        UserDefaults.standard.removeObject(forKey: lastValidatedKey)
    }

    private func isWithinOfflineGrace() -> Bool {
        let ts = UserDefaults.standard.double(forKey: lastValidatedKey)
        guard ts > 0 else { return false }
        let last = Date(timeIntervalSince1970: ts)
        guard let deadline = Calendar.current.date(byAdding: .day, value: offlineGraceDays, to: last) else {
            return false
        }
        return Date() < deadline
    }

    private func clearLocalLicense() {
        keychain.deleteLicenseKey()
        UserDefaults.standard.removeObject(forKey: instanceIDKey)
        clearOfflineGrace()
        setUnlocked(false)
        hasStoredLicense = false
        licenseKeyInput = ""
    }

    private static func defaultInstanceName() -> String {
        let host = Host.current().localizedName ?? "Mac"
        let shortID = String(UUID().uuidString.prefix(8))
        return "Numdr-\(host)-\(shortID)"
    }

    private func friendlyNetworkError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .timedOut, .networkConnectionLost:
                return "No network connection. Try again when online."
            default:
                break
            }
        }
        return (error as NSError).localizedDescription
    }
}

// MARK: - Lemon Squeezy License API (public endpoints — no API secret)

enum LemonSqueezyLicenseAPI {
    private static let base = "https://api.lemonsqueezy.com/v1/licenses"

    struct ActivateResponse: Decodable {
        let activated: Bool?
        let error: String?
        let licenseKey: LicenseKeyInfo?
        let instance: InstanceInfo?

        enum CodingKeys: String, CodingKey {
            case activated, error, instance
            case licenseKey = "license_key"
        }
    }

    struct ValidateResponse: Decodable {
        let valid: Bool?
        let error: String?
        let licenseKey: LicenseKeyInfo?
        let instance: InstanceInfo?

        enum CodingKeys: String, CodingKey {
            case valid, error, instance
            case licenseKey = "license_key"
        }
    }

    struct DeactivateResponse: Decodable {
        let deactivated: Bool?
        let error: String?
        let licenseKey: LicenseKeyInfo?

        enum CodingKeys: String, CodingKey {
            case deactivated, error
            case licenseKey = "license_key"
        }
    }

    struct LicenseKeyInfo: Decodable {
        let id: Int?
        let status: String?
        let key: String?
        let activationLimit: Int?
        let activationUsage: Int?
        let createdAt: String?
        let expiresAt: String?

        enum CodingKeys: String, CodingKey {
            case id, status, key
            case activationLimit = "activation_limit"
            case activationUsage = "activation_usage"
            case createdAt = "created_at"
            case expiresAt = "expires_at"
        }
    }

    struct InstanceInfo: Decodable {
        let id: String?
        let name: String?
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id, name
            case createdAt = "created_at"
        }
    }

    static func activate(licenseKey: String, instanceName: String) async throws -> ActivateResponse {
        try await postForm(
            path: "/activate",
            fields: [
                "license_key": licenseKey,
                "instance_name": instanceName
            ],
            as: ActivateResponse.self
        )
    }

    static func validate(licenseKey: String, instanceID: String?) async throws -> ValidateResponse {
        var fields = ["license_key": licenseKey]
        if let instanceID, !instanceID.isEmpty {
            fields["instance_id"] = instanceID
        }
        return try await postForm(path: "/validate", fields: fields, as: ValidateResponse.self)
    }

    static func deactivate(licenseKey: String, instanceID: String) async throws -> DeactivateResponse {
        try await postForm(
            path: "/deactivate",
            fields: [
                "license_key": licenseKey,
                "instance_id": instanceID
            ],
            as: DeactivateResponse.self
        )
    }

    private static func postForm<T: Decodable>(
        path: String,
        fields: [String: String],
        as type: T.Type
    ) async throws -> T {
        guard let url = URL(string: base + path) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode(fields).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        // LS returns JSON bodies for both success and many 4xx cases.
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if !(200...299).contains(http.statusCode) {
                let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw NSError(
                    domain: "LemonSqueezyLicenseAPI",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }
            throw error
        }
    }

    private static func formEncode(_ fields: [String: String]) -> String {
        fields
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }
}

// MARK: - Keychain storage for license key (macOS)

final class LicenseKeychain {
    private let service = "com.controlx.Numdr.license"
    private let account = "lemonsqueezy-license-key"

    func saveLicenseKey(_ key: String) {
        deleteLicenseKey()
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func loadLicenseKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteLicenseKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
