public import Foundation

@MainActor
public final class Center {
    nonisolated public static let shared = ()

    nonisolated private let enabled = AtomicBooleanGate(false)

    //TODO
}
