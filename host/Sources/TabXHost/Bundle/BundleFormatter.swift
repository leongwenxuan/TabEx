import Foundation

/// Serialises a `ContextBundle` to different output formats.
public struct BundleFormatter {

    // MARK: - JSON

    /// Returns a pretty-printed JSON string for the given bundle.
    public static func json(_ bundle: ContextBundle) throws -> String {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(bundle)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Markdown

    /// Returns a Markdown summary suitable for pasting into a coding-agent prompt.
    public static func markdown(_ bundle: ContextBundle) -> String {
        var lines: [String] = []

        lines.append("# TabX Context Bundle")
        lines.append("")
        lines.append("**Generated:** \(iso8601(bundle.generatedAt))")
        if let branch = bundle.gitBranch {
            lines.append("**Branch:** `\(branch)`")
        }
        if let repo = bundle.gitRepoPath {
            lines.append("**Repo:** `\(repo)`")
        }
        if let task = bundle.taskDescription {
            lines.append("**Task:** \(task)")
        }
        lines.append("")

        if !bundle.openFiles.isEmpty {
            lines.append("## Open / Modified Files")
            lines.append("")
            for f in bundle.openFiles {
                lines.append("- `\(f)`")
            }
            lines.append("")
        }

        if !bundle.survivingTabs.isEmpty {
            lines.append("## Surviving Tabs")
            lines.append("")
            for tab in bundle.survivingTabs {
                let badge = tab.decision == .keep ? "✓" : "⚑"
                lines.append("- \(badge) [\(tab.title)](\(tab.url)) — score: \(String(format: "%.2f", tab.score))")
            }
            lines.append("")
        }

        if !bundle.pagesRead.isEmpty {
            lines.append("## Pages Read")
            lines.append("")
            for page in bundle.pagesRead.prefix(20) {
                lines.append("### \(page.title)")
                lines.append("- **URL:** \(page.url)")
                lines.append("- **Time spent:** \(Int(page.timeSpentSeconds))s")
                lines.append("- **Scroll depth:** \(Int(page.scrollDepth * 100))%")
                if !page.highlights.isEmpty {
                    lines.append("- **Highlights:**")
                    for h in page.highlights.prefix(5) {
                        lines.append("  - > \(h.prefix(200))")
                    }
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private static func iso8601(_ date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.string(from: date)
    }
}
