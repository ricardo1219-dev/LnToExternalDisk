import Foundation

final class SIPHintService {
    private let privilegeCoordinator: PrivilegeCoordinator

    init(privilegeCoordinator: PrivilegeCoordinator) {
        self.privilegeCoordinator = privilegeCoordinator
    }

    func isSIPEnabled() -> Bool {
        do {
            let output = try privilegeCoordinator.run(script: "/usr/bin/csrutil status", privileged: false)
            return output.localizedCaseInsensitiveContains("enabled")
        } catch {
            return false
        }
    }

    func hintIfNeeded(for error: Error, sourcePath: String? = nil, targetPath: String? = nil) -> String? {
        let message = error.localizedDescription.lowercased()
        guard message.contains("operation not permitted")
            || message.contains("permission denied")
            || message.contains("not authorized")
        else {
            return nil
        }

        if isUserPathIssue(sourcePath: sourcePath, targetPath: targetPath) {
            return "检测到用户目录权限不足，请使用管理员授权后以该目录所属用户执行（sudo -u 对应用户名），无需关闭 SIP。"
        }

        if isSIPEnabled() {
            return "检测到系统保护可能阻止了该操作，并且当前 SIP 为开启状态。请在确认风险后关闭 SIP，再重新执行。"
        }
        return "检测到系统权限错误，请使用管理员用户重试，并检查目录权限。"
    }

    private func isUserPathIssue(sourcePath: String?, targetPath: String?) -> Bool {
        let paths = [sourcePath, targetPath].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        let hasUsersPath = paths.contains { $0.hasPrefix("/Users/") }
        let hasSystemPath = paths.contains { $0.hasPrefix("/System/") || $0 == "/System" || $0.hasPrefix("/Library/") || $0 == "/Library" }
        return hasUsersPath && !hasSystemPath
    }
}
