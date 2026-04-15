import AppKit
import Combine
import Foundation

@MainActor
final class BatchListViewModel: ObservableObject {
    @Published var items: [BatchLinkItem] = []
    @Published var selectedIDs: Set<UUID> = []
    @Published var logs: [String] = []
    @Published var volumeRoot: String = ""
    @Published var rules: [PathMappingRule] = []
    @Published var stopOnFailure = false
    @Published var isRunning = false
    @Published var sipHintMessage = ""
    @Published var sudoEnabled = false
    @Published var adminPassword: String = ""

    private let pathMappingService: PathMappingService
    private let workflowService: SymlinkWorkflowService
    private let sipHintService: SIPHintService
    private let privilegeCoordinator: PrivilegeCoordinator

    init(
        pathMappingService: PathMappingService = PathMappingService(),
        workflowService: SymlinkWorkflowService = SymlinkWorkflowService(privilegeCoordinator: PrivilegeCoordinator()),
        sipHintService: SIPHintService = SIPHintService(privilegeCoordinator: PrivilegeCoordinator()),
        privilegeCoordinator: PrivilegeCoordinator = PrivilegeCoordinator()
    ) {
        self.pathMappingService = pathMappingService
        self.workflowService = workflowService
        self.sipHintService = sipHintService
        self.privilegeCoordinator = privilegeCoordinator

        let config = pathMappingService.loadConfig()
        self.volumeRoot = config.volumeRoot
        self.rules = config.rules
    }

    func addDroppedFolders(urls: [URL]) {
        let config = currentConfig()
        for url in urls where url.hasDirectoryPath {
            let sourcePath = url.path
            let targetPath = pathMappingService.suggestedTargetPath(sourcePath: sourcePath, config: config)
            var item = BatchLinkItem(
                sourcePath: sourcePath,
                targetPath: targetPath,
                conflictPolicy: .mergeStopOnConflict,
                targetExists: false,
                requiresPrivileged: pathMappingService.requiresPrivilegedOperation(for: sourcePath, targetPath: targetPath)
            )
            pathMappingService.refreshTargetExistence(item: &item)
            items.append(item)
        }
        log("已追加 \(urls.count) 条任务")
    }

    func removeSelectedItems() {
        items.removeAll { selectedIDs.contains($0.id) }
        selectedIDs.removeAll()
    }

    func clearItems() {
        items.removeAll()
        selectedIDs.removeAll()
    }

    func refreshTargetState(for index: Int) {
        guard items.indices.contains(index) else { return }
        var item = items[index]
        item.requiresPrivileged = pathMappingService.requiresPrivilegedOperation(for: item.sourcePath, targetPath: item.targetPath)
        pathMappingService.refreshTargetExistence(item: &item)
        items[index] = item
    }

    func saveRules() {
        let config = currentConfig()
        pathMappingService.saveConfig(config)
    }

