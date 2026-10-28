import Foundation
import NookCore
import Testing
@testable import NookSystem

struct JSONBuildReportStoreTests {
    let report = BuildReport(
        isSuccess: false, log: "line one\nline two",
        diagnostics: [BuildDiagnostic(file: URL(filePath: "/a/app.swift"), line: 3, column: 7, message: "boom")],
        duration: .milliseconds(6400), finishedAt: Date(timeIntervalSince1970: 1_800_000_000))

    @Test func savedReportLoadsBack() throws {
        let store = JSONBuildReportStore(directory: try makeScratchDirectory().appending(path: "builds"))
        try store.save(report, nookletID: "com.example.clock")
        #expect(try store.load(nookletID: "com.example.clock") == report)
    }

    @Test func unknownNookletHasNoReport() throws {
        let store = JSONBuildReportStore(directory: try makeScratchDirectory())
        #expect(try store.load(nookletID: "com.example.clock") == nil)
    }

    @Test func deletedReportIsGone() throws {
        let store = JSONBuildReportStore(directory: try makeScratchDirectory())
        try store.save(report, nookletID: "com.example.clock")
        try store.delete(nookletID: "com.example.clock")
        #expect(try store.load(nookletID: "com.example.clock") == nil)
    }

    @Test func corruptReportIsReportedWithItsPath() throws {
        let directory = try makeScratchDirectory()
        let file = directory.appending(path: "com.example.clock.json")
        try Data("nope".utf8).write(to: file)
        #expect(throws: JSONBuildReportStoreError.unreadable(file.path)) {
            try JSONBuildReportStore(directory: directory).load(nookletID: "com.example.clock")
        }
    }
}
