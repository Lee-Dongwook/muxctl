import Foundation

public struct Config: Equatable, Sendable {
    public let projectId: String
    public let publishClientKey: String

    public init(projectId: String, publishClientKey: String) {
        self.projectId = projectId
        self.publishClientKey = publishClientKey
    }

     public init(
        environment: Environment,
        overrides: [String: String] = [:],
        developmentProjectId: String,
        productionProjectId: String,
        developmentPublishableClientKey: String,
        productionPublishableClientKey: String
    ) {
        switch environment {
            case .development:
                self.init(
                    projectId: overrides["PROJECT_DEV_ID"] ?? developmentProjectId,
                    publishClientKey: overrides["PUBLISH_CLIENT_DEV_KEY"] ?? developmentPublishableClientKey
                )
            case .production:
                self.init(
                    projectId: overrides["PROJECT_ID"] ?? productionProjectId,
                    publishClientKey: overrides["PUBLISH_CLIENT_KEY"] ?? productionPublishableClientKey
                )
        }
    }
}
