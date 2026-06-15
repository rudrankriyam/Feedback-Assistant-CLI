import Foundation
import Testing
@testable import XCFBCore

@Test func webFormOptionsNormalizeChoiceLabelsAndValues() throws {
    let form = try JSONDecoder().decode(
        FeedbackWebFormSchema.self,
        from: Data(testFormJSON.utf8)
    )

    let options = try form.options(tat: "area")
    #expect(options.id == 4167)
    #expect(options.name == "Developer Technologies & SDKs")
    #expect(options.questions.count == 1)
    let question = try #require(options.questions.first)
    #expect(question.group == "Basic Information")
    #expect(question.tat == ":area")
    #expect(question.choices.count == 3)
    #expect(question.choices[0].isPlaceholder)
    #expect(question.choices[2].label == "Foundation Models Framework")
    #expect(question.choices[2].value == "seed:foundationmodelsframework")
    #expect(question.conditions == #"[[":platform",":==","macOS"]]"#)
}

@Test func webDraftEditorPreservesAnswersAndResolvesChoiceLabels() throws {
    let decoder = JSONDecoder()
    let form = try decoder.decode(
        FeedbackWebFormSchema.self,
        from: Data(testFormJSON.utf8)
    )
    let draft = try decoder.decode(
        FeedbackWebDraft.self,
        from: Data(testDraftJSON.utf8)
    )

    let answers = try FeedbackWebDraftEditor.mergedAnswers(
        draft: draft,
        form: form,
        updates: [
            "title": ["Updated title"],
            ":platform": ["macOS"],
            ":area": ["Foundation Models Framework"],
            ":type_req": ["suggestion"],
            ":description": ["Updated description"],
        ]
    )

    #expect(answers.count == 6)
    #expect(
        answers.first(where: { $0.questionID == 304072 })?.values
            == ["Keep this existing impact"]
    )
    #expect(
        answers.first(where: { $0.questionID == 366028 })?.values
            == ["Updated title"]
    )
    #expect(
        answers.first(where: { $0.questionID == 366030 })?.values
            == ["seed:foundationmodelsframework"]
    )
    #expect(
        answers.first(where: { $0.questionID == 366031 })?.values
            == ["Suggestion"]
    )
}

@Test func webDraftEditorRejectsUnknownChoicesAndOversizedText() throws {
    let decoder = JSONDecoder()
    let form = try decoder.decode(
        FeedbackWebFormSchema.self,
        from: Data(testFormJSON.utf8)
    )
    let draft = try decoder.decode(
        FeedbackWebDraft.self,
        from: Data(testDraftJSON.utf8)
    )

    #expect(throws: XCFBError.self) {
        try FeedbackWebDraftEditor.mergedAnswers(
            draft: draft,
            form: form,
            updates: [":platform": ["NewtonOS"]]
        )
    }
    #expect(throws: XCFBError.self) {
        try FeedbackWebDraftEditor.mergedAnswers(
            draft: draft,
            form: form,
            updates: [":title": [String(repeating: "x", count: 256)]]
        )
    }
}

private let testDraftJSON = #"""
{
  "id": 104688952,
  "form_id": 4167,
  "team_id": null,
  "answers": [
    {
      "id": 809386105,
      "question_id": 304072,
      "ignore_required": false,
      "values": ["Keep this existing impact"]
    },
    {
      "id": 809386106,
      "question_id": 366028,
      "ignore_required": false,
      "values": ["Existing title"]
    }
  ]
}
"""#

private let testFormJSON = #"""
{
  "id": 4167,
  "name": "Developer Technologies & SDKs",
  "form_role": "Issue",
  "question_groups": [
    {
      "title": "Basic Information",
      "questions": [
        {
          "id": 366028,
          "tat": ":title",
          "text": "Please provide a descriptive title for your feedback:",
          "answer_widget": "Text Field",
          "is_required": true,
          "is_visible_in_form": true
        },
        {
          "id": 366029,
          "tat": ":platform",
          "text": "Which platform is most relevant for your report?",
          "answer_widget": "Popup",
          "is_required": true,
          "is_visible_in_form": true,
          "choice_set": {
            "choice_options": [
              ["Choose…", -1],
              ["iOS", "iOS"],
              ["macOS", "macOS"]
            ]
          }
        },
        {
          "id": 366030,
          "tat": ":area",
          "text": "Which technology does your report involve?",
          "answer_widget": "Popup",
          "is_required": true,
          "is_visible_in_form": true,
          "conditions": "[[\":platform\",\":==\",\"macOS\"]]",
          "choice_set": {
            "choice_options": [
              ["Please select the problem area", -1],
              ["Foundation", "seed:foundation"],
              ["Foundation Models Framework", "seed:foundationmodelsframework"]
            ]
          }
        },
        {
          "id": 366031,
          "tat": ":type_req",
          "text": "What type of feedback are you reporting?",
          "answer_widget": "Popup",
          "is_required": true,
          "is_visible_in_form": true,
          "choice_set": {
            "choice_options": [
              ["Choose…", -1],
              ["Incorrect/Unexpected Behavior", "Incorrect/Unexpected Behavior"],
              ["Suggestion", "Suggestion"]
            ]
          }
        }
      ]
    },
    {
      "title": "Description",
      "questions": [
        {
          "id": 366122,
          "tat": ":description",
          "text": "Please describe the issue:",
          "answer_widget": "Text Area",
          "is_required": true,
          "is_visible_in_form": true
        },
        {
          "id": 304072,
          "tat": ":dev_impact",
          "text": "Please describe the impact:",
          "answer_widget": "Text Area",
          "is_required": false,
          "is_visible_in_form": true
        }
      ]
    }
  ]
}
"""#
