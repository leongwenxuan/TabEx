import SwiftUI
import TabXHostLib

struct ContextInfoView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        HStack(spacing: 16) {
            Label(branchText, systemImage: "arrow.triangle.branch")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Label(repoText, systemImage: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Label(bundleText, systemImage: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Computed properties

    private var branchText: String {
        appState.gitBranch ?? "No branch"
    }

    private var repoText: String {
        guard let path = appState.gitRepoPath else { return "No repo" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var bundleText: String {
        switch appState.bundleStatus {
        case .none:
            return "No bundle"
        case .available:
            if let time = appState.lastBundleTime {
                return "Bundle: \(relativeTime(time))"
            }
            return "Bundle ready"
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    let state = AppState()
    return ContextInfoView()
        .environment(state)
        .frame(width: 360)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
}
