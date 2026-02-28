import SwiftUI
import TabXHostLib

struct RecentlyClosedView: View {
    @Environment(AppState.self) var appState

    private var visibleItems: [ClosedTabItem] {
        Array(appState.recentlyClosed.prefix(10))
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(visibleItems) { item in
                ClosedTabRow(item: item) {
                    appState.undoClose(item)
                }
            }
        }
    }
}

// MARK: - ClosedTabRow

private struct ClosedTabRow: View {
    let item: ClosedTabItem
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(relativeTime(item.closedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onUndo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.vertical, 5)
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    let state = AppState()
    return RecentlyClosedView()
        .environment(state)
        .frame(width: 360)
        .padding(.horizontal, 12)
}
