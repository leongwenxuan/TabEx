import Foundation
import Network
import TabXHostLib

/// Lightweight localhost HTTP server that serves the context bundle.
/// Uses `NWListener` from the Network framework (no third-party deps).
final class BundleServer {
    private var listener: NWListener?
    private let port: UInt16 = 9876
    private let queue = DispatchQueue(label: "com.tabx.bundleserver")

    var onStatusChange: ((Bool) -> Void)?

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            l.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.onStatusChange?(true)
                case .failed, .cancelled:
                    self?.onStatusChange?(false)
                default:
                    break
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                self?.handleConnection(conn)
            }
            l.start(queue: queue)
            listener = l
        } catch {
            fputs("[TabX] BundleServer failed to start: \(error)\n", stderr)
            onStatusChange?(false)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        onStatusChange?(false)
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }
            let request = String(decoding: data, as: UTF8.self)
            let response = self.route(request)
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    // MARK: - Routing

    private func route(_ raw: String) -> String {
        let path = parsePath(raw)

        switch path {
        case "/bundle", "/bundle.json":
            return serveBundleJSON()
        case "/bundle.md":
            return serveBundleMarkdown()
        case "/health":
            return httpResponse(status: "200 OK", contentType: "application/json", body: "{\"status\":\"ok\"}")
        default:
            return httpResponse(status: "404 Not Found", contentType: "application/json", body: "{\"error\":\"not found\"}")
        }
    }

    private func parsePath(_ raw: String) -> String {
        // First line: "GET /path HTTP/1.1"
        guard let firstLine = raw.split(separator: "\r\n", maxSplits: 1).first else { return "/" }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        // Strip query string
        let full = String(parts[1])
        if let qIdx = full.firstIndex(of: "?") {
            return String(full[full.startIndex..<qIdx])
        }
        return full
    }

    // MARK: - Route handlers

    private func serveBundleJSON() -> String {
        guard let bundle = BundleStore.loadBundle() else {
            return httpResponse(status: "404 Not Found", contentType: "application/json",
                                body: "{\"error\":\"no bundle available\"}")
        }
        do {
            let json = try BundleFormatter.json(bundle)
            return httpResponse(status: "200 OK", contentType: "application/json", body: json)
        } catch {
            return httpResponse(status: "500 Internal Server Error", contentType: "application/json",
                                body: "{\"error\":\"encoding failed\"}")
        }
    }

    private func serveBundleMarkdown() -> String {
        guard let bundle = BundleStore.loadBundle() else {
            return httpResponse(status: "404 Not Found", contentType: "text/plain",
                                body: "No bundle available.")
        }
        let md = BundleFormatter.markdown(bundle)
        return httpResponse(status: "200 OK", contentType: "text/markdown; charset=utf-8", body: md)
    }

    // MARK: - HTTP helpers

    private func httpResponse(status: String, contentType: String, body: String) -> String {
        let bodyData = body.utf8
        return """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        \r
        \(body)
        """
    }
}
