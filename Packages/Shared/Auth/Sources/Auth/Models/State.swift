import Foundation

public struct State: Equatable, Sendable {
    public let isAuthenticated: Bool
    public let currentUser: User?
    public let isRestoringSession: Bool

    public init(isAuthenticated: Bool, currentUser: User?, isRestoringSession: Bool) {
        self.isAuthenticated = isAuthenticated
        self.currentUser = currentUser
        self.isRestoringSession = isRestoringSession
    }

    public static func primed(
        clearAuthRequested: Bool,
        mockDataEnabled: Bool,
        fixtureUser: User?,
        autoLoginCredentials: LoginCredentials?,
        cachedUser: User?,
        hasTokens: Bool,
        mockUser: User
    ) -> Self {
        if clearAuthRequested {
            return .cleared()
        }

        if mockDataEnabled {
            return Self(isAuthenticated: true, currentUser: mockUser, isRestoringSession: false)
        }

        if let fixtureUser {
            return Self(isAuthenticated: true, currentUser: fixtureUser, isRestoringSession: false)
        }

        if autoLoginCredentials != nil, !hasTokens {
            return Self(isAuthenticated: false, currentUser: cachedUser, isRestoringSession: true)
        }

        if hasTokens, let cachedUser {
            return Self(isAuthenticated: true, currentUser: cachedUser, isRestoringSession: true)
        }

        return Self(isAuthenticated: false, currentUser: cachedUser, isRestoringSession: hasTokens)
    }

    public static func cleared() -> Self {
        Self(isAuthenticated: false, currentUser: nil, isRestoringSession: false)
    }
}
