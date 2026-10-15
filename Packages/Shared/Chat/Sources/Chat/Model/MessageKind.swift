public enum MessageKind: Sendable, Equatable {
    case prose(Prose)
    case though(Thought)
    case toolUse(ToolUse)
    case terminal(TerminalCapture)
    case fileEdit(FileEdit)
    case permissionRequest(PermissionRequest)
    case question(Question)
    case status(Status)
    case attachement(Attachment)
    case unsupported(Unsupported)
}

extension MessageKind: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum TypeName: String {
        case prose
        case thought
        case toolUse = "tool_use"
        case terminal
        case fileEdit = "file_edit"
        case permissionRequest = "permission_request"
        case question
        case status
        case attachment
        case unsupported
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decode(String.self, forKey: .type)

        do {
            //TODO
        } catch {
            self = .unsupported(Unsupported(rawType: rawType))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        //TODO
    }
}
