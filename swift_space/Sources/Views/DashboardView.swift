import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.cattleorg.app", category: "Dashboard")

@Observable
@MainActor
final class DashboardViewModel {
    var dashboard: DashboardResponse?
    var isLoading = false
    var errorMessage: String?
    var isNotAvailable = false
    var needsReauth = false

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

struct DashboardView: View {
    @Environment(SessionManager.self) private var session
    @State private var vm = DashboardViewModel()
    @Binding var selectedTab: Int

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                greetingSection
                tilesSection
            }
            .padding()
        }
        .navigationTitle("\u{00DC}bersicht")
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .onChange(of: vm.needsReauth) { _, val in
            if val { session.handleCattleAPIError(CattleAPIError.tokenExpired) }
        }
    }

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hallo, \(session.userName)")
                .font(.title2.bold())
            if !session.farmName.isEmpty {
                Text(session.farmName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.primary.opacity(0.1), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var tilesSection: some View {
        if vm.isLoading && vm.dashboard == nil {
            shimmerTiles
        } else if vm.isNotAvailable {
            notAvailableCard
        } else if let err = vm.errorMessage {
            errorCard(err)
        } else {
            tilesGrid
        }
    }

    private var tilesGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            DashboardTile(icon: "clock.badge.exclamationmark", label: "Wartezeit aktiv", count: vm.dashboard?.wartezeit_aktiv?.count ?? 0, color: AppTheme.warning) {
                selectedTab = 2
            }
            DashboardTile(icon: "syringe", label: "Weiterbehandlungen", count: vm.dashboard?.weiterbehandlungen?.count ?? 0, color: .orange) {
                selectedTab = 2
            }
            DashboardTile(icon: "flask", label: "Hemmstoff f\u{00E4}llig", count: vm.dashboard?.hemmstoff_faellig?.count ?? 0, color: .purple) {
                selectedTab = 2
            }
            DashboardTile(icon: "shippingbox", label: "Proben versendet", count: vm.dashboard?.hemmstoff_versendet?.count ?? 0, color: .blue) {
                selectedTab = 2
            }
            DashboardTile(icon: "heart.text.clipboard", label: "TU f\u{00E4}llig", count: vm.dashboard?.tu_faellig?.count ?? 0, color: AppTheme.primary) {
                selectedTab = 2
            }
        }
    }

    private var shimmerTiles: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray5))
                    .frame(height: 120)
            }
        }
    }

    private var notAvailableCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Dashboard wird vorbereitet.")
                .font(.headline)
            Text("Diese Funktion ist bald verf\u{00FC}gbar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(AppTheme.warning)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button("Erneut versuchen") { Task { await vm.load() } }
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct DashboardTile: View {
    let icon: String
    let label: String
    let count: Int
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text("\(count)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
