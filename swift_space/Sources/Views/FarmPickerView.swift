import SwiftUI

struct FarmPickerView: View {
    @Environment(SessionManager.self) private var session

    var body: some View {
        NavigationStack {
            List(session.farms) { farm in
                Button {
                    session.selectFarm(farm)
                } label: {
                    farmRow(farm)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Betrieb auswählen")
        }
    }

    private func farmRow(_ farm: Farm) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(farm.name ?? "Betrieb")
                    .font(.headline)
                if let role = farm.role {
                    Text(role.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if farm.is_demo == true {
                Text("Demo")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.demoBadge, in: Capsule())
            }
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
