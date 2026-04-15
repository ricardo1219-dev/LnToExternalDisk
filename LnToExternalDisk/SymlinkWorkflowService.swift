import Foundation

enum WorkflowError: LocalizedError {
    case invalidSource(String)
    case sourceAlreadySymlink
    case sourceNameRecreated
    case noAvailableBackupName
    case commandOutput(String)

    var errorDescription: String? {
        switch self {
        case .invalidSource(let path):
            return "源目录不存在或不可用: \(path)"
        case .sourceAlreadySymlink:
            return "源路径已经是软链接"
        case .sourceNameRecreated:
            return "源路径在改名后被系统重新创建，请使用另一个管理员用户操作"
        case .noAvailableBackupName:
            return "无法生成可用备份目录名称"
        case .commandOutput(let message):
            return message
        }
    }
}

final class SymlinkWorkflowService {
    private let privilegeCoordinator: PrivilegeCoordinator

    init(privilegeCoordinator: PrivilegeCoordinator) {
        self.privilegeCoordinator = privilegeCoordinator
    }

    func execute(item: BatchLinkItem, privileged: Bool, password: String?) throws -> String {
        guard FileManager.default.fileExists(atPath: item.sourcePath) else {
            throw WorkflowError.invalidSource(item.sourcePath)
        }

        if isSymlink(at: item.sourcePath) {
            throw WorkflowError.sourceAlreadySymlink
        }

        let backupPath = try nextBackupPath(for: item.sourcePath)
        let script = buildScript(
            sourcePath: item.sourcePath,
            targetPath: item.targetPath,
            backupPath: backupPath,
            policy: item.conflictPolicy
        )
        let preferredUser = preferredUserFromSourcePath(item.sourcePath)

        let output = try privilegeCoordinator.run(
            script: script,
            privileged: privileged,
            preferredUser: preferredUser,
            password: password
        )
        try validateWorkflowOutput(output)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildScript(sourcePath: String, targetPath: String, backupPath: String, policy: ConflictPolicy) -> String {
        let source = shellQuote(sourcePath)
        let target = shellQuote(targetPath)
        let backup = shellQuote(backupPath)
        let targetParent = shellQuote((targetPath as NSString).deletingLastPathComponent)

        let targetPreparation: String
        switch policy {
        case .overwrite:
            targetPreparation = """
            if [ -e \(target) ] || [ -L \(target) ]; then
              /bin/rm -rf \(target)
            fi
            """
        case .mergeOverwrite, .mergeStopOnConflict:
            targetPreparation = "/bin/mkdir -p \(target)"
        }

        let migrateSection: String
        switch policy {
        case .overwrite:
            migrateSection = """
            if [ -e \(target) ] || [ -L \(target) ]; then
              /bin/rm -rf \(target)
            fi
            /bin/mv \(backup) \(target)
            """
        case .mergeOverwrite:
            migrateSection = """
            /usr/bin/rsync -a \(backup)/ \(target)/
            /bin/rm -rf \(backup)
            """
        case .mergeStopOnConflict:
            migrateSection = """
            /usr/bin/python3 - <<'PY'
            import os, sys
            src = \(pythonQuote(backupPath))
            dst = \(pythonQuote(targetPath))
            for root, _, files in os.walk(src):
                rel = os.path.relpath(root, src)
                base = dst if rel == "." else os.path.join(dst, rel)
                for f in files:
                    if os.path.exists(os.path.join(base, f)):
                        print("__MERGE_CONFLICT__")
                        sys.exit(42)
            sys.exit(0)
            PY
            if [ $? -ne 0 ]; then
              echo "__MERGE_CONFLICT__"
              exit 42
            fi
            /usr/bin/rsync -a \(backup)/ \(target)/
            /bin/rm -rf \(backup)
            """
        }

        return """
        set -e
        SOURCE=\(source)
        TARGET=\(target)
        BACKUP=\(backup)
        COMMITTED=0
        BACKUP_DONE=0
        LINK_DONE=0

        rollback() {
          if [ "${COMMITTED}" = "1" ]; then
            return
          fi
          if [ "${LINK_DONE}" = "1" ] && [ -L "${SOURCE}" ]; then
            /bin/rm "${SOURCE}" || true
          fi
          if [ "${BACKUP_DONE}" = "1" ] && [ -e "${BACKUP}" ] && [ ! -e "${SOURCE}" ]; then
            /bin/mv "${BACKUP}" "${SOURCE}" || true
          fi
        }

        trap rollback ERR

        if [ ! -e "${SOURCE}" ]; then
          echo "__SOURCE_MISSING__"
          exit 2
        fi

        /bin/mkdir -p \(targetParent)
        \(targetPreparation)

        /bin/mv "${SOURCE}" "${BACKUP}"
        BACKUP_DONE=1

        if [ -e "${SOURCE}" ] || [ -L "${SOURCE}" ]; then
          echo "__SOURCE_RECREATED__"
          exit 31
        fi

        /bin/ln -s "${TARGET}" "${SOURCE}"
        LINK_DONE=1

        \(migrateSection)

        COMMITTED=1
        echo "__SUCCESS__"
        """
    }

    private func nextBackupPath(for sourcePath: String) throws -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let base = sourcePath + ".backup." + timestamp
        let fm = FileManager.default

        if !fm.fileExists(atPath: base) {
            return base
        }
        for index in 1...99 {
            let candidate = base + ".\(index)"
            if !fm.fileExists(atPath: candidate) {
                return candidate
            }
        }
        throw WorkflowError.noAvailableBackupName
    }

    private func isSymlink(at path: String) -> Bool {
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isSymbolicLinkKey]) else {
            return false
        }
        return values.isSymbolicLink == true
    }

    private func shellQuote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    private func pythonQuote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }

    private func preferredUserFromSourcePath(_ sourcePath: String) -> String? {
        let path = sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/Users/") else { return nil }
        let parts = path.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        let user = String(parts[1])
        return user.isEmpty ? nil : user
    }

    private func validateWorkflowOutput(_ output: String) throws {
        if output.contains("__SOURCE_RECREATED__") {
            throw WorkflowError.sourceNameRecreated
        }
        if output.contains("__MERGE_CONFLICT__") {
            throw WorkflowError.commandOutput("合并遇到重名冲突，已按策略停止")
        }
    }

}
