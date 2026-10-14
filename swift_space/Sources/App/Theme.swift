import SwiftUI

enum AppTheme {
    static let primary = Color(red: 45/255, green: 122/255, blue: 58/255)
    static let accent = Color(red: 76/255, green: 175/255, blue: 80/255)
    static let warning = Color(red: 211/255, green: 47/255, blue: 47/255)
    static let demoBadge = Color(red: 245/255, green: 124/255, blue: 0/255)

    static var primaryGradient: LinearGradient {
        LinearGradient(colors: [primary, accent], startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Reusable Button Style
struct PrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDestructive ? AnyShapeStyle(AppTheme.warning) : AnyShapeStyle(AppTheme.primaryGradient))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3), value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}

// MARK: - Status Colors
extension String {
    var statusColor: Color {
        switch self.lowercased() {
        case "aktiv": return AppTheme.accent
        case "trocken": return .orange
        case "abgegangen", "verkauft": return .gray
        case "krank": return .red
        default: return .secondary
        }
    }
}
