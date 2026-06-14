import Foundation
import Testing
@testable import RelatoKit

@Test func webSubmissionPreflightHandlesConditionalRequiredFileZone() throws {
    let form = try JSONDecoder().decode(
        FeedbackWebFormSchema.self,
        from: Data(submissionFormJSON.utf8)
    )
    let draftWithoutAttachment = try JSONDecoder().decode(
        FeedbackWebDraft.self,
        from: Data(submissionDraftWithoutAttachmentJSON.utf8)
    )

    let blocked = try FeedbackWebSubmissionValidator.preflight(
        draft: draftWithoutAttachment,
        form: form
    )
    #expect(!blocked.ready)
    #expect(blocked.uploadedAttachmentCount == 0)
    #expect(blocked.missingRequiredFields.map(\.tat) == [":required_file_zone"])

    let draftWithAttachment = try JSONDecoder().decode(
        FeedbackWebDraft.self,
        from: Data(submissionDraftWithAttachmentJSON.utf8)
    )
    let ready = try FeedbackWebSubmissionValidator.preflight(
        draft: draftWithAttachment,
        form: form
    )
    #expect(ready.ready)
    #expect(ready.uploadedAttachmentCount == 1)
    #expect(ready.missingRequiredFields.isEmpty)
}

@Test func webSubmissionPreflightIgnoresInactiveConditionalQuestions() throws {
    let form = try JSONDecoder().decode(
        FeedbackWebFormSchema.self,
        from: Data(submissionFormJSON.utf8)
    )
    let draft = try JSONDecoder().decode(
        FeedbackWebDraft.self,
        from: Data(
            submissionDraftWithoutAttachmentJSON
                .replacingOccurrences(of: "\"Suggestion\"", with: "\"Incorrect/Unexpected Behavior\"")
                .utf8
        )
    )

    let preflight = try FeedbackWebSubmissionValidator.preflight(
        draft: draft,
        form: form
    )
    #expect(preflight.ready)
    #expect(preflight.missingRequiredFields.isEmpty)
}

