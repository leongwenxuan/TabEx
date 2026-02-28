import Foundation

/// Compacts a `BundleManagerState` before persisting a session.
///
/// - Normalizes URLs and merges duplicate page records.
/// - Prunes records with < 5s time spent.
/// - Caps at 100 records, sorted by time spent descending.
public enum Compactor {

    private static let minimumTimeSpent: Double = 5.0
    private static let maxRecords = 100

    public static func compact(_ state: BundleManagerState) -> BundleManagerState {
        // 1. Normalize URLs and group records.
        var merged: [String: PageRecord] = [:]
        for (_, record) in state.pageRecords {
            let normalizedURL = URLNormalizer.normalize(record.url)
            if let existing = merged[normalizedURL] {
                // Merge: accumulate time, max scroll, union highlights, keep latest visit.
                merged[normalizedURL] = PageRecord(
                    url: normalizedURL,
                    title: record.title.isEmpty ? existing.title : record.title,
                    contentDigest: record.contentDigest ?? existing.contentDigest,
                    highlights: existing.highlights + record.highlights,
                    timeSpentSeconds: existing.timeSpentSeconds + record.timeSpentSeconds,
                    scrollDepth: max(existing.scrollDepth, record.scrollDepth),
                    visitedAt: max(existing.visitedAt, record.visitedAt)
                )
            } else {
                merged[normalizedURL] = PageRecord(
                    url: normalizedURL,
                    title: record.title,
                    contentDigest: record.contentDigest,
                    highlights: record.highlights,
                    timeSpentSeconds: record.timeSpentSeconds,
                    scrollDepth: record.scrollDepth,
                    visitedAt: record.visitedAt
                )
            }
        }

        // 2. Prune records with insufficient engagement.
        var records = merged.values.filter { $0.timeSpentSeconds >= minimumTimeSpent }

        // 3. Sort by time spent descending and cap.
        records.sort { $0.timeSpentSeconds > $1.timeSpentSeconds }
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }

        // 4. Rebuild the dictionary keyed by normalized URL.
        let compactedRecords = Dictionary(uniqueKeysWithValues: records.map { ($0.url, $0) })

        return BundleManagerState(
            pageRecords: compactedRecords,
            latestResults: state.latestResults,
            urlForTabId: state.urlForTabId,
            titleForTabId: state.titleForTabId
        )
    }
}

private func max(_ a: Date, _ b: Date) -> Date {
    a >= b ? a : b
}
