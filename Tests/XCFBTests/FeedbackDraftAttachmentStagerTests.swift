import Foundation
import Testing
@testable import XCFBCore

@Test func draftAttachmentStagerCopiesIntoNewestDraft() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("XCFBTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("evidence.txt")
    try "fresh evidence".write(to: source, atomically: true, encoding: .utf8)

    let draftRoot = root.appendingPathComponent("Drafts/FB", isDirectory: true)
    let newestDraft = draftRoot.appendingPathComponent("222", isDirectory: true)
    try FileManager.default.createDirectory(at: newestDraft, withIntermediateDirectories: true)
    try "existing".write(to: newestDraft.appendingPathComponent("evidence.txt"), atomically: true, encoding: .utf8)

    let db = root.appendingPathComponent("feedback.sqlite")
    try runSQLite(
        db,
        sql: """
        CREATE TABLE ZFORMRESPONSE (
            ZREMOTEID INTEGER,
            ZCOMPLETED INTEGER
        );
        INSERT INTO ZFORMRESPONSE (ZREMOTEID, ZCOMPLETED) VALUES (111, 0);
        INSERT INTO ZFORMRESPONSE (ZREMOTEID, ZCOMPLETED) VALUES (222, 0);
        INSERT INTO ZFORMRESPONSE (ZREMOTEID, ZCOMPLETED) VALUES (333, 1);
        """
    )

    let attachment = try FeedbackDraftAttachmentStager.stage(
        snapshotPath: source.path,
        storePath: db.path,
        draftRoot: draftRoot.path
    )

    #expect(attachment.draftID == "222")
    #expect(URL(fileURLWithPath: attachment.path).lastPathComponent == "evidence_01.txt")
    #expect(try String(contentsOfFile: attachment.path, encoding: .utf8) == "fresh evidence")
}

private func runSQLite(_ db: URL, sql: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [db.path, sql]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}
