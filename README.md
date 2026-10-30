# CattleOrg iOS

Native iOS-App (Swift / SwiftUI) als Begleit-App zur betriebseigenen Rinderverwaltung **CattleOrg**.
Die App greift ausschließlich über die bestehende Token-API des Server-Projekts
([Obi811/CattleOrg](https://github.com/Obi811/CattleOrg)) zu – sie enthält kein eigenes Backend.

## Funktionen
- Anmeldung mit bestehendem Konto (Token-Speicherung in der iOS-Keychain)
- Betriebsauswahl (Mehrbetriebsfähigkeit)
- Übersicht fälliger Aufgaben (Wartezeiten, Weiterbehandlungen, Hemmstoffproben, TU-Kontrollen)
- Geplante Behandlungen mit Fälligkeitsdatum: in den Aufgaben als eigene Sektion mit **Erledigt** (Datumsauswahl), **Bearbeiten** und **Verwerfen**; überfällige Einträge hervorgehoben. Erledigen übernimmt den Eintrag als Behandlung der Kuh
- Dashboard-Kacheln **Milchkühe**, **Trockensteher** und **Geplant fällig** (Tipp führt in die gefilterte Tierliste)
- Tierliste mit Ohrmarken-Suche, Status-/Wartezeit-Anzeige und Filtern **Nur Milchkühe** / **Nur Trockensteher**
- Gruppenaktionen pro Box: Mehrfachauswahl → Umzug / Inaktivieren / Behandeln / Behandlung planen (mit Bestätigung)
- Totgeburten-Erfassung pro Kuh (ohne Ohrmarke), angezeigt bei den Kalbungen im Tierdetail
- Tierdetail mit Behandlungen, geplanten Behandlungen, Besamungen, Trächtigkeitskontrollen, Totgeburten, Hemmstoffproben
- Schnell-Erfassung und „Abgang melden“
- Rollen-/Rechte-Berücksichtigung (Lesen/Schreiben; Demo-Betriebe schreibgeschützt)
- Push-Benachrichtigungen (APNs, Deep-Link zum Tier, Sammel-Mitteilungen); Badge wird beim Öffnen der App zurückgesetzt
- Datumsanzeige im deutschen Format TT.MM.JJJJ

> **Hinweis:** Die mit V0.10 ergänzten Funktionen (geplante Behandlungen, Totgeburten,
> Gruppenaktionen, Milchkuh-/Trockensteher-Kennzahlen und -Filter) nutzen neue API-Endpunkte.
> Solange diese serverseitig noch nicht live sind, zeigt die App in den betroffenen Bereichen
> einen freundlichen **„bald verfügbar“**-Zustand und funktioniert ohne weitere App-Änderung,
> sobald die API bereitsteht.

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
