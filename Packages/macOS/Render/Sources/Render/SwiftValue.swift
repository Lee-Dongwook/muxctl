import Foundation

public enum SwiftValue: Codable, Sendable, Equatable {
    case int(Int)
    case double(Double)
    case string(String)
    case bool(Bool)

    case null
    case range(lower: Int, upper: Int, inclusive: Bool)
    indirect case array([SwiftValue])
    indirect case object([String: SwiftValue])

    public var displayString: String {
        switch self {
        case let .int(value): return String(value)
        case let .double(value): return String(value)
        case let .string(value): return value
        case let .bool(value): return String(value)
        case .null: return "nil"
        case let .range(lower, upper, inclusive): return "\(lower)\(inclusive ? "..." : "..<")\(upper)"
        case let .array(values): return "[" + values.map(\.displayString).joined(separator: ", ") + "]"
        case let .object(fields): return "{" + fields.keys.sorted().map { "\($0): \(fields[$0]!.displayString)" }.joined(separator: ", ") + "}"
        }
    }

    public func member(_ name: String) -> SwiftValue? {
        switch self {
        case let .object(fields):
            return fields[name]
        case let .array(values):
            if name == "count" { return .int(values.count) }
            if name == "isEmpty" { return .bool(values.isEmpty) }
            if name == "indices" { return .array(values.indices.map { .int($0) }) }
            if name == "first" { return values.first }
            if name == "last" { return values.last }
            return nil
        case let .string(value):
            if name == "count" { return .int(value.count) }
            if name == "isEmpty" { return .bool(value.isEmpty) }
            if name == "capitalized" { return .string(value.capitalized) }
            if name == "uppercased" { return .string(value.uppercased()) }
            if name == "lowercased" { return .string(value.lowercased()) }
            return nil
        default:
            return nil
        }
    }

    public var isTruthy: Bool {
        if case let .bool(value) = self { return value }
        return false
    }

    public var iterationValues: [SwiftValue]? {
        switch self {
            case let .range(lower, upper, inclusive):
                let (end, addOveflow) = inclusive ? upper.addingReportingOverflow(1) : (upper, false)
                guard !addOverflow, end >= lower else { return [] }
                let (count, subOverflow) = end.subtractingReportingOverflow(lower)
                guard !subOverflow, count <= 100_000 else { return [] }
                return (lower..<end).map(SwiftValue.int)
            case let .array(values):
                return values
            default:
                return nil
        }
    }
}
