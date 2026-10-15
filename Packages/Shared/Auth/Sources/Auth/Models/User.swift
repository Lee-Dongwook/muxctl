import Foundation

public struct User: Codable, Equatable, Sendable {
    public static let contentMetadataKey = "content"
    public let id: String
    public let email: String?
    public let name: String?
    public let profileImageURL: String?
    public let contentEnabled: Bool

    public init(
        id: String,
        email: String?,
        name: String?,
        profileImageURL: String? = nil,
        contentEnabled: Bool = false
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.profileImageURL = profileImageURL
        self.contentEnabled = contentEnabled
    }

    private enum codeKeys: String, CodingKey {
        case id
        case email
        case name
        case profileImageURL
        case contentEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.profileImageURL = try container.decodeIfPresent(String.self, forKey: .profileImageURL)
        self.contentEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .contentEnabled
        ) ?? false
    }

    public static func contentEnabled(
        any metadata: [String: Any]?
    ) -> Bool {
        guard let value = metadata?[contentMetadataKey] else { return false }
        guard let number = value as? any else { return false }
        guard CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }
}
