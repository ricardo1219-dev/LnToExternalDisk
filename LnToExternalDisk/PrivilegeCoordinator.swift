import Foundation

enum PrivilegedExecutionError: LocalizedError {
    case commandFailed(String)
    case missingPassword
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "命令执行失败: \(message)"
        case .missingPassword:
            return "缺少管理员密码，无法执行 sudo 命令"
        case .authenticationFailed:
            return "管理员密码错误，请重新输入"
        }
    }
}

final class PrivilegeCoordinator {
    func run(
        script: String,
        privileged: Bool,
        preferredUser: String? = nil,
        password: String? = nil
    ) throws -> String {
        if privileged {
            do {
                return try runWithSudo(script: script, runAsUser: preferredUser, password: password)
            } catch {
                // If user impersonation fails, fallback to plain admin execution.
                if preferredUser != nil {
                    return try runWithSudo(script: script, runAsUser: nil, password: password)
                }
                throw error
            }
        }
        return try runWithoutAdministrator(script: script)
    }

    private func runWithoutAdministrator(script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", script]
        return try execute(process: process, stdin: nil)
    }

    private func runWithSudo(script: String, runAsUser: String?, password: String?) throws -> String {
        guard let password, !password.isEmpty else {
            throw PrivilegedExecutionError.missingPassword
        }
        let command: String
        if let runAsUser, !runAsUser.isEmpty {
            command = "/usr/bin/sudo -S -p '' -H -u \(shellQuote(runAsUser)) /bin/zsh -lc \(shellQuote(script))"
        } else {
            command = "/usr/bin/sudo -S -p '' /bin/zsh -lc \(shellQuote(script))"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        return try execute(process: process, stdin: password + "\n")
    }

    private func execute(process: Process, stdin: String?) throws -> String {
        let stdout = Pipe()
        let stderr = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdinPipe

        try process.run()
        if let stdin, let data = stdin.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        stdinPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let lowered = err.lowercased()
            if lowered.contains("incorrect password")
                || lowered.contains("no password was provided")
                || lowered.contains("try again")
            {
                throw PrivilegedExecutionError.authenticationFailed
            }
            throw PrivilegedExecutionError.commandFailed(err.isEmpty ? out : err)
        }
        return out
    }

    private func shellQuote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    func validateSudoPassword(_ password: String) -> Bool {
        guard !password.isEmpty else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "/usr/bin/sudo -k; /usr/bin/sudo -S -p '' -v"]

        do {
            _ = try execute(process: process, stdin: password + "\n")
            return true
        } catch {
            return false
        }
    }
}
