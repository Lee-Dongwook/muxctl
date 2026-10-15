import Foundation

struct CLIError: Error, CustomStringConvertible {
    enum SocketFailureKind: Equatable {
        case pathMissing
        case pathInspectionFailed
        case pathTypeConflict
        case pathOwnershipConflict
        case startupTimeout
        case receiveTimeoutConfiguration
    }

    let message: String
    let exitCode : Int32
    let vCode: String?
    let isStructuredProtocolResponse: Bool
    let retryable: Bool
    let vmBackendCode: String?
    let vmBackendHTTPStatus: Int?
    let socketFailureKind: SocketFailureKind?
    let vMethod: String?

    init(
        message: String,
        exitCode: Int32 = 1,
        vCode: String? = nil,
        isStructuredProtocolResponse: Bool = false,
        retryable: Bool = false,
        vmBackendCode: String? = nil,
        vmBackendHTTPStatus: Int? = nil,
        socketFailureKind: SocketFailureKind? = nil,
        vMethod: String? = nil,
    ) {
        self.message = message
        self.exitCode = exitCode
        self.vCode = vCode
        self.isStructuredProtocolResponse = isStructuredProtocolResponse
        self.retryable = retryable
        self.vmBackendCode = vmBackendCode
        self.vmBackendHTTPStatus = vmBackendHTTPStatus
        self.socketFailureKind = socketFailureKind
        self.vMethod = vMethod
    }

    var description: String { message }
}
