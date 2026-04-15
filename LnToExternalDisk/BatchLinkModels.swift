import Foundation

enum ConflictPolicy: String, CaseIterable, Identifiable, Codable {
    case overwrite
    case mergeOverwrite
    case mergeStopOnConflict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overwrite:
            return "直接覆盖"
        case .mergeOverwrite:
            return "合并(冲突覆盖)"
        case .mergeStopOnConflict:
            return "合并(冲突停止)"
        }
    }
}

enum BatchItemStatus: String {
    case idle
    case running
    case success
    case failed

    var title: String {
        switch self {
        case .idle: return "待执行"
        case .running: return "执行中"
        case .success: return "成功"
        case .failed: return "失败"
        }
    }
}

struct PathMappingRule: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var sourcePrefix: String
    var replacementPrefix: String
}

struct BatchLinkItem: Identifiable, Hashable {
    let id: UUID
    var sourcePath: String
    var targetPath: String
    var conflictPolicy: ConflictPolicy
    var targetExists: Bool
    var requiresPrivileged: Bool
    var status: BatchItemStatus
    var message: String

    init(
        id: UUID = UUID(),
        sourcePath: String,
        targetPath: String,
        conflictPolicy: ConflictPolicy = .mergeStopOnConflict,
        targetExists: Bool = false,
        requiresPrivileged: Bool = false,
        status: BatchItemStatus = .idle,
        message: String = ""
    ) {
        self.id = id
        self.sourcePath = sourcePath
        self.targetPath = targetPath
        self.conflictPolicy = conflictPolicy
        self.targetExists = targetExists
        self.requiresPrivileged = requiresPrivileged
        self.status = status
        self.message = message
    }
}
