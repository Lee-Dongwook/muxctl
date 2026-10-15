import Foundation

public struct Team: Codable, Equatable, Identifiable, Sendable {
    public let teamId: String
    public let name: String
    public let slug: String?

    public init(teamId: String, name: String, slug: String?) {
        self.teamId = teamId
        self.name = name
        self.slug = slug
    }
}
