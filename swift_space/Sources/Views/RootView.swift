import SwiftUI

struct RootView: View {
    @Environment(SessionManager.self) private var session

    var body: some View {
        Group {
            if session.isLoading {
                splashView
            } else if !session.isAuthenticated {
                LoginView()
            } else if session.selectedFarm == nil {
                FarmPickerView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: session.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: session.selectedFarm?.id.value)
    }

    private var splashView: some View {
        VStack(spacing: 16) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(AppTheme.primary)
            Text("CattleOrg")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            ProgressView()
                .tint(AppTheme.primary)
        }
    }
}
