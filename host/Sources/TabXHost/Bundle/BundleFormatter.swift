import Foundation

/// Serialises a `ContextBundle` to JSON or Markdown.
public struct BundleFormatter {
    private let encoder: JSONEncoder

    public init() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc
    }

    // MARK: - JSON

    public func json(_ bundle: ContextBundle) throws -> String {
        let data = try encoder.encode(bundle)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Markdown

    public func markdown(_ bundle: ContextBundle) -> String {
        var lines: [String] = []

        lines.append("# TabX Context Bundle")
        lines.append("")
        lines.append("Generated: \(iso8601(bundle.generatedAt))")
        if let branch = bundle.gitBranch {
            lines.append("Branch: `\(branch)`")
        }
        if let repo = bundle.gitRepoPath {
            lines.append("Repo: `\(repo)`")
        }
        if let task = bundle.taskDescription {
            lines.append("Task: \(task)")
        }
        lines.append("")

        if !bundle.survivingTabs.isEmpty {
            lines.append("## Surviving Tabs (\(bundle.survivingTabs.count))")
            lines.append("")
            for tab in bundle.survivingTabs.sorted(by: { $0.score > $1.score }) {
                let icon = tab.decision == .keep ? "✓" : "~"
                lines.append("- \(icon) [\(tab.title)](\(tab.url)) — score \(String(format: "%.2f", tab.score)) [\(tab.decision.rawValue)]")
            }
            lines.append("")
        }

        if !bundle.pagesRead.isEmpty {
            lines.append("## Pages Read (\(bundle.pagesRead.count))")
            lines.append("")
            for page in bundle.pagesRead.prefix(20) {
                lines.append("- [\(page.title)](\(page.url))")
                if !page.highlights.isEmpty {
                    for h in page.highlights.prefix(2) {
                        lines.append("  > \(h.prefix(120))")
                    }
                }
            }
            lines.append("")
        }

        if !bundle.openFiles.isEmpty {
            lines.append("## Open Files")
            lines.append("")
            for file in bundle.openFiles {
                lines.append("- `\(file)`")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func iso8601(_ date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        return fmt.string(from: date)
    }
}
