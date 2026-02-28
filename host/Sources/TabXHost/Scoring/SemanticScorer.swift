import Foundation
@preconcurrency import NaturalLanguage

/// Computes semantic similarity between tab content and a set of context tokens.
///
/// Primary: NLEmbedding cosine similarity (requires macOS 12+, falls back automatically).
/// Fallback: Jaccard similarity on token sets when embeddings are unavailable.
public struct SemanticScorer: @unchecked Sendable {
    private let embedding: NLEmbedding?

    public init() {
        self.embedding = NLEmbedding.wordEmbedding(for: .english)
    }

    /// Score is in [0.0, 1.0]. Returns `defaultScore` when no signal is available.
    public func score(
        contextTokens: [String],
        tabTokens: [String],
        defaultScore: Double = 0.3
    ) -> Double {
        guard !contextTokens.isEmpty, !tabTokens.isEmpty else { return defaultScore }

        if let embedding {
            return embeddingScore(
                contextTokens: contextTokens,
                tabTokens: tabTokens,
                embedding: embedding,
                defaultScore: defaultScore
            )
        }
        return jaccardScore(contextTokens: Set(contextTokens), tabTokens: Set(tabTokens))
    }

    // MARK: - Private

    private func embeddingScore(
        contextTokens: [String],
        tabTokens: [String],
        embedding: NLEmbedding,
        defaultScore: Double
    ) -> Double {
        let ctxSample = Array(contextTokens.prefix(5))
        let tabSample = Array(tabTokens.prefix(10))

        var total = 0.0
        var count = 0
        for ct in ctxSample {
            for tt in tabSample {
                let dist = embedding.distance(between: ct, and: tt, distanceType: .cosine)
                total += 1.0 - Double(dist)
                count += 1
            }
        }
        guard count > 0 else { return defaultScore }
        return max(0.0, min(1.0, total / Double(count)))
    }

    private func jaccardScore(contextTokens: Set<String>, tabTokens: Set<String>) -> Double {
        let intersection = contextTokens.intersection(tabTokens).count
        let union = contextTokens.union(tabTokens).count
        guard union > 0 else { return 0.0 }
        return Double(intersection) / Double(union)
    }
}
