import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.cattleorg.app", category: "TaskList")

@Observable
@MainActor
final class TaskListViewModel {
    var dashboard: DashboardResponse?
    var isLoading = false
    var errorMessage: String?
    var isNotAvailable = false
    var needsReauth = false
    var actionMessage: String?

    /// Markiert eine geplante Behandlung als erledigt (erzeugt eine Behandlung am gewählten Datum).
    func complete(_ pt: PlannedTreatment, date: Date) async {
        do {
            try await CattleAPI.completePlannedTreatment(id: pt.id.value, treatmentDate: DateHelper.apiString(from: date))
            await load()
            actionMessage = "Als Behandlung übernommen."
        } catch let err as CattleAPIError {
            actionMessage = err.localizedDescription
        } catch {
            actionMessage = "Aktion fehlgeschlagen."
        }
    }

    /// Verwirft eine geplante Behandlung (entfernt sie).
    func discard(_ pt: PlannedTreatment) async {
        do {
            try await CattleAPI.deletePlannedTreatment(id: pt.id.value)
            await load()
        } catch let err as CattleAPIError {
            actionMessage = err.localizedDescription
        } catch {
            actionMessage = "Aktion fehlgeschlagen."
        }
    }

    // TODO: Server-Endpunkt /api/v1/dashboard/ noch nicht implementiert
    func load() async {
        isLoading = true
        errorMessage = nil
        isNotAvailable = false
        defer { isLoading = false }
        do {
            dashboard = try await CattleAPI.fetchDashboard()
        } catch let err as CattleAPIError {
            switch err {
            case .tokenExpired, .unauthorized: needsReauth = true
            case .notFound: isNotAvailable = true
            default: errorMessage = err.localizedDescription
            }
        } catch {
            errorMessage = "Ein Fehler ist aufgetreten."
        }
    }
}

struct TaskListView: View {
    @Environment(SessionManager.self) private var session
    @Environment(PushRouter.self) private var pushRouter
    @State private var vm = TaskListViewModel()
    /// Aktiver Kategorie-Filter (aus einer Sammel-Mitteilung): traechtigkeit / hemmstoff / weiterbehandlung.
    @State private var activeFilter: String?
    @State private var completingTreatment: PlannedTreatment?
    @State private var editingTreatment: PlannedTreatment?
    @State private var completeDate = Date()

