import Foundation

public struct LoginCredentials : Equatable, Sendable {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }

    public init?(
        environment: [String: String],
        clearAuth: Bool,
        mockDataEnabled: Bool
    ) {
        if clearAuth || mockDataEnabled {
            return nil
        }

        guard let email = environment["TEST_STACK_EMAIL"], !email.isEmpty else {
            return nil
        }

        guard let password = environment["TEST_STACK_PASSWORD"], !password.isEmpty else {
            return nil
        }

        self.init(email: email, password: password)
    }
}
