public struct Question: Sendable, Equatable, Codable {
    public struct Option: Sendable, Equatable, Codable, Identifiable {
        public var id: String { label }
        public let label: String
        public let detail: String?

        public init(label: String, detail: String? = nil, ) {
            self.label = label
            self.detail = detail
        }

        private enum CodingKeys: String, CodingKey {
            case label
            case detail
        }
    }

    public let prompt: String
    public let options: [Option]
    public let selectedOptionLabel: String?
    public let questionID: String?

    public init(
        prompt: String,
        options: [Option],
        selectedOptionLabel: String? = nil,
        questionID: String? = nil
    ) {
        self.prompt = prompt
        self.options = options
        self.selectedOptionLabel = selectedOptionLabel
        self.questionID = questionID
    }

    private enum CodingKeys: String, CodingKey {
        case prompt
        case options
        case selectedOptionLabel = "selected_option_label"
        case questionID = "question_id"
    }
}
