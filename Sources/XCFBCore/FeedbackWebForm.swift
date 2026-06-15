import Foundation

public struct FeedbackWebDraft: Decodable, Sendable {
    public let id: Int
    public let formID: Int
    public let teamID: String?
    public let answers: [FeedbackWebDraftAnswer]
    public let filePromises: [FeedbackWebFilePromise]

    enum CodingKeys: String, CodingKey {
        case id
        case formID = "form_id"
        case teamID = "team_id"
        case answers
        case filePromises = "file_promises"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        formID = try container.decode(Int.self, forKey: .formID)
        teamID = try container.decodeIfPresent(FeedbackWebStringID.self, forKey: .teamID)?.value
        answers = try container.decodeIfPresent([FeedbackWebDraftAnswer].self, forKey: .answers) ?? []
        filePromises =
            try container.decodeIfPresent([FeedbackWebFilePromise].self, forKey: .filePromises) ?? []
    }
}

public struct FeedbackWebDraftAnswer: Decodable, Sendable, Equatable {
    public let questionID: Int
    public let values: [String]
    public let ignoreRequired: Bool

    enum CodingKeys: String, CodingKey {
        case questionID = "question_id"
        case values
        case ignoreRequired = "ignore_required"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        questionID = try container.decode(Int.self, forKey: .questionID)
        values = try container.decodeIfPresent([String].self, forKey: .values) ?? []
        ignoreRequired = try container.decodeIfPresent(Bool.self, forKey: .ignoreRequired) ?? false
    }
}

public struct FeedbackWebFilePromise: Decodable, Sendable, Equatable {
    public let id: Int
    public let uuid: String
    public let name: String
    public let size: Int
    public let status: Int

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case name
        case size
        case status = "status_enum"
    }
}

public struct FeedbackWebAttachmentReceipt: Encodable, Sendable, Equatable {
    public let draftID: Int
    public let id: Int
    public let uuid: String
    public let name: String
    public let size: Int
    public let status: Int
    public let verified: Bool

    enum CodingKeys: String, CodingKey {
        case draftID = "draft_id"
        case id
        case uuid
        case name
        case size
        case status = "status_enum"
        case verified
    }
}

public struct FeedbackWebFormSchema: Decodable, Sendable {
    public let id: Int
    public let name: String
    public let formRole: String?
    public let questionGroups: [FeedbackWebQuestionGroup]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case formRole = "form_role"
        case questionGroups = "question_groups"
    }

    public var questions: [FeedbackWebQuestion] {
        questionGroups.flatMap(\.questions)
    }

    public func options(tat: String? = nil) throws -> FeedbackWebFormOptions {
        let selectedQuestions: [FeedbackWebQuestion]
        if let tat {
            let normalized = Self.normalizedTAT(tat)
            selectedQuestions = questions.filter { Self.normalizedTAT($0.tat) == normalized }
            guard !selectedQuestions.isEmpty else {
                throw XCFBError.invalidArgument("Form \(id) has no question with TAT \(normalized)")
            }
        } else {
            selectedQuestions = questions
        }

        var groupTitles: [Int: String] = [:]
        for group in questionGroups {
            for question in group.questions {
                groupTitles[question.id] = group.title
            }
        }
        return FeedbackWebFormOptions(
            id: id,
            name: name,
            formRole: formRole,
            questions: selectedQuestions.map { question in
                FeedbackWebQuestionOption(
                    group: groupTitles[question.id] ?? "",
                    id: question.id,
                    tat: question.tat,
                    text: question.text,
                    widget: question.answerWidget,
                    required: question.isRequired,
                    visible: question.isVisibleInForm,
                    conditions: question.conditions,
                    choices: question.choices
                )
            }
        )
    }

    static func normalizedTAT(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return value
        }
        return value.hasPrefix(":") ? value : ":\(value)"
    }
}

public struct FeedbackWebQuestionGroup: Decodable, Sendable {
    public let title: String
    public let questions: [FeedbackWebQuestion]

    enum CodingKeys: String, CodingKey {
        case title
        case questions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        questions = try container.decodeIfPresent([FeedbackWebQuestion].self, forKey: .questions) ?? []
    }
}

