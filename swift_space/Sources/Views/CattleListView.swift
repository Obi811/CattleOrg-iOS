import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.cattleorg.app", category: "CattleList")

@Observable
@MainActor
final class CattleListViewModel {
    var cattle: [Cattle] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var needsReauth = false
    var hasMorePages = true
    private var currentPage = 1
    private let perPage = 50
    var searchText = ""
    var statusFilter = "Aktiv"

    // Erweiterte Filter (wie Web-Tierübersicht)
    var genderFilter = "Alle"          // Alle / W / M
    var stallFilter: String? = nil      // Stallname
    var wartezeitOnly = false
    var traechtigOnly = false
    var rasseFilter: String? = nil      // Rasse
    var minAgeText = ""                 // Alter in Monaten (mind.)
    var maxAgeText = ""                 // Alter in Monaten (max.)
    var trockensteherOnly = false       // nur Trockensteher (V0.10)
    var milchkuhOnly = false            // nur Milchkühe (V0.10)
    var stalls: [Stall] = []
    var breeds: [String] = []

    private var minAgeMonths: Int? { Int(minAgeText.trimmingCharacters(in: .whitespaces)) }
    private var maxAgeMonths: Int? { Int(maxAgeText.trimmingCharacters(in: .whitespaces)) }

    /// Anzahl aktiver Zusatzfilter (ohne Status), für das Badge am Filter-Button.
    var extraFilterCount: Int {
        var n = 0
        if genderFilter != "Alle" { n += 1 }
        if stallFilter != nil { n += 1 }
        if wartezeitOnly { n += 1 }
        if traechtigOnly { n += 1 }
        if rasseFilter != nil { n += 1 }
        if minAgeMonths != nil { n += 1 }
        if maxAgeMonths != nil { n += 1 }
        if trockensteherOnly { n += 1 }
        if milchkuhOnly { n += 1 }
        return n
    }

    private var genderParam: String? {
        switch genderFilter {
        case "W": return "W"
        case "M": return "M"
        default: return nil
        }
    }

    func loadStalls() async {
        guard stalls.isEmpty else { return }
        do { stalls = try await CattleAPI.fetchStalls() } catch { }
    }

    func loadBreeds() async {
        guard breeds.isEmpty else { return }
        do { breeds = try await CattleAPI.fetchBreeds() } catch { }
    }

    func resetExtraFilters() {
        genderFilter = "Alle"
        stallFilter = nil
        wartezeitOnly = false
        traechtigOnly = false
        rasseFilter = nil
        minAgeText = ""
        maxAgeText = ""
        trockensteherOnly = false
        milchkuhOnly = false
    }

    /// Wendet eine Voreinstellung aus einer Dashboard-Kachel an (setzt genau einen Filter).
    func applyPreset(_ preset: String) async {
        resetExtraFilters()
        statusFilter = "Aktiv"
        searchText = ""
        switch preset {
        case "trockensteher": trockensteherOnly = true
        case "milchkuh": milchkuhOnly = true
        default: break
        }
        await loadInitial()
    }

    func loadInitial() async {
        currentPage = 1
        hasMorePages = true
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await CattleAPI.fetchCattle(page: 1, perPage: perPage, search: searchText.isEmpty ? nil : searchText, status: statusFilter, geschlecht: genderParam, stall: stallFilter, wartezeitOnly: wartezeitOnly, traechtigOnly: traechtigOnly, rasse: rasseFilter, minAgeMonths: minAgeMonths, maxAgeMonths: maxAgeMonths, trockensteherOnly: trockensteherOnly, milchkuhOnly: milchkuhOnly)
            cattle = result.cattle
            if let meta = result.meta, let tp = meta.total_pages {
                hasMorePages = currentPage < tp
            } else {
                hasMorePages = result.cattle.count >= perPage
            }
        } catch let err as CattleAPIError {
            handleError(err)
        } catch {
            errorMessage = "Ein Fehler ist aufgetreten."
        }
    }

    func loadMore() async {
        guard hasMorePages, !isLoadingMore else { return }
        isLoadingMore = true
        currentPage += 1
        defer { isLoadingMore = false }
        do {
            let result = try await CattleAPI.fetchCattle(page: currentPage, perPage: perPage, search: searchText.isEmpty ? nil : searchText, status: statusFilter, geschlecht: genderParam, stall: stallFilter, wartezeitOnly: wartezeitOnly, traechtigOnly: traechtigOnly, rasse: rasseFilter, minAgeMonths: minAgeMonths, maxAgeMonths: maxAgeMonths, trockensteherOnly: trockensteherOnly, milchkuhOnly: milchkuhOnly)
            cattle.append(contentsOf: result.cattle)
            if let meta = result.meta, let tp = meta.total_pages {
                hasMorePages = currentPage < tp
            } else {
                hasMorePages = result.cattle.count >= perPage
            }
        } catch {
            currentPage -= 1
        }
    }

    private func handleError(_ err: CattleAPIError) {
        switch err {
        case .tokenExpired, .unauthorized: needsReauth = true
        default: errorMessage = err.localizedDescription
        }
    }
}

