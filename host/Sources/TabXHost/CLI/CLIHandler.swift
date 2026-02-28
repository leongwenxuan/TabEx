import Foundation

/// Handles command-line invocations of the tabx-host binary.
///
/// Supported flags:
///   --bundle          Print the latest saved context bundle (JSON)
///   --bundle-md       Print the latest saved context bundle (Markdown)
///   --status          Print host status and last-scored info
///   --config          Print current AppConfig as JSON
///   --config-set KEY=VALUE  Update a flat config key
///   --version         Print version string
///   --help            Print usage
public struct CLIHandler {
    public static let version = "1.0.0"

    private let configManager: ConfigManager
    private let bundleStore: BundleStore
    private let formatter: BundleFormatter

    public init(
        configManager: ConfigManager = .shared,
        bundleStore: BundleStore = .shared
    ) {
        self.configManager = configManager
        self.bundleStore = bundleStore
        self.formatter = BundleFormatter()
    }

    // MARK: - Entry point

    /// Returns exit code (0 = success, 1 = error).
    @discardableResult
    public func run(args: [String]) -> Int32 {
        guard !args.isEmpty else {
            printHelp()
            return 0
        }

        switch args[0] {
        case "--help", "-h":
            printHelp()
            return 0

        case "--version", "-v":
            print("tabx-host \(Self.version)")
            return 0

        case "--bundle":
            return printBundle(format: .json)

        case "--bundle-md":
            return printBundle(format: .markdown)

        case "--status":
            return printStatus()

        case "--config":
            return printConfig()

        case "--config-set":
            guard args.count >= 2 else {
                fputs("Error: --config-set requires KEY=VALUE\n", stderr)
                return 1
            }
            return setConfig(pair: args[1])

        default:
            fputs("Unknown flag: \(args[0])\n", stderr)
            printHelp()
            return 1
        }
    }

    // MARK: - Command implementations

    private enum OutputFormat { case json, markdown }

    private func printBundle(format: OutputFormat) -> Int32 {
        guard let bundle = bundleStore.loadLatestBundle() else {
            fputs("No bundle found. Run the extension to generate one.\n", stderr)
            return 1
        }
        do {
            let output: String
            switch format {
            case .json:     output = try formatter.json(bundle)
            case .markdown: output = formatter.markdown(bundle)
            }
            print(output)
            return 0
        } catch {
            fputs("Error formatting bundle: \(error)\n", stderr)
            return 1
        }
    }

    private func printStatus() -> Int32 {
        let state = bundleStore.loadState()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let obj: [String: String] = [
            "version":      Self.version,
            "lastScoredAt": state.lastScoredAt.map { ISO8601DateFormatter().string(from: $0) } ?? "never",
            "tabCount":     "\(state.tabCount)",
            "closedCount":  "\(state.closedCount)",
            "bundleCount":  "\(bundleStore.allBundleURLs().count)",
        ]
        if let data = try? enc.encode(obj),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
        return 0
    }

    private func printConfig() -> Int32 {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(configManager.config),
              let str = String(data: data, encoding: .utf8) else {
            fputs("Error encoding config\n", stderr)
            return 1
        }
        print(str)
        return 0
    }

    private func setConfig(pair: String) -> Int32 {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            fputs("Invalid format. Use KEY=VALUE\n", stderr)
            return 1
        }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        let value = parts[1].trimmingCharacters(in: .whitespaces)

        var scoring = configManager.scoringConfig
        switch key {
        case "sensitivity":
            guard let d = Double(value) else { return configError(key: key, value: value) }
            scoring.sensitivity = d
        case "closeThreshold":
            guard let d = Double(value) else { return configError(key: key, value: value) }
            scoring.closeThreshold = d
        case "keepThreshold":
            guard let d = Double(value) else { return configError(key: key, value: value) }
            scoring.keepThreshold = d
        case "stalenessThresholdSeconds":
            guard let d = Double(value) else { return configError(key: key, value: value) }
            scoring.stalenessThresholdSeconds = d
        case "retentionSeconds":
            guard let d = Double(value) else { return configError(key: key, value: value) }
            scoring.retentionSeconds = d
        default:
            fputs("Unknown config key: \(key)\n", stderr)
            return 1
        }
        do {
            try configManager.updateScoring(scoring)
            print("Updated \(key) = \(value)")
            return 0
        } catch {
            fputs("Error saving config: \(error)\n", stderr)
            return 1
        }
    }

    private func configError(key: String, value: String) -> Int32 {
        fputs("Invalid value '\(value)' for key '\(key)'\n", stderr)
        return 1
    }

    private func printHelp() {
        print("""
        tabx-host \(Self.version)

        USAGE:
          tabx-host [FLAG]

        FLAGS:
          --bundle          Print latest context bundle (JSON)
          --bundle-md       Print latest context bundle (Markdown)
          --status          Print host status
          --config          Print current configuration
          --config-set K=V  Set a config value (e.g. sensitivity=0.7)
          --version         Print version
          --help            Show this help

        Without flags, enters native messaging mode (used by the Chrome extension).
        """)
    }
}
