import Foundation
import TabXHostLib

// Drop the binary name from arguments.
let args = Array(CommandLine.arguments.dropFirst())

let cli = CLIHandler()
let exitCode = cli.run(arguments: args)

// If arguments were provided, the CLI handled the command — exit now.
if !args.isEmpty {
    exit(exitCode)
}

// No CLI arguments → enter native messaging loop.
let io = NativeMessagingIO()
let router = MessageRouter()

while true {
    guard let message = io.readMessage() else {
        // EOF or malformed length prefix — Chrome closed the pipe.
        break
    }

    let reply = router.handle(message)
    do {
        try io.writeMessage(reply)
    } catch {
        // Write error is unrecoverable — exit cleanly.
        fputs("tabx-host: write error: \(error)\n", stderr)
        break
    }
}