    func appendRule() {
        rules.append(PathMappingRule(sourcePrefix: "/Users/\(NSUserName())", replacementPrefix: "/User"))
    }

    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
    }

    func removeRule(at index: Int) {
        guard rules.indices.contains(index) else { return }
        rules.remove(at: index)
    }

    func toggleSelection(id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func chooseVolumeRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            volumeRoot = url.path
            saveRules()
            recalculateTargets()
            log("已切换目标卷: \(volumeRoot)")
        }
    }

    func pickFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "导入"
        if panel.runModal() == .OK {
            addDroppedFolders(urls: panel.urls)
        }
    }

    func runBatch() {
        guard !isRunning else { return }
        isRunning = true
        sipHintMessage = ""

        Task {
            defer { isRunning = false }
            for idx in items.indices {
                let ok = await runItem(at: idx)
                if !ok && stopOnFailure {
                    break
                }
            }
        }
    }

    func runSingle(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }), !isRunning else { return }
        isRunning = true
        sipHintMessage = ""
        Task {
            defer { isRunning = false }
            _ = await runItem(at: idx)
        }
    }

    private func recalculateTargets() {
        let config = currentConfig()
        for idx in items.indices {
            items[idx].targetPath = pathMappingService.suggestedTargetPath(
                sourcePath: items[idx].sourcePath,
                config: config
            )
            refreshTargetState(for: idx)
        }
    }

    private func currentConfig() -> PathMappingConfig {
        PathMappingConfig(volumeRoot: volumeRoot, rules: rules)
    }

    private func runItem(at index: Int) async -> Bool {
        guard items.indices.contains(index) else { return false }
        items[index].status = .running
        items[index].message = ""

        do {
            let item = items[index]
            let output = try await executeWorkflowInBackground(
                item: item,
                privileged: false,
                password: nil
            )
            items[index].status = .success
            items[index].message = output.isEmpty ? "执行完成" : output
            log("[成功] \(items[index].sourcePath)")
            return true
        } catch {
            if isPermissionDenied(error) {
                guard ensurePasswordForSudo(index: index, reason: "检测到 Permission denied，请输入管理员密码后使用 sudo 重试。") else {
                    items[index].status = .failed
                    items[index].message = "权限不足，未提供 sudo 密码"
                    log("[失败] \(items[index].sourcePath) - 权限不足，未提供 sudo 密码")
                    return false
                }

                do {
                    let item = items[index]
                    let output = try await executeWorkflowInBackground(
                        item: item,
                        privileged: true,
                        password: adminPassword
                    )
                    items[index].status = .success
                    items[index].message = output.isEmpty ? "执行完成" : "已使用 sudo 重试。\(output)"
                    log("[成功] \(items[index].sourcePath) - sudo 重试成功")
                    return true
                } catch {
                    if isPasswordError(error) {
                        adminPassword = ""
                        guard ensurePasswordForSudo(index: index, reason: "密码错误，请重新输入管理员密码。") else {
                            items[index].status = .failed
                            items[index].message = "sudo 密码错误且用户取消重试"
                            log("[失败] \(items[index].sourcePath) - sudo 密码错误且用户取消重试")
                            return false
                        }

                        do {
                            let item = items[index]
                            let output = try await executeWorkflowInBackground(
                                item: item,
                                privileged: true,
                                password: adminPassword
                            )
                            items[index].status = .success
                            items[index].message = output.isEmpty ? "执行完成" : "已使用 sudo 重试。\(output)"
                            log("[成功] \(items[index].sourcePath) - sudo 二次重试成功")
                            return true
                        } catch {
                            return handleExecutionFailure(error: error, index: index)
                        }
                    }
                    return handleExecutionFailure(error: error, index: index)
                }
            }
            return handleExecutionFailure(error: error, index: index)
        }
    }

    private func log(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logs.insert("[\(formatter.string(from: Date()))] \(text)", at: 0)
    }

    private func requestPassword(reason: String) -> Bool {
        if !adminPassword.isEmpty { return true }

        var prompt = reason
        while true {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "请输入管理员密码"
            alert.informativeText = prompt
            alert.addButton(withTitle: "继续")
            alert.addButton(withTitle: "取消")

            let secureField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            alert.accessoryView = secureField
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else {
                log("用户取消输入管理员密码")
                return false
            }
            let password = secureField.stringValue
            guard !password.isEmpty else {
                prompt = "密码不能为空，请重新输入。"
                continue
            }
            guard privilegeCoordinator.validateSudoPassword(password) else {
                prompt = "密码不正确或当前账号无 sudo 权限，请重新输入。"
                continue
            }

            adminPassword = password
            sudoEnabled = true
            return true
        }
    }

    func setSudoEnabled(_ enabled: Bool) {
        if enabled {
            let gotPassword = requestPassword(reason: "启用 sudo 需要管理员密码。密码仅保存在内存中，可随时关闭并清除。")
            if !gotPassword {
                sudoEnabled = false
                return
            }
            sudoEnabled = true
            return
        }

        sudoEnabled = false
        adminPassword = ""
        log("已关闭 sudo 并清除缓存密码")
    }

    private func isPasswordError(_ error: Error) -> Bool {
        if let privilegedError = error as? PrivilegedExecutionError,
           case .authenticationFailed = privilegedError {
            return true
        }

        let text = error.localizedDescription.lowercased()
        return text.contains("incorrect password")
            || text.contains("no password was provided")
            || text.contains("try again")
            || text.contains("密码错误")
    }

    private func isPermissionDenied(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("permission denied")
            || text.contains("operation not permitted")
            || text.contains("not authorized")
    }

    private func ensurePasswordForSudo(index: Int, reason: String) -> Bool {
        guard items.indices.contains(index) else { return false }
        if sudoEnabled && !adminPassword.isEmpty {
            return true
        }
        let gotPassword = requestPassword(reason: reason)
        if gotPassword {
            items[index].requiresPrivileged = true
        }
        return gotPassword
    }

    private func handleExecutionFailure(error: Error, index: Int) -> Bool {
        guard items.indices.contains(index) else { return false }
        items[index].status = .failed
        items[index].message = error.localizedDescription
        if let hint = sipHintService.hintIfNeeded(
            for: error,
            sourcePath: items[index].sourcePath,
            targetPath: items[index].targetPath
        ) {
            sipHintMessage = hint
        }
        log("[失败] \(items[index].sourcePath) - \(error.localizedDescription)")
        return false
    }

    private func executeWorkflowInBackground(item: BatchLinkItem, privileged: Bool, password: String?) async throws -> String {
        let service = workflowService
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let output = try service.execute(item: item, privileged: privileged, password: password)
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
