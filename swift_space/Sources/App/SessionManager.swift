import Foundation
import UIKit
import Observation
import os.log

private let logger = Logger(subsystem: "com.cattleorg.app", category: "Session")

@Observable
@MainActor
final class SessionManager {
    var isLoading = true
    var isAuthenticated = false
    var currentUser: User?
    var farms: [Farm] = []
    var selectedFarm: Farm?
    var errorMessage: String?

    // Computed helpers
    var isDemo: Bool { selectedFarm?.is_demo == true }
    var canWrite: Bool {
        guard !isDemo else { return false }
        let role = selectedFarm?.role?.lowercased() ?? ""
        return role != "viewer"
    }
    var userName: String { currentUser?.username ?? "Benutzer" }
    var farmName: String { selectedFarm?.name ?? "" }

    init() {
        Task { await checkStoredAuth() }
    }

    func checkStoredAuth() async {
        guard let storedToken = KeychainHelper.authToken, !storedToken.isEmpty else {
            isLoading = false
            return
        }
        CattleAPI.token = storedToken
        do {
            let fetchedFarms = try await CattleAPI.fetchFarms()
            farms = fetchedFarms
            currentUser = loadStoredUser()
            isAuthenticated = true
            restoreFarmSelection()
            logger.info("Session restored successfully")
        } catch {
            logger.warning("Token validation failed: \(error.localizedDescription)")
            clearSession()
        }
        isLoading = false
    }

    func login(username: String, password: String) async throws {
        let response = try await CattleAPI.login(username: username, password: password)
        KeychainHelper.authToken = response.token
        CattleAPI.token = response.token
        currentUser = response.user
        farms = response.farms
        storeUser(response.user)
        isAuthenticated = true

        if farms.count == 1, let onlyFarm = farms.first {
            selectFarm(onlyFarm)
        }
        logger.info("Login successful for \(username)")
    }

    func logout() {
        // UI sofort auf Login umstellen; Netzwerk-Aufräumen läuft danach,
        // solange das Token noch gültig ist.
        let tokenToDelete = registeredDeviceToken
        isAuthenticated = false
        selectedFarm = nil
        Task {
            if let t = tokenToDelete {
                try? await CattleAPI.deleteDeviceToken(tokenValue: t)
            }
            await CattleAPI.logout()
            clearSession()
        }
        logger.info("User logged out")
    }

    // MARK: - Push / Geräte-Token
    private var registeredDeviceToken: String?

    /// Registriert den APNs-Geräte-Token beim Server (nur wenn angemeldet).
    func registerDeviceTokenIfPossible(_ hex: String) async {
        guard isAuthenticated, !hex.isEmpty, hex != registeredDeviceToken else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let body: [String: Any] = [
            "token": hex,
            "platform": "ios",
            "environment": environment,
            "device_name": UIDevice.current.name,
            "app_version": appVersion
        ]
        do {
            try await CattleAPI.registerDeviceToken(body)
            registeredDeviceToken = hex
            logger.info("Geräte-Token beim Server registriert")
        } catch {
            // Server-Endpunkt evtl. noch nicht vorhanden – kein harter Fehler für den Nutzer.
            logger.warning("Geräte-Token-Registrierung fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    func selectFarm(_ farm: Farm) {
        selectedFarm = farm
        CattleAPI.farmId = farm.id.value
        UserDefaults.standard.set(farm.id.value, forKey: "selectedFarmId")
    }

    func switchFarm() {
        selectedFarm = nil
        CattleAPI.farmId = nil
        UserDefaults.standard.removeObject(forKey: "selectedFarmId")
    }

    func handleCattleAPIError(_ error: Error) {
        if let apiErr = error as? CattleAPIError {
            switch apiErr {
            case .tokenExpired, .unauthorized:
                clearSession()
            default:
                break
            }
        }
    }

    // MARK: - Private
    private func clearSession() {
        KeychainHelper.authToken = nil
        CattleAPI.token = nil
        CattleAPI.farmId = nil
        currentUser = nil
        farms = []
        selectedFarm = nil
        isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: "selectedFarmId")
        UserDefaults.standard.removeObject(forKey: "storedUsername")
    }

    private func restoreFarmSelection() {
        if let savedId = UserDefaults.standard.string(forKey: "selectedFarmId"),
           let farm = farms.first(where: { $0.id.value == savedId }) {
            selectFarm(farm)
        } else if farms.count == 1, let only = farms.first {
            selectFarm(only)
        }
    }

    private func storeUser(_ user: User) {
        UserDefaults.standard.set(user.username, forKey: "storedUsername")
    }

    private func loadStoredUser() -> User? {
        guard let name = UserDefaults.standard.string(forKey: "storedUsername") else { return nil }
        return User(id: FlexibleID(""), username: name, is_admin: nil)
    }
}
