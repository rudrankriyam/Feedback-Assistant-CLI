import CoreFoundation
import Foundation

public struct FeedbackWebSubmissionField: Encodable, Sendable, Equatable {
    public let questionID: Int
    public let tat: String
    public let text: String

    enum CodingKeys: String, CodingKey {
        case questionID = "question_id"
        case tat
        case text
    }
}

public struct FeedbackWebSubmissionPreflight: Encodable, Sendable, Equatable {
    public let draftID: Int
    public let formID: Int
    public let ready: Bool
    public let uploadedAttachmentCount: Int
    public let missingRequiredFields: [FeedbackWebSubmissionField]

    enum CodingKeys: String, CodingKey {
        case draftID = "draft_id"
        case formID = "form_id"
        case ready
        case uploadedAttachmentCount = "uploaded_attachment_count"
        case missingRequiredFields = "missing_required_fields"
    }
}

public enum FeedbackWebSubmissionValidator {
    public static func preflight(
        draft: FeedbackWebDraft,
        form: FeedbackWebFormSchema
    ) throws -> FeedbackWebSubmissionPreflight {
        guard draft.formID == form.id else {
            throw RelatoError.web(
                "draft \(draft.id) belongs to form \(draft.formID), not form \(form.id)"
            )
        }

        let uploadedAttachmentCount = draft.filePromises.filter { $0.status == 40 }.count
        let answersByQuestionID = Dictionary(
            uniqueKeysWithValues: draft.answers.map { ($0.questionID, $0) }
        )
        let missingRequiredFields = visibleQuestions(draft: draft, form: form).compactMap {
            question -> FeedbackWebSubmissionField? in
            guard question.isRequired else {
                return nil
            }

            let tat = FeedbackWebFormSchema.normalizedTAT(question.tat)
            let isSatisfied: Bool
            if tat == ":required_file_zone" {
                isSatisfied = uploadedAttachmentCount > 0
            } else if let answer = answersByQuestionID[question.id] {
                isSatisfied =
                    !answer.values.isEmpty
                    && answer.values != ["-1"]
                    && !answer.values[0].isEmpty
            } else {
                isSatisfied = false
            }

            guard !isSatisfied else {
                return nil
            }
            return FeedbackWebSubmissionField(
                questionID: question.id,
                tat: tat,
                text: question.text
            )
        }

        return FeedbackWebSubmissionPreflight(
            draftID: draft.id,
            formID: form.id,
            ready: missingRequiredFields.isEmpty,
            uploadedAttachmentCount: uploadedAttachmentCount,
            missingRequiredFields: missingRequiredFields
        )
    }

    static func visibleQuestions(
        draft: FeedbackWebDraft,
        form: FeedbackWebFormSchema
    ) -> [FeedbackWebQuestion] {
        let questionsByID = Dictionary(
            uniqueKeysWithValues: form.questions.map { ($0.id, $0) }
        )
        var answersByTAT: [String: String] = [:]
        for answer in draft.answers {
            guard
                let question = questionsByID[answer.questionID],
                let value = answer.values.first
            else {
                continue
            }
            let tat = FeedbackWebFormSchema.normalizedTAT(question.tat)
            if !tat.isEmpty {
                answersByTAT[tat] = value
            }
        }

        return form.questions.filter { question in
            guard question.isVisibleInForm else {
                return false
            }
            guard
                let conditions = question.conditions?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !conditions.isEmpty
            else {
                return true
            }
            guard
                let data = conditions.data(using: .utf8),
                let expression = try? JSONSerialization.jsonObject(with: data)
            else {
                return true
            }
            return FeedbackWebConditionEvaluator.evaluate(
                expression,
                answersByTAT: answersByTAT
            )
        }
    }
}

private enum FeedbackWebConditionValue: Equatable {
    case boolean(Bool)
    case number(Double)
    case string(String)
    case null

    var booleanValue: Bool {
        self == .boolean(true)
    }
}

private enum FeedbackWebConditionEvaluator {
    static func evaluate(
        _ expression: Any,
        answersByTAT: [String: String]
    ) -> Bool {
        guard let values = expression as? [Any], !values.isEmpty else {
            return false
        }
        if values.count == 1 {
            return operand(values[0], answersByTAT: answersByTAT).booleanValue
        }
        guard values.count >= 3 else {
            return false
        }

        var result = comparison(
            left: operand(values[0], answersByTAT: answersByTAT),
            operation: values[1] as? String,
            right: operand(values[2], answersByTAT: answersByTAT)
        )
        var index = 3
        while index + 1 < values.count {
            result = comparison(
                left: .boolean(result),
                operation: values[index] as? String,
                right: operand(values[index + 1], answersByTAT: answersByTAT)
            )
            index += 2
        }
        return result
    }

    private static func operand(
        _ value: Any,
        answersByTAT: [String: String]
    ) -> FeedbackWebConditionValue {
        if let expression = value as? [Any] {
            return .boolean(evaluate(expression, answersByTAT: answersByTAT))
        }
        if value is NSNull {
            return .null
        }
        if let string = value as? String {
            let tat = FeedbackWebFormSchema.normalizedTAT(string)
            if string.hasPrefix(":"), let answer = answersByTAT[tat] {
                return .string(answer)
            }
            return .string(string)
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .boolean(number.boolValue)
            }
            return .number(number.doubleValue)
        }
        return .null
    }

    private static func comparison(
        left: FeedbackWebConditionValue,
        operation: String?,
        right: FeedbackWebConditionValue
    ) -> Bool {
        switch operation {
        case ":==":
            return left == right
        case ":!=":
            return left != right
        case ":and":
            return left.booleanValue && right.booleanValue
        case ":or":
            return left.booleanValue || right.booleanValue
        default:
            return false
        }
    }
}
