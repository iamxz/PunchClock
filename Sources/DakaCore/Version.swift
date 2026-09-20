import Foundation

/// 三段式语义版本（X.Y.Z），与 GitHub Release tag 比较用。
/// 纯逻辑、无 IO 依赖，便于单测。
public struct AppVersion: Comparable, Equatable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = max(0, major)
        self.minor = max(0, minor)
        self.patch = max(0, patch)
    }

    /// 解析版本字符串：`1.0.3` / `v1.0.3` / `2` / `2.5` 均支持；
    /// 忽略预发布后缀（如 `1.0.0-rc1` 视为 `1.0.0`）。
    /// 无法解析（如纯非数字、空串）返回 nil。
    public static func parse(_ raw: String) -> AppVersion? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        guard !cleaned.isEmpty else { return nil }
        let parts = cleaned.split(separator: ".", maxSplits: 2).map(String.init)
        guard !parts.isEmpty else { return nil }
        var nums: [Int] = []
        for p in parts {
            let digits = p.prefix(while: { $0.isNumber })
            guard let n = Int(digits) else { return nil }
            nums.append(n)
        }
        let major = nums[0]
        let minor = nums.count > 1 ? nums[1] : 0
        let patch = nums.count > 2 ? nums[2] : 0
        return AppVersion(major: major, minor: minor, patch: patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
