import SwiftUI
import TabXHostLib

struct TabListView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        if appState.tabs.isEmpty {
            Text("No tabs scored yet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(appState.tabs) { tab in
                    TabRowView(tab: tab)
                }
            }
        }
    }
}

// MARK: - TabRowView

private struct TabRowView: View {
    let tab: TabDisplayItem

    var decisionColor: Color {
        switch tab.decision {
        case .keep:  return .green
        case .close: return .red
        case .flag:  return .yellow
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(decisionColor)
                .frame(width: 10, height: 10)
                .padding(.top, 2)
                .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .font(.system(.body, design: .default, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(tab.url)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(String(format: "%.0f", tab.score * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    let state = AppState()
    return TabListView()
        .environment(state)
        .frame(width: 360)
        .padding(.horizontal, 12)
}
