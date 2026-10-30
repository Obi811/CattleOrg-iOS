import SwiftUI
import UIKit
import UserNotifications

struct MainTabView: View {
    @Environment(SessionManager.self) private var session
    @Environment(PushRouter.self) private var pushRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var showQuickEntry = false
    @State private var quickEntryType: QuickEntryType?
    @State private var cattlePath = NavigationPath()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                Tab("\u{00DC}bersicht", systemImage: "house.fill", value: 0) {
                    NavigationStack {
                        DashboardView(selectedTab: $selectedTab)
                    }
                }
                Tab("Tiere", systemImage: "pawprint.fill", value: 1) {
                    NavigationStack(path: $cattlePath) {
                        CattleListView()
                    }
                }
                Tab("Aufgaben", systemImage: "checklist", value: 2) {
                    NavigationStack {
                        TaskListView()
                    }
                }
                Tab("Profil", systemImage: "person.fill", value: 3) {
                    NavigationStack {
                        ProfileView()
                    }
                }
            }
            .tint(AppTheme.primary)

            if session.canWrite {
                fabButton
            }
        }
        .sheet(item: $quickEntryType) { type in
            NavigationStack {
                QuickEntrySheet(initialType: type)
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .task {
            clearAppBadge()
            await requestPushPermissionIfNeeded()
            if let hex = pushRouter.deviceTokenHex {
                await session.registerDeviceTokenIfPossible(hex)
            }
            if let target = pushRouter.pendingTarget {
                handlePushTarget(target)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { clearAppBadge() }
        }
        .onChange(of: pushRouter.cattlePreset) { _, preset in
            if preset != nil { selectedTab = 1 }
        }
        .onChange(of: pushRouter.deviceTokenHex) { _, hex in
            if let hex { Task { await session.registerDeviceTokenIfPossible(hex) } }
        }
        .onChange(of: pushRouter.pendingTarget) { _, target in
            if let target { handlePushTarget(target) }
        }
    }

    /// Setzt den roten Zähler (Badge) auf dem App-Icon zurück, sobald die App geöffnet/aktiv ist.
    private func clearAppBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    private func handlePushTarget(_ target: PushTarget) {
        switch target {
        case .tasks(let filter):
            selectedTab = 2
            pushRouter.taskFilter = filter
        case .cattle(let id):
            selectedTab = 1
            cattlePath = NavigationPath()
            cattlePath.append(FlexibleID(id))
        }
        pushRouter.pendingTarget = nil
    }

    private func requestPushPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            if let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge]), granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
        case .authorized, .provisional, .ephemeral:
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        default:
            break
        }
    }

    private var fabButton: some View {
        Button {
            quickEntryType = .treatment
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.accent)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 80)
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "cattleorg" else { return }
        switch url.host {
        case "tasks":
            selectedTab = 2
        case "cattle":
            selectedTab = 1
        default:
            break
        }
    }
}
