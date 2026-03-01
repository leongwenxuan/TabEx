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
    @State private var selectedTab: PanelSection = .arena

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(appState: appState)
            Divider()
            sectionPicker
            Divider()
            sectionContent
            Spacer(minLength: 0)
        }
        .frame(width: 440, height: 520)
        .background(.regularMaterial)
    }

    private var sectionPicker: some View {
        Picker("", selection: $selectedTab) {
            Text("Arena").tag(PanelSection.arena)
            Text("Tabs (\(appState.tabResults.count))").tag(PanelSection.tabs)
            Text("Branches").tag(PanelSection.branches)
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
        case .arena:
            ArenaView(appState: appState)
        case .tabs:
            TabListView(tabResults: appState.tabResults)
        case .branches:
            BranchesView(appState: appState)
        case .closed:
            ClosedTabsView(appState: appState)
        case .settings:
            SettingsView(appState: appState)
        }
    }
}

enum PanelSection: Hashable {
    case arena, tabs, branches, closed, settings
}

// MARK: - Header

struct PanelHeader: View {
    let appState: AppState

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TabX")
                    .font(.headline)
                if let branch = appState.activeBranch ?? appState.gitBranch {
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
            if appState.bundleServerRunning {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.bundleServerURL, forType: .string)
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy bundle URL")
            }
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

// MARK: - Arena View

struct ArenaView: View {
    let appState: AppState
    @State private var historyExpanded: Bool = false
    @State private var selectedRound: ArenaRound? = nil

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                arenaHeader
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        if let round = selectedRound {
                            historyDetailContent(round)
                        } else if appState.contestants.isEmpty {
                            emptyState
                        } else {
                            contestantContent
                        }
                        if !appState.arenaHistory.isEmpty && selectedRound == nil {
                            Divider()
                            arenaHistorySection
                        }
                    }
                }
                .frame(maxHeight: 600)
            }
            if case .judging = appState.arenaPhase {
                JudgingOverlay(contestants: appState.contestants)
            }
        }
    }

    @State private var copiedContext = false

    private var arenaHeader: some View {
        HStack {
            phaseIndicator
            Spacer()
            if appState.lastArenaAt != nil {
                Button {
                    let md = appState.winningContextMarkdown()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(md, forType: .string)
                    copiedContext = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedContext = false }
                } label: {
                    Text(copiedContext ? "Copied!" : "Copy Context")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button {
                    appState.resetArena()
                } label: {
                    Text("Clear")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            fightButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var fightButton: some View {
        Button {
            appState.runManualArena()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "figure.fencing")
                    .font(.caption)
                Text("Fight")
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(.orange)
        .disabled(appState.arenaRunning || appState.tabResults.isEmpty)
    }

    @ViewBuilder
    private var phaseIndicator: some View {
        switch appState.arenaPhase {
        case .idle:
            Label("Waiting for tabs", systemImage: "hourglass")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .analyzing(let completed, let total):
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Agents analyzing \(completed)/\(total)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .judging:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Judge ranking tabs")
                    .font(.caption)
                    .foregroundStyle(.purple)
            }
        case .decided:
            Label("Arena complete", systemImage: "trophy.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.fencing")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No arena battles yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Open tabs in Chrome and TabX will pit them against each other.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }

    private var contestantContent: some View {
        LazyVStack(spacing: 2) {
            ForEach(Array(appState.contestants.enumerated()), id: \.element.id) { rank, contestant in
                ContestantRow(rank: rank + 1, contestant: contestant)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - History detail

    private func historyDetailContent(_ round: ArenaRound) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    selectedRound = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption2)
                        Text("Back")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                Spacer()
                Text(round.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            LazyVStack(spacing: 2) {
                ForEach(Array(round.contestants.enumerated()), id: \.element.id) { rank, c in
                    HistoryContestantRow(rank: rank + 1, contestant: c)
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - History section

    private var arenaHistorySection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    historyExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: historyExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text("History")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("(\(appState.arenaHistory.count))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if historyExpanded {
                Divider()
                historyList
            }
        }
    }

    private var filteredHistory: [ArenaRound] {
        appState.arenaHistory
    }

    private var historyList: some View {
        LazyVStack(spacing: 2) {
            ForEach(filteredHistory) { round in
                Button {
                    selectedRound = round
                } label: {
                    ArenaHistoryRow(round: round)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

}

struct ArenaHistoryRow: View {
    let round: ArenaRound

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(round.timestamp, style: .relative)
                    .font(.caption)
                HStack(spacing: 8) {
                    Text("\(round.tabCount) tabs")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if round.keepCount > 0 {
                        Text("\(round.keepCount) keep")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    if round.closeCount > 0 {
                        Text("\(round.closeCount) close")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    if round.flagCount > 0 {
                        Text("\(round.flagCount) flag")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quinary.opacity(0.5))
        .cornerRadius(4)
        .padding(.horizontal, 6)
    }
}

struct HistoryContestantRow: View {
    let rank: Int
    let contestant: ArenaRound.Contestant

    var body: some View {
        HStack(spacing: 8) {
            Text("#\(rank)")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            RoundedRectangle(cornerRadius: 2)
                .fill(decisionColor)
                .frame(width: 3, height: contestant.summary != nil ? 48 : 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(contestant.title)
                    .font(.callout)
                    .lineLimit(1)
                Text(contestant.url)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let summary = contestant.summary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.0f%%", contestant.score * 100))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(decisionColor)
                Text(contestant.decision.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(decisionColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.quinary.opacity(0.5))
        .cornerRadius(4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture { openURL(contestant.url) }
    }

    private var decisionColor: Color {
        switch contestant.decision {
        case .close: return .red
        case .keep: return .green
        case .flag: return .yellow
        }
    }
}

struct ContestantRow: View {
    let rank: Int
    let contestant: ArenaContestant

    var body: some View {
        HStack(spacing: 8) {
            FighterAvatar(status: contestant.status)

            RoundedRectangle(cornerRadius: 2)
                .fill(statusColor)
                .frame(width: 3, height: isDecided ? 52 : 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(contestant.title)
                    .font(.callout)
                    .lineLimit(1)
                Text(contestant.url)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let summary = contestant.summary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            statusBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.quinary.opacity(0.5))
        .cornerRadius(4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture { openURL(contestant.url) }
        .animation(.easeInOut(duration: 0.3), value: contestant.status)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch contestant.status {
        case .waiting:
            Text("waiting")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .cornerRadius(4)
        case .analyzing:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("analyzing")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        case .analyzed(let score):
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.0f%%", score * 100))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
                Text("scored")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .decided(let decision, let score):
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.0f%%", score * 100))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(decisionColor(decision))
                Text(decision.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(decisionColor(decision))
            }
        }
    }

    private var statusColor: Color {
        switch contestant.status {
        case .waiting: return .gray
        case .analyzing: return .orange
        case .analyzed: return .orange
        case .decided(let d, _): return decisionColor(d)
        }
    }

    private var isDecided: Bool {
        if case .decided = contestant.status { return true }
        return false
    }

    private func decisionColor(_ d: TabDecision) -> Color {
        switch d {
        case .close: return .red
        case .keep: return .green
        case .flag: return .yellow
        }
    }
}

// MARK: - Fighter Avatar

struct FighterAvatar: View {
    let status: TabArenaStatus

    private var face: String {
        switch status {
        case .waiting:                return "( ˘ ᵕ ˘ )"
        case .analyzing:              return "( ᐛ )/ ⚔"
        case .analyzed:               return "( •̀ω•́ )✧"
        case .decided(let d, _):
            switch d {
            case .keep:  return "٩( ᐛ )و ★"
            case .flag:  return "( ˘ ˘ )⚑"
            case .close: return "( x _ x )"
            }
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Text(face)
                    .font(.system(size: 12, design: .monospaced))
                    .fixedSize()
                    .offset(y: bobOffset(t))
                    .rotationEffect(shakeAngle(t))
                    .scaleEffect(pulseScale(t))
                    .opacity(fadeOpacity(t))

                if case .analyzing = status {
                    battleParticles(t)
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: status)
    }

    private func bobOffset(_ t: Double) -> CGFloat {
        switch status {
        case .waiting:
            return CGFloat(sin(t * 2) * 2)
        case .analyzed:
            return CGFloat(sin(t * 4) * 3)
        default:
            return 0
        }
    }

    private func shakeAngle(_ t: Double) -> Angle {
        if case .analyzing = status {
            return .degrees(sin(t * 16) * 6)
        }
        return .zero
    }

    private func pulseScale(_ t: Double) -> CGFloat {
        switch status {
        case .decided(let d, _):
            let pulse = CGFloat(sin(t * 3) * 0.06)
            switch d {
            case .keep:  return 1.0 + pulse
            case .flag:  return 1.0 + pulse * 0.5
            case .close: return max(0.7, 1.0 - CGFloat(sin(t * 0.5).magnitude) * 0.3)
            }
        default:
            return 1.0
        }
    }

    private func fadeOpacity(_ t: Double) -> Double {
        if case .decided(.close, _) = status {
            return 0.5
        }
        return 1.0
    }

    @ViewBuilder
    private func battleParticles(_ t: Double) -> some View {
        let symbols = ["✦", "⚡", "*", "✧"]
        ForEach(0..<4, id: \.self) { i in
            let angle = Double(i) * .pi / 2 + t * 3
            let radius: CGFloat = 14
            Text(symbols[i])
                .font(.system(size: 8))
                .offset(
                    x: CGFloat(cos(angle)) * radius,
                    y: CGFloat(sin(angle)) * radius
                )
                .opacity(0.4 + sin(t * 6 + Double(i)) * 0.4)
        }
    }
}

// MARK: - Judging Overlay

struct JudgingOverlay: View {
    let contestants: [ArenaContestant]
    @State private var pairIndex: Int = 0

    private var pairs: [(ArenaContestant, ArenaContestant)] {
        guard contestants.count >= 2 else { return [] }
        var result: [(ArenaContestant, ArenaContestant)] = []
        let shuffled = contestants.shuffled()
        var i = 0
        while i + 1 < shuffled.count {
            result.append((shuffled[i], shuffled[i + 1]))
            i += 2
        }
        if result.isEmpty {
            result.append((contestants[0], contestants[1]))
        }
        return result
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)

            VStack(spacing: 12) {
                Text("⚔ JUDGE RANKING ⚔")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.purple)

                if !pairs.isEmpty {
                    let pair = pairs[pairIndex % max(pairs.count, 1)]
                    HStack(spacing: 16) {
                        VStack(spacing: 4) {
                            Text("( ᐛ )/ ⚔")
                                .font(.system(size: 16, design: .monospaced))
                            Text(pair.0.title)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(maxWidth: 100)
                        }
                        Text("VS")
                            .font(.caption)
                            .fontWeight(.black)
                            .foregroundStyle(.yellow)
                        VStack(spacing: 4) {
                            Text("⚔ ( ᐛ )")
                                .font(.system(size: 16, design: .monospaced))
                            Text(pair.1.title)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(maxWidth: 100)
                        }
                    }
                    .foregroundStyle(.white)
                    .transition(.opacity)
                    .id(pairIndex)
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
        .onAppear { startCycling() }
    }

    private func startCycling() {
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                pairIndex += 1
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
            .frame(maxHeight: 400)
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
                .frame(width: 3, height: tab.summary != nil ? 52 : 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .font(.callout)
                    .lineLimit(1)
                Text(tab.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let summary = tab.summary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
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
        .contentShape(Rectangle())
        .onTapGesture { openURL(tab.url) }
    }

    private var decisionColor: Color {
        switch tab.decision {
        case .close: return .red
        case .keep:  return .green
        case .flag:  return .yellow
        }
    }
}

// MARK: - Branches

struct BranchesView: View {
    let appState: AppState
    @State private var selectedEntry: SessionIndexEntry? = nil
    @State private var drillDownTabs: [TabDisplayItem] = []

    var body: some View {
        if let entry = selectedEntry {
            branchDetail(entry)
        } else if appState.sessionIndex.isEmpty {
            emptyState
        } else {
            branchList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No branch sessions yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Switch branches while TabX is running to see sessions here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }

    private var branchList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(appState.sessionIndex, id: \.workspaceKey.rawValue) { entry in
                    let isActive = entry.workspaceKey.rawValue == appState.activeWorkspaceKey
                    BranchRow(
                        entry: entry,
                        isActive: isActive,
                        liveTabCount: isActive ? appState.tabResults.count : nil
                    ) {
                        if isActive {
                            drillDownTabs = appState.tabResults
                        } else {
                            drillDownTabs = appState.loadSessionTabs(for: entry.workspaceKey)
                        }
                        selectedEntry = entry
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 400)
    }

    private func branchDetail(_ entry: SessionIndexEntry) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    selectedEntry = nil
                    drillDownTabs = []
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption2)
                        Text("Back")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                Spacer()
                Text(entry.branch)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            if drillDownTabs.isEmpty {
                VStack(spacing: 8) {
                    Text("No tabs saved for this branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(drillDownTabs) { tab in
                            TabRowView(tab: tab)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 400)
            }
        }
    }
}

struct BranchRow: View {
    let entry: SessionIndexEntry
    let isActive: Bool
    var liveTabCount: Int? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                if isActive {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(.quaternary)
                        .frame(width: 8, height: 8)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.branch)
                        .font(.callout)
                        .fontWeight(isActive ? .semibold : .regular)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text("\(liveTabCount ?? entry.tabCount) tabs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text((entry.repoPath as NSString).lastPathComponent)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.capturedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quinary.opacity(0.5))
            .cornerRadius(4)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
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
            .frame(maxHeight: 400)
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
                bundleServerSection
                Divider()
                sensitivitySection
                Divider()
                safelistSection
                Divider()
                resetSection
            }
            .padding(12)
        }
        .frame(maxHeight: 300)
    }

    private var bundleServerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bundle Server")
                .font(.callout)
                .fontWeight(.medium)
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.bundleServerRunning ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(appState.bundleServerRunning ? "Running" : "Stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if appState.bundleServerRunning {
                serverURLRow(label: "JSON", url: "http://localhost:9876/bundle")
                serverURLRow(label: "Markdown", url: "http://localhost:9876/bundle.md")
            }
        }
    }

    private func serverURLRow(label: String, url: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(url)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
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

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Data")
                .font(.callout)
                .fontWeight(.medium)
            Text("Clear all cached tabs, sessions, and arena history")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                appState.resetAll()
            } label: {
                Text("Reset All Data")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        }
    }

    private func commitDomain() {
        let domain = newDomain.trimmingCharacters(in: .whitespaces)
        guard !domain.isEmpty else { return }
        appState.addToSafelist(domain)
        newDomain = ""
    }
}

// MARK: - Helpers

private func openURL(_ urlString: String) {
    guard let url = URL(string: urlString), !urlString.isEmpty else { return }
    NSWorkspace.shared.open(url)
}
