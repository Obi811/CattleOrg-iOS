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
    var isLoading = false
    var errorMessage: String?
    var inhibitorError: String?
    var needsReauth = false
    var departureMessage: String?

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
        .alert("Abgang", isPresented: .constant(vm.departureMessage != nil)) {
            Button("OK") { vm.departureMessage = nil }
        } message: {
            Text(vm.departureMessage ?? "")
        }
    }

    private func detailContent(_ c: Cattle) -> some View {
        List {
            heroSection(c)
            wartezeitBanner(c)
            treatmentsSection
            inseminationsSection
            pregnancySection
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DateHelper.format(test.probe_date)).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("Nr. \(test.nummer ?? "\u{2013}")").font(.subheadline.bold())
                            if let s = test.status {
                                StatusBadge(text: s, color: s.lowercased() == "negativ" ? .green : .orange)
                            }
                        }
                    }
                    .padding(.vertical, 2)
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
