import SwiftUI
import TabXHostLib

// MARK: - App entry point

@main
struct TabXApp: App {
    @State private var appState: AppState
    @State private var messagingService: NativeMessagingService

    init() {
        let state = AppState()
        let service = NativeMessagingService(appState: state)
        service.startIfPiped()
        _appState = State(initialValue: state)
        _messagingService = State(initialValue: service)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(appState: appState)
        } label: {
            Label("TabX", systemImage: "list.bullet.rectangle")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Top-level panel

struct MenuBarPanel: View {
    @Bindable var appState: AppState
    @State private var selectedTab: PanelSection = .tabs

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(appState: appState)
            Divider()
            sectionPicker
            Divider()
            sectionContent
        }
        .frame(width: 380)
        .background(.regularMaterial)
    }

    private var sectionPicker: some View {
        Picker("", selection: $selectedTab) {
            Text("Tabs (\(appState.tabResults.count))").tag(PanelSection.tabs)
            Text("Closed").tag(PanelSection.closed)
            Text("Settings").tag(PanelSection.settings)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedTab {
        case .tabs:
            TabListView(tabResults: appState.tabResults)
        case .closed:
            ClosedTabsView(appState: appState)
        case .settings:
            SettingsView(appState: appState)
        }
    }
}

enum PanelSection: Hashable {
    case tabs, closed, settings
}

// MARK: - Header

struct PanelHeader: View {
    let appState: AppState

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TabX")
                    .font(.headline)
                if let branch = appState.gitBranch {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let repo = appState.gitRepoPath {
                    Text((repo as NSString).lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            BundleStatusBadge(generatedAt: appState.bundleGeneratedAt)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct BundleStatusBadge: View {
    let generatedAt: Date?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let date = generatedAt {
                Text("Bundle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No bundle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Tab list

struct TabListView: View {
    let tabResults: [TabDisplayItem]

    var body: some View {
        if tabResults.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(tabResults) { tab in
                        TabRowView(tab: tab)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 300)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No tab data yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("TabX will score tabs when Chrome sends an update.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}

struct TabRowView: View {
    let tab: TabDisplayItem

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(decisionColor)
                .frame(width: 3, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .font(.callout)
                    .lineLimit(1)
                Text(tab.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f%%", tab.score * 100))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(decisionColor)
                Text(tab.decision.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.quinary.opacity(0.5))
        .cornerRadius(4)
        .padding(.horizontal, 6)
    }

    private var decisionColor: Color {
        switch tab.decision {
        case .close: return .red
        case .keep:  return .green
        case .flag:  return .yellow
        }
    }
}

// MARK: - Closed tabs

struct ClosedTabsView: View {
    @Bindable var appState: AppState

    var body: some View {
        if appState.recentlyClosed.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("No recently closed tabs")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(appState.recentlyClosed) { record in
                        ClosedTabRow(record: record) {
                            appState.recentlyClosed.removeAll { $0.id == record.id }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 300)
        }
    }
}

struct ClosedTabRow: View {
    let record: ClosedTabRecord
    let onUndo: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.item.title)
                    .font(.callout)
                    .lineLimit(1)
                Text(record.closedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Undo", action: onUndo)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quinary.opacity(0.5))
        .cornerRadius(4)
        .padding(.horizontal, 6)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Bindable var appState: AppState
    @State private var newDomain: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sensitivitySection
                Divider()
                safelistSection
            }
            .padding(12)
        }
        .frame(maxHeight: 300)
    }

    private var sensitivitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sensitivity")
                .font(.callout)
                .fontWeight(.medium)
            HStack(spacing: 8) {
                Text("Permissive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $appState.sensitivity, in: 0...1, step: 0.05)
                Text("Aggressive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(Int(appState.sensitivity * 100))% — higher values close more tabs")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var safelistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Safelist")
                .font(.callout)
                .fontWeight(.medium)
            Text("Domains that are never auto-closed")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("github.com", text: $newDomain)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .onSubmit { commitDomain() }
                Button("Add") { commitDomain() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !appState.safelist.isEmpty {
                VStack(spacing: 3) {
                    ForEach(appState.safelist, id: \.self) { domain in
                        HStack {
                            Text(domain)
                                .font(.callout)
                            Spacer()
                            Button {
                                appState.removeFromSafelist(domain)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quinary)
                        .cornerRadius(4)
                    }
                }
            }
        }
    }

    private func commitDomain() {
        let domain = newDomain.trimmingCharacters(in: .whitespaces)
        guard !domain.isEmpty else { return }
        appState.addToSafelist(domain)
        newDomain = ""
    }
}
