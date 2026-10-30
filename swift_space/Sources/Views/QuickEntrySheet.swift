import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.cattleorg.app", category: "QuickEntry")

enum QuickEntryType: String, CaseIterable, Identifiable {
    case treatment = "Behandlung"
    case insemination = "Besamung"
    case inhibitorTest = "Hemmstofftest"
    case pregnancyCheck = "TU-Kontrolle"
    case departure = "Abgang"
    case plannedTreatment = "Geplante Behandlung"
    case stillbirth = "Totgeburt"

    var id: String { rawValue }

    /// Typen, die im Schnellerfassungs-Umschalter (ohne vorgewähltes Tier) angeboten werden.
    static var quickCases: [QuickEntryType] { [.treatment, .insemination, .inhibitorTest, .pregnancyCheck, .departure] }
}

struct QuickEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionManager.self) private var session
    @State var initialType: QuickEntryType
    var preselectedCattle: Cattle?
    var editingPlanned: PlannedTreatment?

    var body: some View {
        VStack(spacing: 0) {
            if preselectedCattle == nil && editingPlanned == nil {
                Picker("Aktion", selection: $initialType) {
                    ForEach(QuickEntryType.quickCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
            }

            formContent
        }
        .navigationTitle(initialType.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var formContent: some View {
        switch initialType {
        case .treatment:
            TreatmentFormView(preselectedCattle: preselectedCattle, onSave: { dismiss() })
        case .insemination:
            InseminationFormView(preselectedCattle: preselectedCattle, onSave: { dismiss() })
        case .inhibitorTest:
            InhibitorTestFormView(preselectedCattle: preselectedCattle, onSave: { dismiss() })
        case .pregnancyCheck:
            PregnancyCheckFormView(preselectedCattle: preselectedCattle, onSave: { dismiss() })
        case .departure:
            DepartureFormView(preselectedCattle: preselectedCattle, onSave: { dismiss() })
        case .plannedTreatment:
            PlannedTreatmentFormView(preselectedCattle: preselectedCattle, editing: editingPlanned, onSave: { dismiss() })
        case .stillbirth:
            StillbirthFormView(preselectedCattle: preselectedCattle, onSave: { dismiss() })
        }
    }
}

// MARK: - Treatment Form
struct TreatmentFormView: View {
    var preselectedCattle: Cattle?
    var onSave: () -> Void
    @State private var selectedCattle: Cattle?
    @State private var showCattlePicker = false
    @State private var medications: [Medication] = []
    @State private var selectedMedication: Medication?
    @State private var dosage = ""
    @State private var treatmentDate = Date()
    @State private var treatmentType = ""
    @State private var notes = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusField: Int?

    var body: some View {
        Form {
            cattleSection
            medicationSection
            detailsSection
            errorSection
            saveSection
        }
        .task {
            selectedCattle = preselectedCattle
            await loadMedications()
        }
        .sheet(isPresented: $showCattlePicker) {
            NavigationStack {
                CattlePickerSheet(selectedCattle: $selectedCattle)
            }
        }
    }

    private var cattleSection: some View {
        Section("Tier") {
            Button {
                if preselectedCattle == nil { showCattlePicker = true }
            } label: {
                HStack {
                    Text(selectedCattle?.displayTag ?? "Tier ausw\u{00E4}hlen")
                        .foregroundStyle(selectedCattle == nil ? .secondary : .primary)
                    Spacer()
                    if preselectedCattle == nil {
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(preselectedCattle != nil)
        }
    }

    private var medicationSection: some View {
        Section("Medikament") {
            if medications.isEmpty {
                Text("Medikamente werden geladen\u{2026}")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Medikament", selection: $selectedMedication) {
                    Text("Ausw\u{00E4}hlen").tag(nil as Medication?)
                    ForEach(medications) { med in
                        Text(med.name ?? "Unbekannt").tag(med as Medication?)
                    }
                }
            }
            TextField("Dosis", text: $dosage)
                .keyboardType(.decimalPad)
                .focused($focusField, equals: 0)
                .contentShape(Rectangle())
                .onTapGesture { focusField = 0 }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            DatePicker("Datum", selection: $treatmentDate, displayedComponents: .date)
                .environment(\.locale, Locale(identifier: "de_DE"))
            TextField("Art (z.B. oral, i.m.)", text: $treatmentType)
                .focused($focusField, equals: 1)
                .contentShape(Rectangle())
                .onTapGesture { focusField = 1 }
            TextField("Bemerkungen (optional)", text: $notes)
                .focused($focusField, equals: 2)
                .contentShape(Rectangle())
                .onTapGesture { focusField = 2 }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let err = errorMessage {
            Section {
                Text(err).foregroundStyle(AppTheme.warning).font(.subheadline)
            }
        }
    }

    private var saveSection: some View {
        Section {
            Button {
                Task { await save() }
            } label: {
                HStack {
                    Spacer()
                    if isLoading { ProgressView() } else { Text("Speichern").bold() }
                    Spacer()
                }
            }
            .disabled(isLoading || selectedCattle == nil)
        }
    }

    private func loadMedications() async {
        do {
            medications = try await CattleAPI.fetchMedications()
        } catch {
            logger.warning("Failed to load medications: \(error.localizedDescription)")
        }
    }

    private func save() async {
        guard let cattle = selectedCattle else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        var body: [String: Any] = [
            "cattle_id": cattle.id.value,
            "treatment_date": DateHelper.apiString(from: treatmentDate)
        ]
        if let med = selectedMedication { body["medication"] = med.name ?? "" }
        if !dosage.isEmpty { body["dosage"] = dosage }
        if !treatmentType.isEmpty { body["type"] = treatmentType }
        if !notes.isEmpty { body["notes"] = notes }
        do {
            let _ = try await CattleAPI.createTreatment(body)
            onSave()
        } catch let err as CattleAPIError {
            errorMessage = err.localizedDescription
        } catch {
            errorMessage = "Fehler beim Speichern."
        }
    }
}

// MARK: - Insemination Form
struct InseminationFormView: View {
    var preselectedCattle: Cattle?
    var onSave: () -> Void
    @State private var selectedCattle: Cattle?
    @State private var showCattlePicker = false
    @State private var bullName = ""
    @State private var inseminationDate = Date()
    @State private var inseminationType = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusField: Int?

    var body: some View {
        Form {
            Section("Tier") {
                Button {
                    if preselectedCattle == nil { showCattlePicker = true }
                } label: {
                    HStack {
                        Text(selectedCattle?.displayTag ?? "Tier ausw\u{00E4}hlen")
                            .foregroundStyle(selectedCattle == nil ? .secondary : .primary)
                        Spacer()
                        if preselectedCattle == nil {
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(preselectedCattle != nil)
            }
            Section("Details") {
                TextField("Bullenname/-code", text: $bullName)
                    .focused($focusField, equals: 0)
                    .contentShape(Rectangle())
                    .onTapGesture { focusField = 0 }
                DatePicker("Datum", selection: $inseminationDate, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "de_DE"))
                TextField("Art (optional)", text: $inseminationType)
                    .focused($focusField, equals: 1)
                    .contentShape(Rectangle())
                    .onTapGesture { focusField = 1 }
            }
            if let err = errorMessage {
                Section { Text(err).foregroundStyle(AppTheme.warning).font(.subheadline) }
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading { ProgressView() } else { Text("Speichern").bold() }
                        Spacer()
                    }
                }
                .disabled(isLoading || selectedCattle == nil || bullName.isEmpty)
            }
        }
        .task { selectedCattle = preselectedCattle }
        .sheet(isPresented: $showCattlePicker) {
            NavigationStack { CattlePickerSheet(selectedCattle: $selectedCattle) }
        }
    }

    private func save() async {
        guard let cattle = selectedCattle else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        var body: [String: Any] = [
            "cattle_id": cattle.id.value,
            "date": DateHelper.apiString(from: inseminationDate),
            "bull_name": bullName
        ]
        if !inseminationType.isEmpty { body["type"] = inseminationType }
        do {
            let _ = try await CattleAPI.createInsemination(body)
            onSave()
        } catch let err as CattleAPIError {
            errorMessage = err.localizedDescription
        } catch {
            errorMessage = "Fehler beim Speichern."
        }
    }
}

// MARK: - Pregnancy Check Form
struct PregnancyCheckFormView: View {
    var preselectedCattle: Cattle?
    var onSave: () -> Void
    @State private var selectedCattle: Cattle?
    @State private var showCattlePicker = false
    @State private var checkDate = Date()
    @State private var result = "Positiv"
    @State private var comment = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusField: Int?

    var body: some View {
        Form {
            Section("Tier") {
                Button {
                    if preselectedCattle == nil { showCattlePicker = true }
                } label: {
                    HStack {
                        Text(selectedCattle?.displayTag ?? "Tier ausw\u{00E4}hlen")
                            .foregroundStyle(selectedCattle == nil ? .secondary : .primary)
                        Spacer()
                        if preselectedCattle == nil {
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(preselectedCattle != nil)
            }
            Section("Ergebnis") {
                Picker("Ergebnis", selection: $result) {
                    Text("Positiv").tag("Positiv")
                    Text("Negativ").tag("Negativ")
                    Text("Unklar").tag("Unklar")
                }
                .pickerStyle(.segmented)
                DatePicker("Datum", selection: $checkDate, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "de_DE"))
                TextField("Kommentar (optional)", text: $comment)
                    .focused($focusField, equals: 0)
                    .contentShape(Rectangle())
                    .onTapGesture { focusField = 0 }
            }
            if let err = errorMessage {
                Section { Text(err).foregroundStyle(AppTheme.warning).font(.subheadline) }
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading { ProgressView() } else { Text("Speichern").bold() }
                        Spacer()
                    }
                }
                .disabled(isLoading || selectedCattle == nil)
            }
        }
        .task { selectedCattle = preselectedCattle }
        .sheet(isPresented: $showCattlePicker) {
            NavigationStack { CattlePickerSheet(selectedCattle: $selectedCattle) }
        }
    }

    private func save() async {
        guard let cattle = selectedCattle else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        var body: [String: Any] = [
            "cattle_id": cattle.id.value,
            "check_date": DateHelper.apiString(from: checkDate),
            "result": result
        ]
        if !comment.isEmpty { body["comment"] = comment }
        do {
            let _ = try await CattleAPI.createPregnancyCheck(body)
            onSave()
        } catch let err as CattleAPIError {
            errorMessage = err.localizedDescription
        } catch {
            errorMessage = "Fehler beim Speichern."
        }
    }
}

// MARK: - Inhibitor Test Form
// TODO: Server-Endpunkt /api/v1/inhibitor-tests/ POST noch nicht implementiert
struct InhibitorTestFormView: View {
    var preselectedCattle: Cattle?
    var onSave: () -> Void
    @State private var selectedCattle: Cattle?
    @State private var showCattlePicker = false
    @State private var probeDate = Date()
    @State private var nummer = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusField: Int?

    var body: some View {
        Form {
            Section("Tier") {
                Button {
                    if preselectedCattle == nil { showCattlePicker = true }
                } label: {
                    HStack {
                        Text(selectedCattle?.displayTag ?? "Tier ausw\u{00E4}hlen")
                            .foregroundStyle(selectedCattle == nil ? .secondary : .primary)
                        Spacer()
                        if preselectedCattle == nil {
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(preselectedCattle != nil)
            }
            Section("Probe") {
                TextField("Proben-Nummer", text: $nummer)
                    .focused($focusField, equals: 0)
                    .contentShape(Rectangle())
                    .onTapGesture { focusField = 0 }
                DatePicker("Datum", selection: $probeDate, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "de_DE"))
            }
            if let err = errorMessage {
                Section { Text(err).foregroundStyle(AppTheme.warning).font(.subheadline) }
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading { ProgressView() } else { Text("Speichern").bold() }
                        Spacer()
                    }
                }
                .disabled(isLoading || selectedCattle == nil || nummer.isEmpty)
            }
        }
        .task { selectedCattle = preselectedCattle }
        .sheet(isPresented: $showCattlePicker) {
            NavigationStack { CattlePickerSheet(selectedCattle: $selectedCattle) }
        }
    }

    private func save() async {
        guard let cattle = selectedCattle else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let body: [String: Any] = [
            "cattle_id": cattle.id.value,
            "nummer": nummer,
            "probe_date": DateHelper.apiString(from: probeDate)
        ]
        do {
            let _ = try await CattleAPI.createInhibitorTest(body)
            onSave()
        } catch let err as CattleAPIError {
            if case .notFound = err {
                errorMessage = "Diese Funktion ist noch nicht verf\u{00FC}gbar. Bitte den Server-Endpunkt erg\u{00E4}nzen."
            } else {
                errorMessage = err.localizedDescription
            }
        } catch {
            errorMessage = "Fehler beim Speichern."
        }
    }
}

// MARK: - Departure Form
// TODO: Server-Endpunkt /api/v1/cattle/abgang/ noch nicht implementiert
struct DepartureFormView: View {
    var preselectedCattle: Cattle?
    var onSave: () -> Void
    @State private var selectedCattle: Cattle?
    @State private var showCattlePicker = false
    @State private var departureDate = Date()
    @State private var art = "Verkauf"
    @State private var grund = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusField: Int?

    private let artOptions = ["Verkauf", "Schlachtung", "Tod", "Sonstiges"]

    var body: some View {
        Form {
            Section("Tier") {
                Button {
                    if preselectedCattle == nil { showCattlePicker = true }
                } label: {
                    HStack {
                        Text(selectedCattle?.displayTag ?? "Tier ausw\u{00E4}hlen")
                            .foregroundStyle(selectedCattle == nil ? .secondary : .primary)
                        Spacer()
                        if preselectedCattle == nil {
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(preselectedCattle != nil)
            }
            Section("Abgangsdetails") {
                Picker("Art", selection: $art) {
                    ForEach(artOptions, id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }
                DatePicker("Datum", selection: $departureDate, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "de_DE"))
                TextField("Grund (optional)", text: $grund)
                    .focused($focusField, equals: 0)
                    .contentShape(Rectangle())
                    .onTapGesture { focusField = 0 }
            }
            if let err = errorMessage {
                Section { Text(err).foregroundStyle(AppTheme.warning).font(.subheadline) }
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading { ProgressView() } else {
                            Text("Abgang melden")
                                .bold()
                                .foregroundStyle(AppTheme.warning)
                        }
                        Spacer()
                    }
                }
                .disabled(isLoading || selectedCattle == nil)
            }
        }
        .task { selectedCattle = preselectedCattle }
        .sheet(isPresented: $showCattlePicker) {
            NavigationStack { CattlePickerSheet(selectedCattle: $selectedCattle) }
        }
    }

    private func save() async {
        guard let cattle = selectedCattle else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        var body: [String: Any] = [
            "cattle_id": cattle.id.value,
            "art": art,
            "datum": DateHelper.apiString(from: departureDate)
        ]
        if !grund.isEmpty { body["grund"] = grund }
        do {
            try await CattleAPI.reportDeparture(body)
            onSave()
        } catch let err as CattleAPIError {
            if case .notFound = err {
                errorMessage = "Diese Funktion ist noch nicht verf\u{00FC}gbar. Bitte den Server-Endpunkt erg\u{00E4}nzen."
            } else {
                errorMessage = err.localizedDescription
            }
        } catch {
            errorMessage = "Fehler beim Speichern."
        }
    }
}

// MARK: - Planned Treatment Form (geplante Behandlung)
// Server-Endpunkt /api/v1/planned-treatments/ (ab V0.10; vorher 404 -> "bald verfügbar")
struct PlannedTreatmentFormView: View {
    var preselectedCattle: Cattle?
    var editing: PlannedTreatment?
    var onSave: () -> Void
    @State private var selectedCattle: Cattle?
    @State private var showCattlePicker = false
    @State private var medications: [Medication] = []
    @State private var selectedMedicationName = ""
    @State private var dosage = ""
    @State private var plannedDate = Date()
    @State private var treatmentType = "Injektion"
    @State private var notes = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusField: Int?

    private var isEditing: Bool { editing != nil }

    var body: some View {
        Form {
            Section("Tier") {
                if isEditing {
                    Text(editing?.displayTag ?? "\u{2013}")
                        .font(.body.monospaced())
                } else {
                    Button {
                        if preselectedCattle == nil { showCattlePicker = true }
                    } label: {
                        HStack {
                            Text(selectedCattle?.displayTag ?? "Tier ausw\u{00E4}hlen")
                                .foregroundStyle(selectedCattle == nil ? .secondary : .primary)
                            Spacer()
                            if preselectedCattle == nil {
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(preselectedCattle != nil)
                }
            }
            Section("Behandlung") {
                if medications.isEmpty {
                    Text("Medikamente werden geladen\u{2026}").foregroundStyle(.secondary)
                } else {
                    Picker("Medikament", selection: $selectedMedicationName) {
                        Text("Ausw\u{00E4}hlen").tag("")
                        ForEach(medications) { med in
                            Text(med.name ?? "Unbekannt").tag(med.name ?? "")
                        }
                        if !selectedMedicationName.isEmpty && !medications.contains(where: { $0.name == selectedMedicationName }) {
                            Text(selectedMedicationName).tag(selectedMedicationName)
                        }
                    }
                }
                Picker("Art", selection: $treatmentType) {
                    ForEach(TreatmentTypeCatalog.all, id: \.self) { t in
                        Text(t).tag(t)
                    }
                }
                TextField("Dosis (optional)", text: $dosage)
                    .focused($focusField, equals: 0)
                    .contentShape(Rectangle())
                    .onTapGesture { focusField = 0 }
            }
            Section("Termin") {
                DatePicker("Geplantes Datum", selection: $plannedDate, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "de_DE"))
                TextField("Bemerkungen (optional)", text: $notes)
                    .focused($focusField, equals: 1)
                    .contentShape(Rectangle())
                    .onTapGesture { focusField = 1 }
            }
            if let err = errorMessage {
                Section { Text(err).foregroundStyle(AppTheme.warning).font(.subheadline) }
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading { ProgressView() } else { Text("Speichern").bold() }
                        Spacer()
                    }
                }
                .disabled(isLoading || (!isEditing && selectedCattle == nil) || selectedMedicationName.isEmpty)
            }
        }
        .task {
            if let e = editing {
                selectedMedicationName = e.medication ?? ""
                dosage = e.dosage ?? ""
                treatmentType = (e.type?.isEmpty == false) ? (e.type ?? "Injektion") : "Injektion"
                notes = e.notes ?? ""
                if let d = DateHelper.parse(e.planned_date) { plannedDate = d }
            } else {
                selectedCattle = preselectedCattle
            }
            await loadMedications()
        }
        .sheet(isPresented: $showCattlePicker) {
            NavigationStack { CattlePickerSheet(selectedCattle: $selectedCattle) }
        }
    }

    private func loadMedications() async {
        do { medications = try await CattleAPI.fetchMedications() } catch { }
    }

    private func save() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        var body: [String: Any] = [
            "planned_date": DateHelper.apiString(from: plannedDate),
            "medication": selectedMedicationName,
            "type": treatmentType
        ]
        if !dosage.isEmpty { body["dosage"] = dosage }
        if !notes.isEmpty { body["notes"] = notes }
        do {
            if let e = editing {
                try await CattleAPI.updatePlannedTreatment(id: e.id.value, body: body)
            } else {
                guard let cattle = selectedCattle else { return }
                body["cattle_id"] = cattle.id.value
                let _ = try await CattleAPI.createPlannedTreatment(body)
            }
            onSave()
        } catch let err as CattleAPIError {
            if case .notFound = err {
                errorMessage = "Diese Funktion ist noch nicht verf\u{00FC}gbar. Bitte den Server-Endpunkt erg\u{00E4}nzen."
            } else {
                errorMessage = err.localizedDescription
            }
        } catch {
            errorMessage = "Fehler beim Speichern."
        }
    }
}

// MARK: - Stillbirth Form (Totgeburt)
// Server-Endpunkt /api/v1/stillbirths/ (ab V0.10; vorher 404 -> "bald verfügbar")
struct StillbirthFormView: View {
    var preselectedCattle: Cattle?
    var onSave: () -> Void
    @State private var selectedCattle: Cattle?
    @State private var showCattlePicker = false
    @State private var birthDate = Date()
    @State private var sex = "weiblich"
    @State private var comment = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusField: Int?

    var body: some View {
        Form {
            Section("Mutter-Tier") {
                Button {
                    if preselectedCattle == nil { showCattlePicker = true }
                } label: {
                    HStack {
                        Text(selectedCattle?.displayTag ?? "Tier ausw\u{00E4}hlen")
                            .foregroundStyle(selectedCattle == nil ? .secondary : .primary)
                        Spacer()
                        if preselectedCattle == nil {
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(preselectedCattle != nil)
            }
            Section("Totgeburt") {
                DatePicker("Datum", selection: $birthDate, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "de_DE"))
                Picker("Geschlecht", selection: $sex) {
                    Text("Weiblich").tag("weiblich")
                    Text("M\u{00E4}nnlich").tag("maennlich")
                    Text("Unbekannt").tag("unbekannt")
                }
                .pickerStyle(.segmented)
                TextField("Bemerkung (optional)", text: $comment)
                    .focused($focusField, equals: 0)
                    .contentShape(Rectangle())
                    .onTapGesture { focusField = 0 }
            }
            if let err = errorMessage {
                Section { Text(err).foregroundStyle(AppTheme.warning).font(.subheadline) }
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading { ProgressView() } else { Text("Speichern").bold() }
                        Spacer()
                    }
                }
                .disabled(isLoading || selectedCattle == nil)
            }
        }
        .task { selectedCattle = preselectedCattle }
        .sheet(isPresented: $showCattlePicker) {
            NavigationStack { CattlePickerSheet(selectedCattle: $selectedCattle) }
        }
    }

    private func save() async {
        guard let cattle = selectedCattle else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        var body: [String: Any] = [
            "cattle_id": cattle.id.value,
            "birth_date": DateHelper.apiString(from: birthDate),
            "sex": sex
        ]
        if !comment.isEmpty { body["comment"] = comment }
        do {
            let _ = try await CattleAPI.createStillbirth(body)
            onSave()
        } catch let err as CattleAPIError {
            if case .notFound = err {
                errorMessage = "Diese Funktion ist noch nicht verf\u{00FC}gbar. Bitte den Server-Endpunkt erg\u{00E4}nzen."
            } else {
                errorMessage = err.localizedDescription
            }
        } catch {
            errorMessage = "Fehler beim Speichern."
        }
    }
}

// MARK: - Cattle Picker Sheet
struct CattlePickerSheet: View {
    @Binding var selectedCattle: Cattle?
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var cattle: [Cattle] = []
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        List(cattle) { animal in
            Button {
                selectedCattle = animal
                dismiss()
            } label: {
                HStack {
                    Text(animal.displayTag)
                        .font(.body.bold().monospaced())
                    if let name = animal.name, !name.isEmpty {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .overlay {
            if isLoading && cattle.isEmpty {
                ProgressView()
            }
            if !isLoading && cattle.isEmpty && !searchText.isEmpty {
                Text("Keine Tiere gefunden")
                    .foregroundStyle(.secondary)
            }
        }
        .searchable(text: $searchText, prompt: "Ohrmarke suchen\u{2026}")
        .onChange(of: searchText) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await loadCattle()
            }
        }
        .navigationTitle("Tier ausw\u{00E4}hlen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
        }
        .task { await loadCattle() }
    }

    private func loadCattle() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await CattleAPI.fetchCattle(page: 1, perPage: 100, search: searchText.isEmpty ? nil : searchText)
            cattle = result.cattle
        } catch {
            cattle = []
        }
    }
}

// MARK: - Medication Picker Conformance
extension Medication: Equatable {
    static func == (lhs: Medication, rhs: Medication) -> Bool {
        lhs.id == rhs.id
    }
}

extension Medication: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