public struct FeedbackWebQuestion: Decodable, Sendable {
    public let id: Int
    public let tat: String
    public let text: String
    public let answerWidget: String
    public let isRequired: Bool
    public let isVisibleInForm: Bool
    public let conditions: String?
    public let choices: [FeedbackWebChoice]

    enum CodingKeys: String, CodingKey {
        case id
        case tat
        case text
        case answerWidget = "answer_widget"
        case isRequired = "is_required"
        case isVisibleInForm = "is_visible_in_form"
        case conditions
        case choiceSet = "choice_set"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        tat = try container.decodeIfPresent(String.self, forKey: .tat) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        answerWidget = try container.decodeIfPresent(String.self, forKey: .answerWidget) ?? ""
        isRequired = try container.decodeIfPresent(Bool.self, forKey: .isRequired) ?? false
        isVisibleInForm =
            try container.decodeIfPresent(Bool.self, forKey: .isVisibleInForm) ?? true
        conditions = try container.decodeIfPresent(String.self, forKey: .conditions)
        choices =
            try container.decodeIfPresent(FeedbackWebChoiceSet.self, forKey: .choiceSet)?
            .choiceOptions ?? []
    }
}

public struct FeedbackWebChoice: Codable, Sendable, Equatable {
    public let label: String
    public let value: String

    public var isPlaceholder: Bool {
        let normalizedLabel = label.lowercased()
        return value == "-1"
            || normalizedLabel.hasPrefix("choose")
            || normalizedLabel.hasPrefix("please select")
    }

    enum CodingKeys: String, CodingKey {
        case label
        case value
        case placeholder
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        label = try container.decode(String.self)
        value = try container.decode(FeedbackWebScalar.self).value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(value, forKey: .value)
        try container.encode(isPlaceholder, forKey: .placeholder)
    }
}

public struct FeedbackWebFormOptions: Encodable, Sendable {
    public let id: Int
    public let name: String
    public let formRole: String?
    public let questions: [FeedbackWebQuestionOption]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case formRole = "form_role"
        case questions
    }
}

public struct FeedbackWebQuestionOption: Encodable, Sendable {
    public let group: String
    public let id: Int
    public let tat: String
    public let text: String
    public let widget: String
    public let required: Bool
    public let visible: Bool
    public let conditions: String?
    public let choices: [FeedbackWebChoice]
}

public struct FeedbackWebAnswerMutation: Encodable, Sendable, Equatable {
    public let questionID: Int
    public let values: [String]?
    public let ignoreRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case questionID = "question_id"
        case values
        case ignoreRequired = "ignore_required"
    }

    public init(
        questionID: Int,
        values: [String]? = nil,
        ignoreRequired: Bool? = nil
    ) {
        self.questionID = questionID
        self.values = values
        self.ignoreRequired = ignoreRequired
    }
}

public enum FeedbackWebDraftEditor {
    public static func mergedAnswers(
        draft: FeedbackWebDraft,
        form: FeedbackWebFormSchema,
        updates: [String: [String]]
    ) throws -> [FeedbackWebAnswerMutation] {
        guard !updates.isEmpty else {
            throw XCFBError.invalidArgument("At least one draft answer update is required")
        }

        var questionsByID: [Int: FeedbackWebQuestion] = [:]
        var questionsByTAT: [String: FeedbackWebQuestion] = [:]
        for question in form.questions {
            questionsByID[question.id] = question
            let tat = FeedbackWebFormSchema.normalizedTAT(question.tat)
            if !tat.isEmpty {
                questionsByTAT[tat] = question
            }
        }

        var normalizedUpdates: [String: [String]] = [:]
        for (tat, values) in updates {
            let normalized = FeedbackWebFormSchema.normalizedTAT(tat)
            guard !normalized.isEmpty else {
                throw XCFBError.invalidArgument("Draft answer TAT cannot be empty")
            }
            normalizedUpdates[normalized] = values
        }

        for tat in normalizedUpdates.keys where questionsByTAT[tat] == nil {
            throw XCFBError.invalidArgument("Form \(form.id) has no question with TAT \(tat)")
        }

        var mutations = draft.answers.map { answer -> FeedbackWebAnswerMutation in
            let question = questionsByID[answer.questionID]
            if answer.ignoreRequired
                || FeedbackWebFormSchema.normalizedTAT(question?.tat ?? "")
                    == ":required_file_zone"
            {
                return FeedbackWebAnswerMutation(
                    questionID: answer.questionID,
                    ignoreRequired: true
                )
            }
            return FeedbackWebAnswerMutation(
                questionID: answer.questionID,
                values: answer.values
            )
        }
        var indexesByQuestionID: [Int: Int] = [:]
        for (index, mutation) in mutations.enumerated() {
            indexesByQuestionID[mutation.questionID] = index
        }

        for question in form.questions {
            let tat = FeedbackWebFormSchema.normalizedTAT(question.tat)
            guard let requestedValues = normalizedUpdates[tat] else {
                continue
            }
            let values = try validatedValues(requestedValues, for: question)
            let mutation = FeedbackWebAnswerMutation(
                questionID: question.id,
                values: values
            )
            if let index = indexesByQuestionID[question.id] {
                mutations[index] = mutation
            } else {
                indexesByQuestionID[question.id] = mutations.count
                mutations.append(mutation)
            }
        }

        return mutations
    }

