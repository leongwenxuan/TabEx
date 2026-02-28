import Foundation

/// Reads git state from the working directory so the scoring engine can
/// compare tab content against the current branch / touched files.
public struct GitContext: Sendable {
    public let branch: String?
    public let repoPath: String?
    /// Files modified but not yet committed (union of staged and unstaged changes).
    public let recentFiles: [String]

    public init(branch: String?, repoPath: String?, recentFiles: [String]) {
        self.branch = branch
        self.repoPath = repoPath
        self.recentFiles = recentFiles
    }

    /// Detects git context by walking up from `directory`.
    public static func detect(from directory: String = FileManager.default.currentDirectoryPath) -> GitContext {
        guard let root = findGitRoot(from: directory) else {
            return GitContext(branch: nil, repoPath: nil, recentFiles: [])
        }
        let branch = readBranch(repoPath: root)
        let recent = readRecentFiles(repoPath: root)
        return GitContext(branch: branch, repoPath: root, recentFiles: recent)
    }

    // MARK: - Private helpers

    private static func findGitRoot(from directory: String) -> String? {
        var current = (directory as NSString).standardizingPath
        let fm = FileManager.default
        for _ in 0..<20 {
            let gitDir = (current as NSString).appendingPathComponent(".git")
            if fm.fileExists(atPath: gitDir) { return current }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
        }
        return nil
    }

    private static func readBranch(repoPath: String) -> String? {
        let headPath = (repoPath as NSString).appendingPathComponent(".git/HEAD")
        guard let content = try? String(contentsOfFile: headPath, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref: refs/heads/") {
            return String(trimmed.dropFirst("ref: refs/heads/".count))
        }
        return trimmed.count >= 7 ? String(trimmed.prefix(7)) : trimmed
    }

    private static func readRecentFiles(repoPath: String) -> [String] {
        let unstaged = git(repoPath, args: ["diff", "--name-only"])
        let staged   = git(repoPath, args: ["diff", "--name-only", "--cached"])
        return (unstaged + staged)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .removingDuplicates()
    }

    @discardableResult
    private static func git(_ repoPath: String, args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["git", "-C", repoPath] + args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