@Test func webSubmissionPreflightHonorsIgnoredRequiredAnswers() throws {
    let form = try JSONDecoder().decode(
        FeedbackWebFormSchema.self,
        from: Data(submissionFormJSON.utf8)
    )
    let draft = try JSONDecoder().decode(
        FeedbackWebDraft.self,
        from: Data(
            #"""
            {
              "id": 104688952,
              "form_id": 4167,
              "answers": [
                {"question_id": 366028, "values": ["Video input"]},
                {"question_id": 366031, "values": ["Suggestion"]},
                {"question_id": 364164, "ignore_required": true}
              ],
              "file_promises": []
            }
            """#.utf8
        )
    )

    let preflight = try FeedbackWebSubmissionValidator.preflight(
        draft: draft,
        form: form
    )
    #expect(preflight.ready)
    #expect(preflight.missingRequiredFields.isEmpty)
}

@Test func webSubmissionPreflightUsesLatestDuplicateAnswer() throws {
    let form = try JSONDecoder().decode(
        FeedbackWebFormSchema.self,
        from: Data(submissionFormJSON.utf8)
    )
    let draft = try JSONDecoder().decode(
        FeedbackWebDraft.self,
        from: Data(
            #"""
            {
              "id": 104688952,
              "form_id": 4167,
              "answers": [
                {"question_id": 366028, "values": []},
                {"question_id": 366028, "values": ["Video input"]},
                {"question_id": 366031, "values": ["Incorrect/Unexpected Behavior"]}
              ],
              "file_promises": []
            }
            """#.utf8
        )
    )

    let preflight = try FeedbackWebSubmissionValidator.preflight(
        draft: draft,
        form: form
    )
    #expect(preflight.ready)
    #expect(preflight.missingRequiredFields.isEmpty)
}

@Test func webSubmissionPreflightTreatsEmptyConditionsAsVisible() throws {
    let form = try JSONDecoder().decode(
        FeedbackWebFormSchema.self,
        from: Data(
            #"""
            {
              "id": 4167,
              "name": "Developer Technologies & SDKs",
              "question_groups": [
                {
                  "questions": [
                    {
                      "id": 364164,
                      "tat": ":required_file_zone",
                      "text": "Attach supporting evidence",
                      "answer_widget": "Required File Zone",
                      "is_required": true,
                      "is_visible_in_form": true,
                      "conditions": "[]"
                    }
                  ]
                }
              ]
            }
            """#.utf8
        )
    )
    let draft = try JSONDecoder().decode(
        FeedbackWebDraft.self,
        from: Data(
            #"{"id":104688952,"form_id":4167,"answers":[],"file_promises":[]}"#
                .utf8
        )
    )

    let preflight = try FeedbackWebSubmissionValidator.preflight(
        draft: draft,
        form: form
    )
    #expect(!preflight.ready)
    #expect(preflight.missingRequiredFields.map(\.tat) == [":required_file_zone"])
}

@Test func webSubmissionPreflightTreatsMissingConditionAnswersAsEmpty() throws {
    let form = try JSONDecoder().decode(
        FeedbackWebFormSchema.self,
        from: Data(
            #"""
            {
              "id": 4167,
              "name": "Developer Technologies & SDKs",
              "question_groups": [
                {
                  "questions": [
                    {
                      "id": 366031,
                      "tat": ":type_req",
                      "text": "Feedback type",
                      "answer_widget": "Popup",
                      "is_visible_in_form": true
                    },
                    {
                      "id": 366032,
                      "tat": ":description",
                      "text": "Description",
                      "answer_widget": "Text Area",
                      "is_required": true,
                      "is_visible_in_form": true,
                      "conditions": "[[\":type_req\",\":==\",\"\"]]"
                    }
                  ]
                }
              ]
            }
            """#.utf8
        )
    )
    let unansweredDraft = try JSONDecoder().decode(
        FeedbackWebDraft.self,
        from: Data(
            #"{"id":104688952,"form_id":4167,"answers":[],"file_promises":[]}"#
                .utf8
        )
    )

    let unanswered = try FeedbackWebSubmissionValidator.preflight(
        draft: unansweredDraft,
        form: form
    )
    #expect(!unanswered.ready)
    #expect(unanswered.missingRequiredFields.map(\.tat) == [":description"])

    let answeredDraft = try JSONDecoder().decode(
        FeedbackWebDraft.self,
        from: Data(
            #"""
            {
              "id": 104688952,
              "form_id": 4167,
              "answers": [
                {"question_id": 366031, "values": ["Suggestion"]}
              ],
              "file_promises": []
            }
            """#.utf8
        )
    )
    let answered = try FeedbackWebSubmissionValidator.preflight(
        draft: answeredDraft,
        form: form
    )
    #expect(answered.ready)
    #expect(answered.missingRequiredFields.isEmpty)
}

@Test func webSubmissionAnswerPayloadUsesAppleRequiredFileRepresentation() throws {
    let form = try JSONDecoder().decode(
        FeedbackWebFormSchema.self,
        from: Data(submissionFormJSON.utf8)
    )
    let draft = try JSONDecoder().decode(
        FeedbackWebDraft.self,
        from: Data(submissionDraftWithAttachmentJSON.utf8)
    )

    let data = try JSONEncoder().encode(
        FeedbackWebSubmissionAnswerBuilder.payload(draft: draft, form: form)
    )
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let answers = try #require(object["answers"] as? [[String: Any]])
    let fileAnswer = try #require(
        answers.first(where: { $0["question_id"] as? Int == 364164 })
    )
    #expect(fileAnswer["values"] as? Bool == false)
    #expect(fileAnswer["ignore_required"] as? Bool == true)
}

@Test func webSubmissionResponseRequiresTypedFeedbackRecord() throws {
    let fileOnly = try JSONDecoder().decode(
        FeedbackWebMutationResponse.self,
        from: Data(
            #"{"items":{"upsert":[{"id":60604757,"type":"FILE_PROMISE"}]}}"#
                .utf8
        )
    )
    #expect(fileOnly.items.feedbackID == nil)

    let feedback = try JSONDecoder().decode(
        FeedbackWebMutationResponse.self,
        from: Data(
            #"{"items":{"upsert":[{"id":60604757,"type":"FILE_PROMISE"},{"id":23050000,"type":"FEEDBACK"}]}}"#
                .utf8
        )
    )
    #expect(feedback.items.feedbackID == 23_050_000)
}

private let submissionFormJSON = #"""
{
  "id": 4167,
  "name": "Developer Technologies & SDKs",
  "question_groups": [
    {
      "title": "Basic Information",
      "questions": [
        {
          "id": 366028,
          "tat": ":title",
          "text": "Title",
          "answer_widget": "Text Field",
          "is_required": true,
          "is_visible_in_form": true
        },
        {
          "id": 366031,
          "tat": ":type_req",
          "text": "Feedback type",
          "answer_widget": "Popup",
          "is_required": true,
          "is_visible_in_form": true
        },
        {
          "id": 364164,
          "tat": ":required_file_zone",
          "text": "Attach supporting evidence",
          "answer_widget": "Required File Zone",
          "is_required": true,
          "is_visible_in_form": true,
          "conditions": "[[\":type_req\",\":==\",\"Suggestion\"]]"
        }
      ]
    }
  ]
}
"""#

private let submissionDraftWithoutAttachmentJSON = #"""
{
  "id": 104688952,
  "form_id": 4167,
  "answers": [
    {"question_id": 366028, "values": ["Video input"]},
    {"question_id": 366031, "values": ["Suggestion"]}
  ],
  "file_promises": []
}
"""#

private let submissionDraftWithAttachmentJSON = #"""
{
  "id": 104688952,
  "form_id": 4167,
  "answers": [
    {"question_id": 366028, "values": ["Video input"]},
    {"question_id": 366031, "values": ["Suggestion"]}
  ],
  "file_promises": [
    {
      "id": 60604757,
      "uuid": "BE25C106-A40B-4C79-B94E-B9BC8BD46640",
      "name": "evidence.md",
      "size": 823,
      "status_enum": 40
    }
  ]
}
"""#
