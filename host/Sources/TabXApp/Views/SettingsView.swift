import SwiftUI
import TabXHostLib

struct SettingsView: View {
    @Environment(AppState.self) var appState
    @State private var newDomain = ""

    var body: some View {
        DisclosureGroup("Settings") {
            VStack(alignment: .leading, spacing: 12) {
                sensitivitySection
                Divider()
                safelistSection
            }
            .padding(.top, 8)
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
    }

    // MARK: - Sensitivity

    private var sensitivitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sensitivity")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { appState.scoringConfig.sensitivity },
                    set: { appState.updateSensitivity($0) }
                ),
                in: 0...1,
                step: 0.05
            )
            .tint(.accentColor)

            HStack {
                Text("Permissive")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Aggressive")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Safelist

    private var safelistSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Safelist")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if appState.scoringConfig.safelist.isEmpty {
                Text("No safelisted domains")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.scoringConfig.safelist, id: \.self) { domain in
                    HStack {
                        Text(domain)
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Spacer()
                        Button {
                            appState.removeFromSafelist(domain)
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("Add domain...", text: $newDomain)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitDomain() }

                Button("Add") {
                    submitDomain()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func submitDomain() {
        let domain = newDomain.trimmingCharacters(in: .whitespaces)
        guard !domain.isEmpty else { return }
        appState.addToSafelist(domain)
        newDomain = ""
    }
}

#Preview {
    let state = AppState()
    return SettingsView()
        .environment(state)
        .frame(width: 360)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
}
