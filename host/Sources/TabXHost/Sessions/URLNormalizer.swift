import Foundation

/// Normalizes URLs for deduplication: strips fragments, sorts query params, strips trailing slash.
public enum URLNormalizer {

    public static func normalize(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else {
            return urlString
        }

        // Strip fragment.
        components.fragment = nil

        // Sort query parameters by name for stable comparison.
        if let items = components.queryItems, !items.isEmpty {
            components.queryItems = items.sorted { $0.name < $1.name }
        }

        guard var result = components.string else {
            return urlString
        }

        // Strip trailing slash (unless path is just "/").
        if result.hasSuffix("/"), result.count > 1 {
            let pathOnly = components.path
            if pathOnly != "/" {
                result = String(result.dropLast())
            }
        }

        return result
    }
}
