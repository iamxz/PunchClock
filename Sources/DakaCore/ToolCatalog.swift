import Foundation

public enum ToolID: String, CaseIterable, Identifiable, Sendable {
    case punch, water, eye, sedentary
    public var id: String { rawValue }
}

public struct ToolMetadata: Equatable, Sendable, Identifiable {
    public let id: ToolID
    public let title: String
    public let symbol: String

    public init(id: ToolID, title: String, symbol: String) {
        self.id = id
        self.title = title
        self.symbol = symbol
    }
}

public enum ToolCatalog {
    public static let all: [ToolMetadata] = [
        ToolMetadata(id: .punch, title: "打卡统计", symbol: "checkmark.seal"),
        ToolMetadata(id: .water, title: "喝水", symbol: "drop"),
        ToolMetadata(id: .eye, title: "护眼", symbol: "eye"),
        ToolMetadata(id: .sedentary, title: "久坐", symbol: "figure.walk")
    ]

    public static func metadata(for id: ToolID) -> ToolMetadata {
        all.first { $0.id == id } ?? all[0]
    }
}