    private static func validatedValues(
        _ values: [String],
        for question: FeedbackWebQuestion
    ) throws -> [String] {
        guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }) else {
            throw XCFBError.invalidArgument(
                "Answer \(FeedbackWebFormSchema.normalizedTAT(question.tat)) requires a value"
            )
        }

        let widget = question.answerWidget.lowercased()
        if widget.contains("information") || widget.contains("file") {
            throw XCFBError.invalidArgument(
                "Question \(FeedbackWebFormSchema.normalizedTAT(question.tat)) cannot be set as a text answer"
            )
        }

        let choices = question.choices.filter { !$0.isPlaceholder }
        if !choices.isEmpty {
            if widget != "check box" && values.count != 1 {
                throw XCFBError.invalidArgument(
                    "Question \(FeedbackWebFormSchema.normalizedTAT(question.tat)) accepts one value"
                )
            }
            return try values.map { value in
                guard let choice = resolvedChoice(value, in: choices) else {
                    let labels = choices.prefix(12).map(\.label).joined(separator: ", ")
                    let suffix =
                        choices.count > 12
                        ? ", ... Use `xcfb web forms options --id FORM_ID --tat \(FeedbackWebFormSchema.normalizedTAT(question.tat))` to inspect all values."
                        : ""
                    throw XCFBError.invalidArgument(
                        "Invalid value for \(FeedbackWebFormSchema.normalizedTAT(question.tat)): \(value). Expected one of: \(labels)\(suffix)"
                    )
                }
                return choice.value
            }
        }

        guard values.count == 1 else {
            throw XCFBError.invalidArgument(
                "Question \(FeedbackWebFormSchema.normalizedTAT(question.tat)) accepts one value"
            )
        }
        let limit: Int?
        switch question.answerWidget {
        case "Text Field":
            limit = 255
        case "Text Area":
            limit = 4_096
        default:
            limit = nil
        }
        if let limit, values[0].count > limit {
            throw XCFBError.invalidArgument(
                "Answer \(FeedbackWebFormSchema.normalizedTAT(question.tat)) exceeds Apple's \(limit)-character limit"
            )
        }
        return values
    }

    private static func resolvedChoice(
        _ requested: String,
        in choices: [FeedbackWebChoice]
    ) -> FeedbackWebChoice? {
        if let exact = choices.first(where: {
            $0.value == requested || $0.label == requested
        }) {
            return exact
        }
        return choices.first {
            $0.value.caseInsensitiveCompare(requested) == .orderedSame
                || $0.label.caseInsensitiveCompare(requested) == .orderedSame
        }
    }
}

private struct FeedbackWebChoiceSet: Decodable, Sendable {
    let choiceOptions: [FeedbackWebChoice]

    enum CodingKeys: String, CodingKey {
        case choiceOptions = "choice_options"
    }
}

private struct FeedbackWebStringID: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let integer = try? container.decode(Int.self) {
            value = String(integer)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a string or integer identifier"
                )
            )
        }
    }
}

private struct FeedbackWebScalar: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let integer = try? container.decode(Int.self) {
            value = String(integer)
        } else if let double = try? container.decode(Double.self) {
            value = String(double)
        } else if let boolean = try? container.decode(Bool.self) {
            value = String(boolean)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a scalar choice value"
                )
            )
        }
    }
}
