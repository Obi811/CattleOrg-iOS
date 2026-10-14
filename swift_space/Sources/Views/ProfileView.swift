import SwiftUI
import UIKit
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.cattleorg.app", category: "Profile")

struct ProfileView: View {
    @Environment(SessionManager.self) private var session
    @State private var showLogoutAlert = false
    @State private var showChangePassword = false
    @State private var showFarmPicker = false
    @State private var notificationsEnabled = false

    var body: some View {
        List {
            userSection
            farmSection
            settingsSection
            logoutSection
            versionSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Profil")
        .alert("Abmelden", isPresented: $showLogoutAlert) {
            Button("Abmelden", role: .destructive) { session.logout() }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("M\u{00F6}chten Sie sich wirklich abmelden?")
        }
        .sheet(isPresented: $showChangePassword) {
            NavigationStack {
                ChangePasswordView()
            }
        }
        .fullScreenCover(isPresented: $showFarmPicker) {
            FarmPickerView()
        }
        .task { await checkNotificationStatus() }
    }

    private var userSection: some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppTheme.primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.userName)
                        .font(.title3.bold())
                    if session.currentUser?.is_admin == true {
                        StatusBadge(text: "Admin", color: AppTheme.primary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var farmSection: some View {
        Section("Betrieb") {
            HStack {
                VStack(alignment: .leading) {
                    Text(session.farmName)
                        .font(.headline)
                    if session.isDemo {
                        Text("Demo \u{2013} nur Lesezugriff")
                            .font(.caption)
                            .foregroundStyle(AppTheme.demoBadge)
                    }
                }
                Spacer()
                if session.farms.count > 1 {
                    Button("Wechseln") {
                        session.switchFarm()
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.primary)
                }
            }
        }
    }

    private var settingsSection: some View {
        Section("Einstellungen") {
            Button {
                showChangePassword = true
            } label: {
                Label("Passwort \u{00E4}ndern", systemImage: "lock.rotation")
            }

            HStack {
                Label("Benachrichtigungen", systemImage: "bell")
                Spacer()
                Toggle("", isOn: $notificationsEnabled)
                    .labelsHidden()
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled {
                            Task { await requestNotificationPermission() }
                        }
                    }
            }
        }
    }

    private var logoutSection: some View {
        Section {
            Button(role: .destructive) {
                showLogoutAlert = true
            } label: {
                Label("Abmelden", systemImage: "arrow.right.square")
                    .foregroundStyle(AppTheme.warning)
            }
        }
    }

    private var versionSection: some View {
        Section {
            HStack {
                Spacer()
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .listRowBackground(Color.clear)
    }

    private func checkNotificationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        notificationsEnabled = settings.authorizationStatus == .authorized
    }

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            notificationsEnabled = granted
            if granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
            logger.info("Notification permission: \(granted)")
        } catch {
            logger.error("Notification permission error: \(error.localizedDescription)")
            notificationsEnabled = false
        }
    }
}

// MARK: - Change Password View
// TODO: Server-Endpunkt /api/v1/user/password/ noch nicht implementiert
struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @FocusState private var focusedField: Int?

    var body: some View {
        Form {
            Section("Aktuelles Passwort") {
                SecureField("Aktuelles Passwort", text: $currentPassword)
                    .focused($focusedField, equals: 0)
                    .textContentType(.password)
                    .padding(4)
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = 0 }
            }
            Section("Neues Passwort") {
                SecureField("Neues Passwort", text: $newPassword)
                    .focused($focusedField, equals: 1)
                    .textContentType(.newPassword)
                    .padding(4)
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = 1 }
                SecureField("Passwort best\u{00E4}tigen", text: $confirmPassword)
                    .focused($focusedField, equals: 2)
                    .textContentType(.newPassword)
                    .padding(4)
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = 2 }
            }

            if let err = errorMessage {
                Section {
                    Text(err).foregroundStyle(AppTheme.warning).font(.subheadline)
                }
            }
            if let msg = successMessage {
                Section {
                    Text(msg).foregroundStyle(AppTheme.accent).font(.subheadline)
                }
            }

            Section {
                Button {
                    Task { await changePassword() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Passwort \u{00E4}ndern")
                    }
                }
                .disabled(isLoading || currentPassword.isEmpty || newPassword.isEmpty || newPassword != confirmPassword)
            }
        }
        .navigationTitle("Passwort \u{00E4}ndern")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
        }
    }

    private func changePassword() async {
        errorMessage = nil
        successMessage = nil
        guard newPassword == confirmPassword else {
            errorMessage = "Passw\u{00F6}rter stimmen nicht \u{00FC}berein."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await CattleAPI.changePassword(currentPassword: currentPassword, newPassword: newPassword)
            successMessage = "Passwort erfolgreich ge\u{00E4}ndert."
        } catch let err as CattleAPIError {
            if case .notFound = err {
                errorMessage = "Diese Funktion ist noch nicht verf\u{00FC}gbar. Bitte den Server-Endpunkt erg\u{00E4}nzen."
            } else {
                errorMessage = err.localizedDescription
            }
        } catch {
            errorMessage = "Ein Fehler ist aufgetreten."
        }
    }
}
