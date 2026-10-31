import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.cattleorg.app", category: "GroupActions")

// MARK: - ViewModel
@Observable
@MainActor
final class GroupActionsViewModel {
    var stalls: [Stall] = []
    var selectedStall: String = ""
    var animals: [GroupAnimal] = []
    var selectedIDs: Set<String> = []
    var medications: [Medication] = []

    var isLoadingAnimals = false
    var notAvailable = false
    var errorMessage: String?
    var resultMessage: String?
    var isSubmitting = false

    // Aktion + Felder
    var action = "move"               // move | inactivate | treat | plan
    var targetStall = ""
    var date = Date()
    var grund = ""
    var medicationName = ""
    var treatmentType = "Injektion"
    var dosage = ""
    var notes = ""
    var plannedDate = Date()

    var canSubmit: Bool {
        guard !selectedIDs.isEmpty, !isSubmitting else { return false }
        switch action {
        case "move": return !targetStall.isEmpty
        case "inactivate": return true
        case "treat", "plan": return !medicationName.isEmpty
        default: return false
        }
    }

    func loadStalls() async {
        guard stalls.isEmpty else { return }
        do { stalls = try await CattleAPI.fetchStalls() } catch { }
    }

    func loadMedications() async {
        guard medications.isEmpty else { return }
        do { medications = try await CattleAPI.fetchMedications() } catch { }
    }

    func loadAnimals() async {
        guard !selectedStall.isEmpty else { animals = []; selectedIDs = []; return }
        isLoadingAnimals = true
        errorMessage = nil
        notAvailable = false
        selectedIDs = []
        defer { isLoadingAnimals = false }
        do {
            animals = try await CattleAPI.fetchGroupAnimals(stall: selectedStall)
        } catch let err as CattleAPIError {
            if case .notFound = err {
                notAvailable = true
            } else {
                errorMessage = err.localizedDescription
            }
            animals = []
        } catch {
            errorMessage = "Tiere konnten nicht geladen werden."
            animals = []
        }
    }

