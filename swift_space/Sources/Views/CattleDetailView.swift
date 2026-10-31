import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.cattleorg.app", category: "CattleDetail")

@Observable
@MainActor
final class CattleDetailViewModel {
    let cattleId: String
    var cattle: Cattle?
    var treatments: [Treatment] = []
    var inseminations: [Insemination] = []
    var pregnancyChecks: [PregnancyCheck] = []
    var inhibitorTests: [InhibitorTest] = []
    var stillbirths: [Stillbirth] = []
    var plannedTreatments: [PlannedTreatment] = []
    var plannedError: String?
    var isLoading = false
    var errorMessage: String?
    var inhibitorError: String?
    var needsReauth = false
    var departureMessage: String?
    var inhibitorUpdatingID: String?
    var inhibitorActionMessage: String?
    var actionMessage: String?

    init(cattleId: String) {
        self.cattleId = cattleId
    }

    func loadAll() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Load cattle detail
        do {
            cattle = try await CattleAPI.fetchCattleDetail(id: cattleId)
            stillbirths = cattle?.stillbirths ?? []
        } catch let err as CattleAPIError {
            if case .tokenExpired = err { needsReauth = true; return }
            if case .unauthorized = err { needsReauth = true; return }
            errorMessage = err.localizedDescription
            return
        } catch {
            errorMessage = "Fehler beim Laden der Tierdaten."
            return
        }

        // Load sub-data in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadTreatments() }
            group.addTask { await self.loadInseminations() }
            group.addTask { await self.loadPregnancyChecks() }
            group.addTask { await self.loadInhibitorTests() }
            group.addTask { await self.loadPlannedTreatments() }
        }
    }

    private func loadPlannedTreatments() async {
        do {
            let r = try await CattleAPI.fetchPlannedTreatments(cattleId: cattleId)
            plannedTreatments = r.items
            plannedError = nil
        } catch let err as CattleAPIError {
            if case .notFound = err {
                plannedError = "Geplante Behandlungen sind bald verf\u{00FC}gbar."
            }
        } catch { }
    }

    func deleteStillbirth(_ s: Stillbirth) async {
        do {
            try await CattleAPI.deleteStillbirth(id: s.id.value)
            await loadAll()
        } catch let err as CattleAPIError {
            if case .notFound = err {
                actionMessage = "Diese Funktion ist noch nicht verf\u{00FC}gbar."
            } else {
                actionMessage = err.localizedDescription
            }
        } catch {
            actionMessage = "L\u{00F6}schen fehlgeschlagen."
        }
    }

    private func loadTreatments() async {
        do { treatments = try await CattleAPI.fetchTreatments(cattleId: cattleId) } catch { }
    }
    private func loadInseminations() async {
        do { inseminations = try await CattleAPI.fetchInseminations(cattleId: cattleId) } catch { }
    }
    private func loadPregnancyChecks() async {
        do { pregnancyChecks = try await CattleAPI.fetchPregnancyChecks(cattleId: cattleId) } catch { }
    }
    private func loadInhibitorTests() async {
        do {
            inhibitorTests = try await CattleAPI.fetchInhibitorTests(cattleId: cattleId)
            inhibitorError = nil
        } catch let err as CattleAPIError {
            if case .notFound = err {
                inhibitorError = "Hemmstofftests sind bald verf\u{00FC}gbar."
            }
        } catch { }
    }

    /// Zeichnet eine versendete Probe als "frei" oder "nicht frei".
    func setInhibitorStatus(id: String, status: String) async {
        inhibitorUpdatingID = id
        inhibitorActionMessage = nil
        defer { inhibitorUpdatingID = nil }
        do {
            try await CattleAPI.updateInhibitorTest(id: id, statusValue: status)
            // Lokal aktualisieren, damit die UI sofort reagiert
            if let idx = inhibitorTests.firstIndex(where: { $0.id.value == id }) {
                inhibitorTests[idx].status = status
            }
            // Danach frisch vom Server laden
            await loadInhibitorTests()
        } catch let err as CattleAPIError {
            if case .tokenExpired = err { needsReauth = true; return }
            if case .unauthorized = err { needsReauth = true; return }
            inhibitorActionMessage = err.localizedDescription
        } catch {
            inhibitorActionMessage = "Status konnte nicht gespeichert werden."
        }
    }

    // TODO: Server-Endpunkt /api/v1/cattle/abgang/ noch nicht implementiert
    func reportDeparture(art: String, datum: String, grund: String) async {
        departureMessage = nil
        do {
            try await CattleAPI.reportDeparture([
                "cattle_id": cattleId,
                "art": art,
                "datum": datum,
                "grund": grund
            ])
            departureMessage = "Abgang erfolgreich gemeldet."
        } catch let err as CattleAPIError {
            if case .notFound = err {
                departureMessage = "Diese Funktion ist noch nicht verf\u{00FC}gbar. Bitte den Server-Endpunkt erg\u{00E4}nzen."
            } else {
                departureMessage = err.localizedDescription
            }
        } catch {
            departureMessage = "Fehler beim Melden des Abgangs."
        }
    }
}