struct CattleListView: View {
    @Environment(SessionManager.self) private var session
    @Environment(PushRouter.self) private var pushRouter
    @State private var vm = CattleListViewModel()
    @State private var searchTask: Task<Void, Never>?
    @State private var showFilterSheet = false
    @State private var showGroupActions = false

    var body: some View {
        Group {
            if vm.isLoading && vm.cattle.isEmpty {
                loadingView
            } else if let err = vm.errorMessage, vm.cattle.isEmpty {
                errorView(err)
            } else if vm.cattle.isEmpty {
                emptyView
            } else {
                cattleList
            }
        }
        .navigationTitle("Tiere")
        .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Ohrmarke suchen\u{2026}")
        .onChange(of: vm.searchText) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await vm.loadInitial()
            }
        }
        .onChange(of: vm.statusFilter) { _, _ in
            Task { await vm.loadInitial() }
        }
        .onChange(of: vm.needsReauth) { _, val in
            if val { session.handleCattleAPIError(CattleAPIError.tokenExpired) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFilterSheet = true
                } label: {
                    Image(systemName: vm.extraFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter")
            }
            if session.canWrite {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showGroupActions = true
                    } label: {
                        Image(systemName: "square.stack.3d.up")
                    }
                    .accessibilityLabel("Gruppenaktion")
                }
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            NavigationStack {
                CattleFilterSheet(vm: vm)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showGroupActions, onDismiss: { Task { await vm.loadInitial() } }) {
            NavigationStack {
                GroupActionsView()
            }
        }
        .task {
            if let p = pushRouter.cattlePreset {
                pushRouter.cattlePreset = nil
                await vm.applyPreset(p)
            } else {
                await vm.loadInitial()
            }
            await vm.loadStalls()
            await vm.loadBreeds()
        }
        .onChange(of: pushRouter.cattlePreset) { _, preset in
            if let p = preset {
                pushRouter.cattlePreset = nil
                Task { await vm.applyPreset(p) }
            }
        }
        .refreshable { await vm.loadInitial() }
    }

    private var cattleList: some View {
        List {
            filterChips
            ForEach(vm.cattle) { animal in
                NavigationLink(value: animal.id) {
                    CattleRowView(cattle: animal)
                }
            }
            if vm.hasMorePages {
                loadMoreRow
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: FlexibleID.self) { id in
            CattleDetailView(cattleId: id.value)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["Aktiv", "Inaktiv", "Alle"], id: \.self) { status in
                    FilterChip(title: status, isSelected: vm.statusFilter == status) {
                        vm.statusFilter = status
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
    }

    private var loadMoreRow: some View {
        HStack {
            Spacer()
            if vm.isLoadingMore {
                ProgressView()
            } else {
                Button("Mehr laden\u{2026}") {
                    Task { await vm.loadMore() }
                }
                .foregroundStyle(AppTheme.primary)
            }
            Spacer()
        }
        .onAppear {
            Task { await vm.loadMore() }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Tiere werden geladen\u{2026}")
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
            Button("Erneut versuchen") { Task { await vm.loadInitial() } }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 200)
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Keine Tiere gefunden")
                .font(.headline)
            Text("Passen Sie Ihre Suche oder Filter an.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Cattle Row
struct CattleRowView: View {
    let cattle: Cattle

    var body: some View {
        HStack(spacing: 12) {
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(cattle.displayTag)
                        .font(.body.bold().monospaced())
                    if cattle.isWartezeitActive {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.warning)
                    }
                }
                HStack(spacing: 8) {
                    if let rasse = cattle.rasse {
                        Text(rasse).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let bd = cattle.birth_date {
                        Text(DateHelper.format(bd)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if let g = cattle.geschlecht {
                Image(systemName: g.lowercased().contains("w") ? "circle.and.line.horizontal" : "arrow.up.right")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
    }

    private var statusColor: Color {
        if cattle.isWartezeitActive { return AppTheme.warning }
        return cattle.status?.statusColor ?? .gray
    }
}

// MARK: - Cattle Filter Sheet
struct CattleFilterSheet: View {
    @Bindable var vm: CattleListViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var minAgeFocused: Bool
    @FocusState private var maxAgeFocused: Bool

    var body: some View {
        Form {
            Section("Geschlecht") {
                Picker("Geschlecht", selection: $vm.genderFilter) {
                    Text("Alle").tag("Alle")
                    Text("Weiblich").tag("W")
                    Text("Männlich").tag("M")
                }
                .pickerStyle(.segmented)
            }

            Section("Rasse") {
                Picker("Rasse", selection: Binding(
                    get: { vm.rasseFilter ?? "" },
                    set: { vm.rasseFilter = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Alle Rassen").tag("")
                    ForEach(vm.breeds, id: \.self) { breed in
                        Text(breed).tag(breed)
                    }
                }
            }

            Section("Stall") {
                Picker("Stall", selection: Binding(
                    get: { vm.stallFilter ?? "" },
                    set: { vm.stallFilter = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Alle Ställe").tag("")
                    ForEach(vm.stalls) { stall in
                        Text(stall.name ?? "–").tag(stall.name ?? "")
                    }
                }
            }

            Section {
                HStack {
                    Text("Mind.")
                    TextField("0", text: $vm.minAgeText)
                        .keyboardType(.numberPad)
                        .focused($minAgeFocused)
                        .multilineTextAlignment(.trailing)
                        .contentShape(Rectangle())
                        .onTapGesture { minAgeFocused = true }
                    Text("Monate").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Höchstens")
                    TextField("–", text: $vm.maxAgeText)
                        .keyboardType(.numberPad)
                        .focused($maxAgeFocused)
                        .multilineTextAlignment(.trailing)
                        .contentShape(Rectangle())
                        .onTapGesture { maxAgeFocused = true }
                    Text("Monate").foregroundStyle(.secondary)
                }
            } header: {
                Text("Alter (in Monaten)")
            }

            Section("Weitere Kriterien") {
                Toggle("Nur mit aktiver Wartezeit", isOn: $vm.wartezeitOnly)
                Toggle("Nur trächtige Tiere", isOn: $vm.traechtigOnly)
                Toggle("Nur Milchkühe", isOn: $vm.milchkuhOnly)
                Toggle("Nur Trockensteher", isOn: $vm.trockensteherOnly)
            }
        }
        .navigationTitle("Filter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Zurücksetzen") {
                    vm.resetExtraFilters()
                    Task { await vm.loadInitial() }
                }
                .disabled(vm.extraFilterCount == 0)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fertig") { dismiss() }
            }
        }
        .onChange(of: vm.genderFilter) { _, _ in Task { await vm.loadInitial() } }
        .onChange(of: vm.stallFilter) { _, _ in Task { await vm.loadInitial() } }
        .onChange(of: vm.wartezeitOnly) { _, _ in Task { await vm.loadInitial() } }
        .onChange(of: vm.traechtigOnly) { _, _ in Task { await vm.loadInitial() } }
        .onChange(of: vm.rasseFilter) { _, _ in Task { await vm.loadInitial() } }
        .onChange(of: vm.milchkuhOnly) { _, _ in Task { await vm.loadInitial() } }
        .onChange(of: vm.trockensteherOnly) { _, _ in Task { await vm.loadInitial() } }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") {
                    minAgeFocused = false
                    maxAgeFocused = false
                    Task { await vm.loadInitial() }
                }
            }
        }
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? AppTheme.primary : Color(.systemGray5))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
