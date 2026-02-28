import Foundation
import TabXHostLib

// MARK: - Entry point

let args = Array(CommandLine.arguments.dropFirst())  // strip binary path

// Any known CLI flag → run in CLI mode, then exit.
let cliFlags: Set<String> = ["--bundle", "--bundle-md", "--status", "--config",
                              "--config-set", "--version", "--help", "-h", "-v"]

if let first = args.first, cliFlags.contains(first) || first.hasPrefix("--config-set") {
    let handler = CLIHandler()
    let code = handler.run(args: args)
    exit(code)
}

// No CLI flag → enter native messaging loop.
let io = NativeMessagingIO()
let router = MessageRouter()

while true {
    guard let message = io.readMessage() else {
        // EOF or unreadable message: exit cleanly.
        break
    }
    let response = router.handle(message)
    do {
        try io.writeMessage(response)
    } catch {
        // Best-effort error response; if this also fails, exit.
        let errMsg = OutgoingMessage(type: .error, error: error.localizedDescription)
        try? io.writeMessage(errMsg)
    }
}