struct CattleDetailView: View {
    let cattleId: String
    @Environment(SessionManager.self) private var session
    @State private var vm: CattleDetailViewModel
    @State private var showDepartureSheet = false
    @State private var showAddTreatment = false
    @State private var showAddInsemination = false
    @State private var showAddPregnancy = false
    @State private var showAddInhibitor = false
    @State private var showAddStillbirth = false
    @State private var showAddPlanned = false

    init(cattleId: String) {
        self.cattleId = cattleId
        _vm = State(initialValue: CattleDetailViewModel(cattleId: cattleId))
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.cattle == nil {
                ProgressView("Lade Tierdaten\u{2026}")
            } else if let err = vm.errorMessage, vm.cattle == nil {
                errorView(err)
            } else if let c = vm.cattle {
                detailContent(c)
            }
        }
        .navigationTitle(vm.cattle?.displayTag ?? "Tier")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.loadAll() }
        .refreshable { await vm.loadAll() }
        .onChange(of: vm.needsReauth) { _, val in
            if val { session.handleCattleAPIError(CattleAPIError.tokenExpired) }
        }
        .sheet(isPresented: $showAddTreatment) {
            NavigationStack {
                QuickEntrySheet(initialType: .treatment, preselectedCattle: vm.cattle)
            }
        }
        .sheet(isPresented: $showAddInsemination) {
            NavigationStack {
                QuickEntrySheet(initialType: .insemination, preselectedCattle: vm.cattle)
            }
        }
        .sheet(isPresented: $showAddPregnancy) {
            NavigationStack {
                QuickEntrySheet(initialType: .pregnancyCheck, preselectedCattle: vm.cattle)
            }
        }
        .sheet(isPresented: $showAddInhibitor) {
            NavigationStack {
                QuickEntrySheet(initialType: .inhibitorTest, preselectedCattle: vm.cattle)
            }
        }
        .sheet(isPresented: $showDepartureSheet) {
            NavigationStack {
                QuickEntrySheet(initialType: .departure, preselectedCattle: vm.cattle)
            }
        }
        .sheet(isPresented: $showAddStillbirth, onDismiss: { Task { await vm.loadAll() } }) {
            NavigationStack {
                QuickEntrySheet(initialType: .stillbirth, preselectedCattle: vm.cattle)
            }
        }
        .sheet(isPresented: $showAddPlanned, onDismiss: { Task { await vm.loadAll() } }) {
            NavigationStack {
                QuickEntrySheet(initialType: .plannedTreatment, preselectedCattle: vm.cattle)
            }
        }
        .alert("Hinweis", isPresented: .constant(vm.actionMessage != nil)) {
            Button("OK") { vm.actionMessage = nil }
        } message: {
            Text(vm.actionMessage ?? "")
        }
        .alert("Abgang", isPresented: .constant(vm.departureMessage != nil)) {
            Button("OK") { vm.departureMessage = nil }
        } message: {
            Text(vm.departureMessage ?? "")
        }
        .alert("Hemmstoffprobe", isPresented: .constant(vm.inhibitorActionMessage != nil)) {
            Button("OK") { vm.inhibitorActionMessage = nil }
        } message: {
            Text(vm.inhibitorActionMessage ?? "")
        }
    }

    private func detailContent(_ c: Cattle) -> some View {
        List {
            heroSection(c)
            wartezeitBanner(c)
            treatmentsSection
            plannedTreatmentsSection
            inseminationsSection
            pregnancySection
            stillbirthsSection
            inhibitorSection
            if session.canWrite {
                departureSection
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Hero Section
    private func heroSection(_ c: Cattle) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(c.displayTag)
                        .font(.title.bold().monospaced())
                    Spacer()
                    if let status = c.status {
                        StatusBadge(text: status, color: status.statusColor)
                    }
                }
                detailRow("Rasse", c.rasse)
                detailRow("Geschlecht", c.geschlecht)
                detailRow("Geburtsdatum", DateHelper.format(c.birth_date))
                detailRow("Mutter", c.mutter)
                detailRow("Stall", c.current_stall)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Stammdaten")
        }
    }

    private func detailRow(_ label: String, _ value: String?) -> some View {
        Group {
            if let v = value, !v.isEmpty {
                HStack {
                    Text(label).foregroundStyle(.secondary)
                    Spacer()
                    Text(v)
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Wartezeit Banner
    @ViewBuilder
    private func wartezeitBanner(_ c: Cattle) -> some View {
        if c.isWartezeitActive {
            Section {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.white)
                    VStack(alignment: .leading) {
                        Text("Wartezeit aktiv")
                            .font(.headline)
                            .foregroundStyle(.white)
                        if let ende = c.wartezeitEnde {
                            Text("bis \(DateHelper.format(ende))")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .background(AppTheme.warning, in: RoundedRectangle(cornerRadius: 12))
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Treatments Section
    private var treatmentsSection: some View {
        Section {
            if vm.treatments.isEmpty {
                Text("Keine Eintr\u{00E4}ge vorhanden")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(vm.treatments) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DateHelper.format(t.treatment_date)).font(.caption).foregroundStyle(.secondary)
                        Text(t.medication ?? "Behandlung").font(.subheadline.bold())
                        if let d = t.dosage { Text("Dosis: \(d)").font(.caption) }
                    }
                    .padding(.vertical, 2)
                }
            }
            if session.canWrite {
                Button { showAddTreatment = true } label: {
                    Label("Behandlung hinzuf\u{00FC}gen", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("Behandlungen")
        }
    }

    // MARK: - Planned Treatments Section
    private var plannedTreatmentsSection: some View {
        Section {
            if let err = vm.plannedError {
                Text(err).foregroundStyle(.secondary).font(.subheadline)
            } else if vm.plannedTreatments.isEmpty {
                Text("Keine Eintr\u{00E4}ge vorhanden")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(vm.plannedTreatments) { pt in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(DateHelper.format(pt.planned_date)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if let st = pt.status {
                                StatusBadge(text: st, color: plannedStatusColor(st))
                            }
                        }
                        Text(pt.medication ?? "Behandlung").font(.subheadline.bold())
                        if let d = pt.dosage, !d.isEmpty { Text("Dosis: \(d)").font(.caption) }
                        if let t = pt.type, !t.isEmpty { Text(t).font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 2)
                }
            }
            if session.canWrite && vm.plannedError == nil {
                Button { showAddPlanned = true } label: {
                    Label("Behandlung planen", systemImage: "calendar.badge.plus")
                }
            }
        } header: {
            Text("Geplante Behandlungen")
        }
    }

    private func plannedStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "geplant": return .teal
        case "erledigt": return .green
        case "verworfen": return .secondary
        default: return .secondary
        }
    }

    // MARK: - Stillbirths Section
    private var stillbirthsSection: some View {
        Section {
            if vm.stillbirths.isEmpty {
                Text("Keine Eintr\u{00E4}ge vorhanden")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(vm.stillbirths) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DateHelper.format(s.birth_date)).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("Totgeburt").font(.subheadline.bold())
                            if let sex = s.sex, !sex.isEmpty {
                                StatusBadge(text: sexLabel(sex), color: .secondary)
                            }
                        }
                        if let c = s.comment, !c.isEmpty { Text(c).font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 2)
                    .swipeActions(edge: .trailing) {
                        if session.canWrite {
                            Button(role: .destructive) {
                                Task { await vm.deleteStillbirth(s) }
                            } label: {
                                Label("L\u{00F6}schen", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            if session.canWrite {
                Button { showAddStillbirth = true } label: {
                    Label("Totgeburt erfassen", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("Totgeburten")
        }
    }

    private func sexLabel(_ sex: String) -> String {
        switch sex.lowercased() {
        case "maennlich", "männlich": return "männlich"
        case "weiblich": return "weiblich"
        default: return "unbekannt"
        }
    }

    // MARK: - Inseminations Section
    private var inseminationsSection: some View {
        Section {
            if vm.inseminations.isEmpty {
                Text("Keine Eintr\u{00E4}ge vorhanden")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(vm.inseminations) { ins in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DateHelper.format(ins.date)).font(.caption).foregroundStyle(.secondary)
                        Text(ins.bull_name ?? "Besamung").font(.subheadline.bold())
                        if let t = ins.type { Text(t).font(.caption) }
                    }
                    .padding(.vertical, 2)
                }
            }
            if session.canWrite {
                Button { showAddInsemination = true } label: {
                    Label("Besamung hinzuf\u{00FC}gen", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("Besamungen")
        }
    }

    // MARK: - Pregnancy Section
    private var pregnancySection: some View {
        Section {
            if vm.pregnancyChecks.isEmpty {
                Text("Keine Eintr\u{00E4}ge vorhanden")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(vm.pregnancyChecks) { pc in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DateHelper.format(pc.check_date)).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("Ergebnis:").font(.subheadline)
                            StatusBadge(
                                text: pc.result ?? "\u{2013}",
                                color: pc.result?.lowercased() == "positiv" ? .green : .orange
                            )
                        }
                        if let c = pc.comment, !c.isEmpty { Text(c).font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 2)
                }
            }
            if session.canWrite {
                Button { showAddPregnancy = true } label: {
                    Label("Pr\u{00FC}fung hinzuf\u{00FC}gen", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("TU-Kontrollen")
        }
    }

    // MARK: - Inhibitor Section
    private var inhibitorSection: some View {
        Section {
            if let err = vm.inhibitorError {
                Text(err)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else if vm.inhibitorTests.isEmpty {
                Text("Keine Eintr\u{00E4}ge vorhanden")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(vm.inhibitorTests) { test in
                    inhibitorRow(test)
                }
            }
            if session.canWrite && vm.inhibitorError == nil {
                Button { showAddInhibitor = true } label: {
                    Label("Hemmstofftest hinzuf\u{00FC}gen", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("Hemmstofftests")
        }
    }

    @ViewBuilder
    private func inhibitorRow(_ test: InhibitorTest) -> some View {
        let status = test.status ?? "\u{2013}"
        let isVersendet = status.lowercased() == "versendet"
        VStack(alignment: .leading, spacing: 6) {
            Text(DateHelper.format(test.probe_date)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Nr. \(test.nummer ?? "\u{2013}")").font(.subheadline.bold())
                StatusBadge(text: status, color: inhibitorStatusColor(status))
                Spacer()
                if vm.inhibitorUpdatingID == test.id.value {
                    ProgressView()
                }
            }
            // Nur versendete Proben lassen sich zeichnen, und nur mit Schreibrecht.
            if isVersendet && session.canWrite {
                HStack(spacing: 10) {
                    Button {
                        Task { await vm.setInhibitorStatus(id: test.id.value, status: "frei") }
                    } label: {
                        Label("Frei", systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.green)
                    Button {
                        Task { await vm.setInhibitorStatus(id: test.id.value, status: "nicht frei") }
                    } label: {
                        Label("Nicht frei", systemImage: "xmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(AppTheme.warning)
                }
                .buttonStyle(.bordered)
                .disabled(vm.inhibitorUpdatingID != nil)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }

    private func inhibitorStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "frei": return .green
        case "nicht frei": return AppTheme.warning
        case "versendet": return .orange
        default: return .secondary
        }
    }

    // MARK: - Departure
    private var departureSection: some View {
        Section {
            Button { showDepartureSheet = true } label: {
                Label("Abgang melden", systemImage: "arrow.right.square")
                    .foregroundStyle(AppTheme.warning)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
            Button("Erneut versuchen") { Task { await vm.loadAll() } }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 200)
        }
        .padding()
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }
}
