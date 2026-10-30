# Changelog – CattleOrg iOS

Alle nennenswerten Änderungen an der nativen iOS-App werden hier dokumentiert.
Die App greift ausschließlich über die Token-API des Server-Projekts
[Obi811/CattleOrg](https://github.com/Obi811/CattleOrg) zu.

## V0.10 – Geplante Behandlungen, Gruppenaktionen, Milchkühe/Trockensteher

> Hinweis: Die neuen Funktionen nutzen API-Endpunkte, die serverseitig noch nicht
> überall live sind. Bis dahin zeigt die App in den betroffenen Bereichen einen
> freundlichen „bald verfügbar"-Zustand (statt eines Fehlers) und funktioniert ohne
> weitere App-Änderung, sobald die API bereitsteht.

### Neu
- **Geplante Behandlungen** mit festem Fälligkeitsdatum: eigene Sektion in den
  Aufgaben mit Aktionen **Erledigt** (Datumsauswahl, Standard heute), **Bearbeiten**
  und **Verwerfen**; überfällige Einträge hervorgehoben. „Erledigt" übernimmt den
  Eintrag als Behandlung der jeweiligen Kuh. Anlegen/Bearbeiten über das Tierdetail.
- **Dashboard-Kacheln** „Milchkühe", „Trockensteher" und „Geplant fällig"; Tippen
  führt in die passend gefilterte Tierliste.
- **Tierlisten-Filter** „Nur Milchkühe" und „Nur Trockensteher".
- **Gruppenaktionen pro Box**: Box wählen → Mehrfachauswahl → Umzug / Inaktivieren /
  Behandeln / Behandlung planen, jeweils mit Bestätigungsdialog.
- **Totgeburten** pro Kuh erfassen und löschen (ohne Ohrmarke); Anzeige bei den
  Kalbungen im Tierdetail.

### Behoben
- **Push-Badge** bleibt nach dem Öffnen der App nicht mehr stehen: Die rote Badge
  wird beim App-Start und bei Rückkehr in den Vordergrund auf 0 zurückgesetzt.

### Technisch
- Neue API-Methoden im `CattleAPI`-Client (geplante Behandlungen CRUD + Complete,
  Totgeburten, Gruppenaktionen, Kennzahlen, Filterparameter `milchkuh`/`trockensteher`).
- Neue Modelle (`PlannedTreatment`, `Stillbirth`, `GroupAnimal`, Kennzahlen).
- Neue View `GroupActionsView`; Erweiterungen in Dashboard, Tierliste, Aufgaben,
  Tierdetail und Schnell-Erfassung.
- Datumsanzeige durchgängig im deutschen Format TT.MM.JJJJ (Requests weiterhin ISO).

## Frühere Änderungen
- Push: Sammel-Mitteilungen (summary) als Deep-Link in den Aufgaben-Tab (PR #1).
- Support- und Datenschutzseite für GitHub Pages inkl. „Fehler melden" (PR #2).
- Erstimport der nativen CattleOrg-iOS-App (SwiftUI).
