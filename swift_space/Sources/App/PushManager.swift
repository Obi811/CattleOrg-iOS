import SwiftUI
import UIKit
import UserNotifications
import Observation
import os.log

private let pushLogger = Logger(subsystem: "com.cattleorg.app", category: "Push")

// MARK: - Deep-Link-Ziel einer Push-Mitteilung
enum PushTarget: Equatable {
    /// Aufgaben-Tab; optionaler Filter aus einer Sammel-Mitteilung
    /// (Werte: `traechtigkeit`, `hemmstoff`, `weiterbehandlung`).
    case tasks(filter: String?)
    case cattle(id: String)
}

// MARK: - PushRouter
// Teilt den APNs-Geräte-Token und das Deep-Link-Ziel mit der SwiftUI-Oberfläche.
@Observable
@MainActor
final class PushRouter {
    static let shared = PushRouter()
    /// Hex-String des APNs-Geräte-Tokens (wird an den Server gesendet).
    var deviceTokenHex: String?
    /// Ausstehendes Ziel, zu dem nach einem Tap auf eine Mitteilung navigiert werden soll.
    var pendingTarget: PushTarget?
    /// Aktiver Aufgaben-Filter aus einer Sammel-Mitteilung (wird von der Aufgaben-Ansicht gelesen).
    var taskFilter: String?
    /// Voreinstellung für die Tierliste (z. B. "trockensteher" oder "milchkuh"), gesetzt von einer Dashboard-Kachel.
    var cattlePreset: String?
    private init() {}
}

// MARK: - AppDelegate (APNs-Registrierung + Mitteilungs-Handling)
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Wenn der Benutzer die Erlaubnis bereits erteilt hat, erneut bei APNs registrieren
        // (Geräte-Token kann sich ändern und muss bei jedem Start aktualisiert werden).
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
        return true
    }

    // Erfolgreiche APNs-Registrierung – Geräte-Token empfangen
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        pushLogger.info("APNs-Geräte-Token empfangen (\(hex.count) Zeichen)")
        Task { @MainActor in
            PushRouter.shared.deviceTokenHex = hex
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        pushLogger.error("APNs-Registrierung fehlgeschlagen: \(error.localizedDescription)")
    }

    // Mitteilung während die App im Vordergrund ist – trotzdem anzeigen
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }

    // Tap auf eine Mitteilung – Deep-Link auflösen
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        let target = Self.target(from: userInfo)
        await MainActor.run {
            PushRouter.shared.pendingTarget = target
        }
    }

    /// Wertet die Custom-Felder des Payloads aus (`type`, `target`, `filter`, `cattle_id`).
    static func target(from userInfo: [AnyHashable: Any]) -> PushTarget {
        let type = userInfo["type"] as? String
        let targetField = userInfo["target"] as? String
        // Sammel-Mitteilung (§4.1): in den Aufgaben-Tab springen, optional vorfiltern.
        if type == "summary" || targetField == "tasks" {
            let filter = (userInfo["filter"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return .tasks(filter: filter)
        }
        // Einzel-Mitteilung mit betroffenem Tier → Tierdetail.
        if let cid = userInfo["cattle_id"] {
            let str: String?
            switch cid {
            case let s as String: str = s.isEmpty ? nil : s
            case let n as NSNumber: str = n.stringValue
            case let i as Int: str = String(i)
            default: str = nil
            }
            if let s = str { return .cattle(id: s) }
        }
        return .tasks(filter: nil)
    }
}
