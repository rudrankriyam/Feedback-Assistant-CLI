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
