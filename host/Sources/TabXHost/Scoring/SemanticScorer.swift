import Foundation
@preconcurrency import NaturalLanguage

/// Computes semantic similarity between a tab and a set of context tokens
/// using NLEmbedding (cosine distance), with a Jaccard-overlap fallback
/// when the embedding model is unavailable.
public struct SemanticScorer: Sendable {
    private let embedder: NLEmbedding?

    public init() {
        self.embedder = NLEmbedding.wordEmbedding(for: .english)
    }

    /// Returns a score in [0.0, 1.0] measuring semantic similarity between
    /// `contextTokens` (e.g. branch name tokens) and `tabTokens` (tab content tokens).
    public func score(contextTokens: [String], tabTokens: [String]) -> Double {
        guard !contextTokens.isEmpty, !tabTokens.isEmpty else { return 0.3 }
        if let embedder {
            return embeddingScore(embedder: embedder, context: contextTokens, tab: tabTokens)
        }
        return jaccardScore(context: contextTokens, tab: tabTokens)
    }

    // MARK: - Private

    private func embeddingScore(embedder: NLEmbedding, context: [String], tab: [String]) -> Double {
        let ctxTokens = Array(context.prefix(5))
        let tabTokens = Array(tab.prefix(10))
        var total = 0.0
        var count = 0
        for ct in ctxTokens {
            for tt in tabTokens {
                let dist = embedder.distance(between: ct, and: tt, distanceType: .cosine)
                total += 1.0 - Double(dist)
                count += 1
            }
        }
        guard count > 0 else { return jaccardScore(context: context, tab: tab) }
        return max(0.0, min(1.0, total / Double(count)))
    }

    /// Jaccard similarity: |intersection| / |union|
    private func jaccardScore(context: [String], tab: [String]) -> Double {
        let setA = Set(context)
        let setB = Set(tab)
        let intersect = setA.intersection(setB).count
        let union = setA.union(setB).count
        guard union > 0 else { return 0.0 }
        return Double(intersect) / Double(union)
    }
}
