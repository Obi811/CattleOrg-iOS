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
    var statusFilter = "Alle"

    func loadInitial() async {
        currentPage = 1
        hasMorePages = true
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await CattleAPI.fetchCattle(page: 1, perPage: perPage, search: searchText.isEmpty ? nil : searchText, status: statusFilter)
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
            let result = try await CattleAPI.fetchCattle(page: currentPage, perPage: perPage, search: searchText.isEmpty ? nil : searchText, status: statusFilter)
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
    @State private var vm = CattleListViewModel()
    @State private var searchTask: Task<Void, Never>?

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
        .task { await vm.loadInitial() }
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
                ForEach(["Alle", "Aktiv", "Trocken", "Abgegangen"], id: \.self) { status in
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
