import Foundation

struct PathMappingConfig: Codable {
    var volumeRoot: String
    var rules: [PathMappingRule]
}

final class PathMappingService {
    private enum Constants {
        static let configKey = "pathMappingConfig.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadConfig() -> PathMappingConfig {
        guard
            let data = defaults.data(forKey: Constants.configKey),
            let config = try? JSONDecoder().decode(PathMappingConfig.self, from: data)
        else {
            return makeDefaultConfig()
        }
        return config
    }

    func saveConfig(_ config: PathMappingConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Constants.configKey)
    }

    func suggestedTargetPath(sourcePath: String, config: PathMappingConfig) -> String {
        let source = normalizedAbsolutePath(sourcePath)
        let sortedRules = config.rules.sorted { $0.sourcePrefix.count > $1.sourcePrefix.count }
        let matched = sortedRules.first { isPrefixMatch(path: source, prefix: normalizedAbsolutePath($0.sourcePrefix)) }

        let mappedSuffix: String
        if let matched {
            let normalizedSourcePrefix = normalizedAbsolutePath(matched.sourcePrefix)
            let replacement = normalizedAbsolutePath(matched.replacementPrefix)
            let tail = String(source.dropFirst(normalizedSourcePrefix.count))
            mappedSuffix = replacement + tail
        } else {
            mappedSuffix = source
        }

        let volumeRoot = normalizedAbsolutePath(config.volumeRoot)
        return normalizeJoin(volumeRoot: volumeRoot, mappedPath: mappedSuffix)
    }

    func refreshTargetExistence(item: inout BatchLinkItem) {
        item.targetExists = FileManager.default.fileExists(atPath: item.targetPath)
    }

    func requiresPrivilegedOperation(for sourcePath: String, targetPath: String) -> Bool {
        let protectedPrefixes = ["/Library", "/Users/Shared", "/private", "/System"]
        return protectedPrefixes.contains(where: { sourcePath == $0 || sourcePath.hasPrefix($0 + "/") })
            || protectedPrefixes.contains(where: { targetPath == $0 || targetPath.hasPrefix($0 + "/") })
    }

    private func makeDefaultConfig() -> PathMappingConfig {
        let username = NSUserName()
        let removableVolume = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsRemovableKey, .volumeIsInternalKey],
            options: [.skipHiddenVolumes]
        )?.first(where: { url in
            let values = try? url.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeIsInternalKey])
            return values?.volumeIsRemovable == true || values?.volumeIsInternal == false
        })?.path ?? "/Volumes/ExternalDisk"

        return PathMappingConfig(
            volumeRoot: removableVolume,
            rules: [
                PathMappingRule(sourcePrefix: "/Users/\(username)", replacementPrefix: "/User"),
                PathMappingRule(sourcePrefix: "/Library", replacementPrefix: "/SystemLibrary")
            ]
        )
    }

    private func normalizedAbsolutePath(_ path: String) -> String {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "/" }
        var normalized = NSString(string: path).expandingTildeInPath
        if !normalized.hasPrefix("/") {
            normalized = "/" + normalized
        }
        while normalized.contains("//") {
            normalized = normalized.replacingOccurrences(of: "//", with: "/")
        }
        if normalized.count > 1 && normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    private func isPrefixMatch(path: String, prefix: String) -> Bool {
        guard path.hasPrefix(prefix) else { return false }
        return path.count == prefix.count || path[path.index(path.startIndex, offsetBy: prefix.count)] == "/"
    }

    private func normalizeJoin(volumeRoot: String, mappedPath: String) -> String {
        let suffix = mappedPath.hasPrefix("/") ? String(mappedPath.dropFirst()) : mappedPath
        return volumeRoot + "/" + suffix
    }
}
