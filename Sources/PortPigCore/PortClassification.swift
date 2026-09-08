import Foundation

public enum PortCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case web
    case database
    case cache
    case messaging
    case container
    case mobile
    case development
    case system
    case other
}

public struct PortClassification: Equatable, Sendable {
    public let category: PortCategory
    public let displayName: String
    public let secondaryDisplayName: String?
    public let reason: String
    public let iconName: String?
    public let applicationBundlePath: String?

    public init(
        category: PortCategory,
        displayName: String,
        secondaryDisplayName: String? = nil,
        reason: String,
        iconName: String? = nil,
        applicationBundlePath: String? = nil
    ) {
        self.category = category
        self.displayName = displayName
        self.secondaryDisplayName = secondaryDisplayName
        self.reason = reason
        self.iconName = iconName
        self.applicationBundlePath = applicationBundlePath
    }

    public var isWebServer: Bool {
        category == .web
    }

    public var isDevelopmentRelated: Bool {
        switch category {
        case .web, .database, .cache, .messaging, .container, .mobile, .development:
            return true
        case .system, .other:
            return false
        }
    }
}
