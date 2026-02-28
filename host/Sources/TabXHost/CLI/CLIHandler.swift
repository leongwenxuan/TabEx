import Foundation

/// Handles command-line invocations of the tabx-host binary.
///
/// Supported commands:
///   --bundle     Generate and print the context bundle (JSON by default, Markdown with --markdown)
///   --status     Print a one-line status summary
///   --config     Print the current configuration as JSON
///   --set-key    Save an OpenAI API key to config
///   --version    Print the version string
///   --help       Print usage information
public struct CLIHandler {

    private var configManager: ConfigManager

    public init(configManager: ConfigManager = ConfigManager()) {
        self.configManager = configManager
    }

    /// Parses `CommandLine.arguments` (excluding the binary name) and runs the matching command.
    /// Returns the exit code.
    @discardableResult
    public mutating func run(arguments: [String]) -> Int32 {
        if arguments.isEmpty {
            return 0  // caller should enter native-messaging loop
        }

        switch arguments[0] {
        case "--bundle":
            return handleBundle(arguments: Array(arguments.dropFirst()))
        case "--status":
            return handleStatus()
        case "--config":
            return handleConfig()
        case "--set-key":
            return handleSetKey(arguments: Array(arguments.dropFirst()))
        case "--version":
            return handleVersion()
        case "--help", "-h":
            return handleHelp()
        default:
            fputs("Unknown option: \(arguments[0])\n", stderr)
            fputs("Run with --help for usage.\n", stderr)
            return 1
        }
    }

    // MARK: - Command handlers

    private func handleBundle(arguments: [String]) -> Int32 {
        let useMarkdown = arguments.contains("--markdown")

        if let bundle = BundleStore.loadBundle() {
            if useMarkdown {
                print(BundleFormatter.markdown(bundle))
            } else {
                if let json = try? BundleFormatter.json(bundle) {
                    print(json)
                } else {
                    fputs("Error: failed to encode bundle as JSON.\n", stderr)
                    return 1
                }
            }
            return 0
        }

        // No bundle on disk — generate from current git context.
        let git = GitContext.detect()
        let bundle = ContextBundle(
            generatedAt: Date(),
            gitBranch: git.branch,
            gitRepoPath: git.repoPath,
            pagesRead: [],
            survivingTabs: [],
            openFiles: git.recentFiles,
            taskDescription: git.branch.map { $0.replacingOccurrences(of: "/", with: ": ").replacingOccurrences(of: "-", with: " ") }
        )
        if useMarkdown {
            print(BundleFormatter.markdown(bundle))
        } else {
            if let json = try? BundleFormatter.json(bundle) {
                print(json)
            } else {
                fputs("Error: failed to encode bundle as JSON.\n", stderr)
                return 1
            }
        }
        return 0
    }

    private func handleStatus() -> Int32 {
        let git = GitContext.detect()
        let bundleExists = FileManager.default.fileExists(atPath: BundleStore.bundleURL.path)
        let branch = git.branch ?? "(detached)"
        let repo = git.repoPath ?? "(none)"
        let bundleStatus = bundleExists ? "available" : "none"
        let apiKeyStatus = configManager.config.openai.hasAPIKey ? "configured" : "not configured"
        let agentModel = configManager.config.openai.agentModel
        let judgeModel = configManager.config.openai.judgeModel
        print("tabx-host \(configManager.config.version)")
        print("Mode:    agent")
        print("Branch:  \(branch)")
        print("Repo:    \(repo)")
        print("Bundle:  \(bundleStatus)")
        print("API Key: \(apiKeyStatus)")
        print("Models:  agent=\(agentModel), judge=\(judgeModel)")
        print("Config:  \(ConfigManager.configURL.path)")
        return 0
    }

    private mutating func handleSetKey(arguments: [String]) -> Int32 {
        guard let key = arguments.first, !key.isEmpty else {
            fputs("Usage: tabx-host --set-key <openai-api-key>\n", stderr)
            return 1
        }
        configManager.config.openai.apiKey = key
        do {
            try configManager.save()
            print("API key saved to \(ConfigManager.configURL.path)")
            return 0
        } catch {
            fputs("Error saving config: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private func handleConfig() -> Int32 {
        print(configManager.prettyJSON())
        return 0
    }

    private func handleVersion() -> Int32 {
        print("tabx-host \(configManager.config.version)")
        return 0
    }

    private func handleHelp() -> Int32 {
        let usage = """
        Usage: tabx-host [OPTION]

        When called with no options, enters Chrome native messaging mode (reads
        length-prefixed JSON from stdin and writes to stdout).

        Options:
          --bundle [--markdown]  Print the latest context bundle (JSON or Markdown)
          --status               Print current status (branch, repo, agent mode, API key)
          --config               Print the current configuration as JSON
          --set-key <key>        Save an OpenAI API key to ~/.tabx/config.json
          --version              Print version information
          --help                 Show this help message
        """
        print(usage)
        return 0
    }
}
