# CattleOrg iOS

Native iOS-App (Swift / SwiftUI) als Begleit-App zur betriebseigenen Rinderverwaltung **CattleOrg**.
Die App greift ausschließlich über die bestehende Token-API des Server-Projekts
([Obi811/CattleOrg](https://github.com/Obi811/CattleOrg)) zu – sie enthält kein eigenes Backend.

## Funktionen
- Anmeldung mit bestehendem Konto (Token-Speicherung in der iOS-Keychain)
- Betriebsauswahl (Mehrbetriebsfähigkeit)
- Übersicht fälliger Aufgaben (Wartezeiten, Weiterbehandlungen, Hemmstoffproben, TU-Kontrollen)
- Tierliste mit Ohrmarken-Suche und Status-/Wartezeit-Anzeige
- Tierdetail mit Behandlungen, Besamungen, Trächtigkeitskontrollen, Hemmstoffproben
- Schnell-Erfassung und „Abgang melden“
- Rollen-/Rechte-Berücksichtigung (Lesen/Schreiben)
- Push-Benachrichtigungen (APNs, Deep-Link zum Tier)

## Projektstruktur
```
swift_space/
  Sources/
    App/      App-Entry, Konfiguration, API-Client, Session, Keychain, Push
    Models/   Datenmodelle (Codable)
    Views/    SwiftUI-Views (eine Hauptview pro Datei)
  Assets.xcassets/
  project.yml           (Projekt wird hieraus generiert)
  Config.xcconfig       (enthält API_BASE_URL)
app_store_assets/       Datenschutz-/Support-Seiten, Store-Screenshot
```

## Konfiguration
Die Basis-URL der API wird über `API_BASE_URL` in `swift_space/Config.xcconfig`
gesetzt (Wert: Produktions-API-Endpunkt). Es sind **keine** Geheimnisse im Repo
abgelegt.

## Build
Deployment-Target iOS 18.0, Swift 5.10. Das Xcode-Projekt wird aus `project.yml`
(XcodeGen) erzeugt. Der Vertrieb erfolgt über TestFlight / App Store.

## Hinweis
Die Dateien unter `app_store_assets/` mit Zugangs-/Kontaktdaten (Listing-Kit) sind
bewusst **nicht** Teil dieses öffentlichen Repos.
