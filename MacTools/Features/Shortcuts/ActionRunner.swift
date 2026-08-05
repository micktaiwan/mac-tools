import Foundation

/// Runs a shortcut's action and reports what happened, so a failing script is
/// visible in the UI instead of being a key press that does nothing.
enum ActionRunner {
    static func run(_ action: UserShortcut.Action) async -> ActionResult {
        switch action.type {
        case .shell:
            return await runShell(action.command)
        }
    }

    private static func runShell(_ command: String) async -> ActionResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                // Login shell so the command sees the same PATH as a terminal.
                process.arguments = ["-lc", command]

                let output = Pipe()
                process.standardOutput = output
                process.standardError = output

                do {
                    try process.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: ActionResult(
                        date: Date(),
                        exitCode: process.terminationStatus,
                        output: String(data: data, encoding: .utf8) ?? ""
                    ))
                } catch {
                    continuation.resume(returning: ActionResult(
                        date: Date(),
                        exitCode: -1,
                        output: error.localizedDescription
                    ))
                }
            }
        }
    }
}
