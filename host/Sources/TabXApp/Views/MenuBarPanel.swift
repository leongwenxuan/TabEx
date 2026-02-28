import SwiftUI
import TabXHostLib

struct MenuBarPanel: View {
    @Environment(AppState.self) var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                headerView

                Divider()

                // Context info
                ContextInfoView()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Divider()

                // Tabs section
                sectionHeader("Tabs")
                TabListView()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                // Recently Closed (only if non-empty)
                if !appState.recentlyClosed.isEmpty {
                    Divider()
                    sectionHeader("Recently Closed")
                    RecentlyClosedView()
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }

                Divider()

                // Settings
                SettingsView()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Divider()

                // Footer
                footerView
            }
        }
        .frame(width: 360)
        .frame(maxHeight: 500)
        .background(.ultraThinMaterial)
        .task { appState.startServices() }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            Text("TabX")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(appState.isConnected ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(appState.isConnected ? "Connected" : "Disconnected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private var footerView: some View {
        HStack {
            Spacer()
            Button("Quit TabX") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview {
    let state = AppState()
    return MenuBarPanel()
        .environment(state)
}
