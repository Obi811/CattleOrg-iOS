import SwiftUI

@main
struct CattleOrgAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = SessionManager()
    @State private var pushRouter = PushRouter.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(pushRouter)
        }
    }
}