    func toggle(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    func selectAll() {
        selectedIDs = Set(animals.map { $0.id.value })
    }

    func clearSelection() {
        selectedIDs = []
    }

    /// Führt die Gruppenaktion aus. Gibt true bei Erfolg zurück.
    func perform() async -> Bool {
        isSubmitting = true
        errorMessage = nil
        resultMessage = nil
        defer { isSubmitting = false }
        let ids = selectedIDs.compactMap { Int($0) }
        var body: [String: Any] = ["action": action, "cattle_ids": ids]
        switch action {
        case "move":
            body["target_stall"] = targetStall
            body["date"] = DateHelper.apiString(from: date)
        case "inactivate":
            body["date"] = DateHelper.apiString(from: date)
            if !grund.isEmpty { body["grund"] = grund }
        case "treat":
            body["medication"] = medicationName
            body["type"] = treatmentType
            if !dosage.isEmpty { body["dosage"] = dosage }
            if !notes.isEmpty { body["notes"] = notes }
            body["date"] = DateHelper.apiString(from: date)
        case "plan":
            body["medication"] = medicationName
            body["type"] = treatmentType
            if !dosage.isEmpty { body["dosage"] = dosage }
            if !notes.isEmpty { body["notes"] = notes }
            body["planned_date"] = DateHelper.apiString(from: plannedDate)
        default:
            break
        }
        do {
            let result = try await CattleAPI.performGroupAction(body)
            let n = result.processed ?? ids.count
            resultMessage = "\(n) Tier(e) erfolgreich verarbeitet."
            return true
        } catch let err as CattleAPIError {
            if case .notFound = err {
                errorMessage = "Gruppenaktionen sind noch nicht verf\u{00FC}gbar. Bitte den Server-Endpunkt erg\u{00E4}nzen."
            } else {
                errorMessage = err.localizedDescription
            }
            return false
        } catch {
            errorMessage = "Aktion fehlgeschlagen."
            return false
        }
    }
}

// MARK: - View
struct GroupActionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionManager.self) private var session
    @State private var vm = GroupActionsViewModel()
    @State private var showConfirm = false
    @FocusState private var focusField: Int?

    private let actions: [(key: String, label: String)] = [
        ("move", "Umziehen"),
        ("inactivate", "Inaktivieren"),
        ("treat", "Behandeln"),
        ("plan", "Planen")
    ]

    var body: some View {
        Form {
            stallSection
            if !vm.selectedStall.isEmpty {
                animalsSection
                if !vm.animals.isEmpty {
                    actionSection
                    actionFieldsSection
                    submitSection
                }
            }
            if let res = vm.resultMessage {
                Section { Text(res).foregroundStyle(.green).font(.subheadline) }
            }
            if let err = vm.errorMessage {
                Section { Text(err).foregroundStyle(AppTheme.warning).font(.subheadline) }
            }
        }
        .navigationTitle("Gruppenaktion")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fertig") { dismiss() }
            }
        }
        .task {
            await vm.loadStalls()
            await vm.loadMedications()
        }
        .onChange(of: vm.selectedStall) { _, _ in
            Task { await vm.loadAnimals() }
        }
        .confirmationDialog(confirmText, isPresented: $showConfirm, titleVisibility: .visible) {
            Button(confirmButtonLabel, role: confirmRole) {
                Task {
                    let ok = await vm.perform()
                    if ok { await vm.loadAnimals() }
                }
            }
            Button("Abbrechen", role: .cancel) { }
        }
    }

    // MARK: Sections
    private var stallSection: some View {
        Section("Box / Stall") {
            if vm.stalls.isEmpty {
                Text("St\u{00E4}lle werden geladen\u{2026}").foregroundStyle(.secondary)
            } else {
                Picker("Stall", selection: $vm.selectedStall) {
                    Text("Ausw\u{00E4}hlen").tag("")
                    ForEach(vm.stalls) { stall in
                        Text(stall.name ?? "\u{2013}").tag(stall.name ?? "")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var animalsSection: some View {
        Section {
            if vm.isLoadingAnimals {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if vm.notAvailable {
                Text("Gruppenaktionen sind bald verf\u{00FC}gbar.")
                    .foregroundStyle(.secondary).font(.subheadline)
            } else if vm.animals.isEmpty {
                Text("Keine Tiere in dieser Box.")
                    .foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(vm.animals) { animal in
                    Button {
                        vm.toggle(animal.id.value)
                    } label: {
                        HStack {
                            Image(systemName: vm.selectedIDs.contains(animal.id.value) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(vm.selectedIDs.contains(animal.id.value) ? AppTheme.primary : .secondary)
                            Text(animal.displayTag)
                                .font(.body.monospaced())
                                .foregroundStyle(.primary)
                            Spacer()
                            if let r = animal.rasse, !r.isEmpty {
                                Text(r).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Text("Tiere (\(vm.selectedIDs.count) ausgew\u{00E4}hlt)")
                Spacer()
                if !vm.animals.isEmpty {
                    if vm.selectedIDs.count == vm.animals.count {
                        Button("Keine") { vm.clearSelection() }.font(.caption)
                    } else {
                        Button("Alle") { vm.selectAll() }.font(.caption)
                    }
                }
            }
        }
    }

    private var actionSection: some View {
        Section("Aktion") {
            Picker("Aktion", selection: $vm.action) {
                ForEach(actions, id: \.key) { a in
                    Text(a.label).tag(a.key)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var actionFieldsSection: some View {
        switch vm.action {
        case "move":
            Section("Zielbox") {
                Picker("Neuer Stall", selection: $vm.targetStall) {
                    Text("Ausw\u{00E4}hlen").tag("")
                    ForEach(vm.stalls) { stall in
                        Text(stall.name ?? "\u{2013}").tag(stall.name ?? "")
                    }
                }
                DatePicker("Datum", selection: $vm.date, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "de_DE"))
            }
        case "inactivate":
            Section("Inaktivieren") {
                DatePicker("Datum", selection: $vm.date, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "de_DE"))
                TextField("Grund (optional)", text: $vm.grund)
                    .focused($focusField, equals: 0)
                    .contentShape(Rectangle())
                    .onTapGesture { focusField = 0 }
            }
        case "treat", "plan":
            Section(vm.action == "treat" ? "Behandlung" : "Geplante Behandlung") {
                Picker("Medikament", selection: $vm.medicationName) {
                    Text("Ausw\u{00E4}hlen").tag("")
                    ForEach(vm.medications) { med in
                        Text(med.name ?? "Unbekannt").tag(med.name ?? "")
                    }
                }
                Picker("Art", selection: $vm.treatmentType) {
                    ForEach(TreatmentTypeCatalog.all, id: \.self) { t in
                        Text(t).tag(t)
                    }
                }
                TextField("Dosis (optional)", text: $vm.dosage)
                    .focused($focusField, equals: 1)
                    .contentShape(Rectangle())
                    .onTapGesture { focusField = 1 }
                TextField("Bemerkungen (optional)", text: $vm.notes)
                    .focused($focusField, equals: 2)
                    .contentShape(Rectangle())
                    .onTapGesture { focusField = 2 }
                if vm.action == "treat" {
                    DatePicker("Datum", selection: $vm.date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "de_DE"))
                } else {
                    DatePicker("Geplantes Datum", selection: $vm.plannedDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "de_DE"))
                }
            }
        default:
            EmptyView()
        }
    }

    private var submitSection: some View {
        Section {
            Button {
                showConfirm = true
            } label: {
                HStack {
                    Spacer()
                    if vm.isSubmitting { ProgressView() } else { Text("Ausf\u{00FC}hren").bold() }
                    Spacer()
                }
            }
            .disabled(!vm.canSubmit)
        }
    }

    // MARK: Confirmation texts
    private var confirmText: String {
        let n = vm.selectedIDs.count
        switch vm.action {
        case "move": return "\(n) Tier(e) nach \u{201E}\(vm.targetStall)\u{201C} umziehen?"
        case "inactivate": return "\(n) Tier(e) inaktivieren?"
        case "treat": return "\(n) Tier(e) behandeln?"
        case "plan": return "Behandlung f\u{00FC}r \(n) Tier(e) planen?"
        default: return "Aktion ausf\u{00FC}hren?"
        }
    }

    private var confirmButtonLabel: String {
        switch vm.action {
        case "move": return "Umziehen"
        case "inactivate": return "Inaktivieren"
        case "treat": return "Behandeln"
        case "plan": return "Planen"
        default: return "Ausf\u{00FC}hren"
        }
    }

    private var confirmRole: ButtonRole? {
        vm.action == "inactivate" ? .destructive : nil
    }
}
