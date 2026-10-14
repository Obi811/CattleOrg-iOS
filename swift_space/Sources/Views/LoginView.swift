import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.cattleorg.app", category: "LoginView")

struct LoginView: View {
    @Environment(SessionManager.self) private var session
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case username, password }

    var body: some View {
        ZStack {
            backgroundGradient
            ScrollView {
                VStack(spacing: 32) {
                    Spacer().frame(height: 40)
                    logoSection
                    loginCard
                    versionLabel
                    Spacer()
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Sub Views
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(.systemBackground), AppTheme.primary.opacity(0.08)],
            startPoint: .top, endPoint: .bottom
        ).ignoresSafeArea()
    }

    private var logoSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.primary)
            Text("CattleOrg")
                .font(.system(size: 28, weight: .bold, design: .rounded))
        }
    }

    private var loginCard: some View {
        VStack(spacing: 16) {
            usernameField
            passwordField
            errorBanner
            loginButton
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var usernameField: some View {
        TextField("Benutzername", text: $username)
            .textContentType(.username)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($focusedField, equals: .username)
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
            .contentShape(Rectangle())
            .onTapGesture { focusedField = .username }
    }

    private var passwordField: some View {
        HStack {
            Group {
                if showPassword {
                    TextField("Passwort", text: $password)
                } else {
                    SecureField("Passwort", text: $password)
                }
            }
            .textContentType(.password)
            .focused($focusedField, equals: .password)

            Button { showPassword.toggle() } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
        .contentShape(Rectangle())
        .onTapGesture { focusedField = .password }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let msg = errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(msg)
                    .font(.subheadline)
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(AppTheme.warning, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var loginButton: some View {
        Button {
            Task { await performLogin() }
        } label: {
            Group {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Anmelden")
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isLoading || username.isEmpty || password.isEmpty)
        .sensoryFeedback(.selection, trigger: isLoading)
    }

    private var versionLabel: some View {
        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Actions
    private func performLogin() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await session.login(username: username, password: password)
            logger.info("Login succeeded")
        } catch let err as CattleAPIError {
            errorMessage = err.localizedDescription
            logger.warning("Login failed: \(err.localizedDescription)")
        } catch {
            errorMessage = "Ein Fehler ist aufgetreten. Bitte versuchen Sie es erneut."
        }
    }
}