    var body: some View {
        Group {
            if vm.isLoading && vm.dashboard == nil {
                ProgressView("Aufgaben werden geladen\u{2026}")
            } else if vm.isNotAvailable {
                notAvailableView
            } else if let err = vm.errorMessage {
                errorView(err)
            } else {
                taskList
            }
        }
        .navigationTitle("Aufgaben")
        .task {
            await vm.load()
            applyPendingFilter()
        }
        .refreshable { await vm.load() }
        .onChange(of: vm.needsReauth) { _, val in
            if val { session.handleCattleAPIError(CattleAPIError.tokenExpired) }
        }
        .onChange(of: pushRouter.taskFilter) { _, _ in
            applyPendingFilter()
        }
        .sheet(item: $completingTreatment) { pt in
            NavigationStack {
                Form {
                    Section("Behandlungsdatum") {
                        DatePicker("Datum", selection: $completeDate, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "de_DE"))
                    }
                    Section {
                        Text("\(pt.displayTag) wird als Behandlung übernommen.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Als erledigt markieren")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { completingTreatment = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Erledigt") {
                            let p = pt
                            completingTreatment = nil
                            Task { await vm.complete(p, date: completeDate) }
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $editingTreatment, onDismiss: { Task { await vm.load() } }) { pt in
            NavigationStack {
                QuickEntrySheet(initialType: .plannedTreatment, editingPlanned: pt)
            }
        }
        .alert("Geplante Behandlung", isPresented: .constant(vm.actionMessage != nil)) {
            Button("OK") { vm.actionMessage = nil }
        } message: {
            Text(vm.actionMessage ?? "")
        }
    }

    /// Übernimmt einen vom Push gesetzten Filter und setzt ihn im Router zurück.
    private func applyPendingFilter() {
        if let f = pushRouter.taskFilter {
            activeFilter = f
            pushRouter.taskFilter = nil
        }
    }

    /// Welche Sektionen bei aktivem Filter sichtbar sind.
    private func isVisible(_ key: String) -> Bool {
        guard let f = activeFilter else { return true }
        switch f {
        case "traechtigkeit": return key == "tu"
        case "hemmstoff": return key == "hemmstoff_versendet"
        case "weiterbehandlung": return key == "weiterbehandlung"
        default: return true
        }
    }

    private var filterLabel: String {
        switch activeFilter {
        case "traechtigkeit": return "TU-Kontrollen"
        case "hemmstoff": return "Versendete Proben"
        case "weiterbehandlung": return "Weiterbehandlungen"
        default: return "Gefiltert"
        }
    }

    private var taskList: some View {
        List {
            if activeFilter != nil {
                filterBanner
            }
            if activeFilter == nil, let planned = vm.dashboard?.geplante_faellig {
                plannedSection(planned)
            }
            if isVisible("wartezeit") {
                taskSection(title: "Wartezeit aktiv", icon: "clock.badge.exclamationmark", tasks: vm.dashboard?.wartezeit_aktiv)
            }
            if isVisible("weiterbehandlung") {
                taskSection(title: "Weiterbehandlungen f\u{00E4}llig", icon: "syringe", tasks: vm.dashboard?.weiterbehandlungen)
            }
            if isVisible("hemmstoff_faellig") {
                taskSection(title: "Hemmstoffproben f\u{00E4}llig", icon: "flask", tasks: vm.dashboard?.hemmstoff_faellig)
            }
            if isVisible("hemmstoff_versendet") {
                taskSection(title: "Versendete Proben", icon: "shippingbox", tasks: vm.dashboard?.hemmstoff_versendet)
            }
            if isVisible("tu") {
                taskSection(title: "TU-Kontrollen f\u{00E4}llig", icon: "heart.text.clipboard", tasks: vm.dashboard?.tu_faellig)
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: FlexibleID.self) { id in
            CattleDetailView(cattleId: id.value)
        }
    }

    private var filterBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(AppTheme.primary)
            Text("Gefiltert: \(filterLabel)")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button {
                activeFilter = nil
            } label: {
                Label("Filter entfernen", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
        .listRowBackground(AppTheme.primary.opacity(0.08))
    }

    @ViewBuilder
    private func plannedSection(_ items: [PlannedTreatment]) -> some View {
        Section {
            if items.isEmpty {
                Text("Keine f\u{00E4}lligen geplanten Behandlungen")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(items) { pt in
                    plannedRow(pt)
                }
            }
        } header: {
            Label {
                HStack {
                    Text("Geplante Behandlungen f\u{00E4}llig")
                    Spacer()
                    if !items.isEmpty {
                        Text("\(items.count)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.teal, in: Capsule())
                    }
                }
            } icon: {
                Image(systemName: "calendar.badge.clock")
            }
        }
    }

    @ViewBuilder
    private func plannedRow(_ pt: PlannedTreatment) -> some View {
        let overdue = pt.overdueDays > 0
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(pt.displayTag)
                    .font(.body.bold().monospaced())
                if overdue {
                    Text("\(pt.overdueDays) Tg. \u{00FC}berf\u{00E4}llig")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.warning, in: Capsule())
                }
                Spacer()
                Text(DateHelper.format(pt.planned_date))
                    .font(.caption)
                    .foregroundStyle(overdue ? AppTheme.warning : .secondary)
            }
            if let med = pt.medication, !med.isEmpty {
                Text(med).font(.caption).foregroundStyle(.secondary)
            }
            if let t = pt.type, !t.isEmpty {
                Text(t).font(.caption2).foregroundStyle(.secondary)
            }
            if session.canWrite {
                HStack(spacing: 8) {
                    Button {
                        completeDate = Date()
                        completingTreatment = pt
                    } label: {
                        Label("Erledigt", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.green)
                    Button {
                        editingTreatment = pt
                    } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.blue)
                    Button(role: .destructive) {
                        Task { await vm.discard(pt) }
                    } label: {
                        Label("Verwerfen", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(AppTheme.warning)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(overdue ? AppTheme.warning.opacity(0.08) : Color(.secondarySystemGroupedBackground))
    }

    private func taskSection(title: String, icon: String, tasks: [DashboardTask]?) -> some View {
        Section {
            if let tasks = tasks, !tasks.isEmpty {
                ForEach(tasks) { task in
                    taskRow(task)
                }
            } else {
                Text("Keine Eintr\u{00E4}ge")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        } header: {
            Label {
                HStack {
                    Text(title)
                    Spacer()
                    if let c = tasks?.count, c > 0 {
                        Text("\(c)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(AppTheme.primary, in: Capsule())
                    }
                }
            } icon: {
                Image(systemName: icon)
            }
        }
    }

    @ViewBuilder
    private func taskRow(_ task: DashboardTask) -> some View {
        if let cid = task.cattle_id {
            NavigationLink(value: cid) { taskRowContent(task) }
        } else {
            taskRowContent(task)
        }
    }

    private func taskRowContent(_ task: DashboardTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.displayTag)
                .font(.body.bold().monospaced())
            if let date = task.displayDate {
                Text(DateHelper.format(date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let med = task.medication {
                Text(med).font(.caption).foregroundStyle(.secondary)
            }
            if let nr = task.nummer {
                Text("Probe Nr. \(nr)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var notAvailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Aufgaben werden vorbereitet")
                .font(.headline)
            Text("Diese Funktion ist bald verf\u{00FC}gbar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message).multilineTextAlignment(.center)
            Button("Erneut versuchen") { Task { await vm.load() } }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 200)
        }
        .padding()
    }
}
