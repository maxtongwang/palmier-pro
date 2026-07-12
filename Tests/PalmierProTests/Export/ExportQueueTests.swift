import Foundation
import Testing
@testable import PalmierPro

@Suite("Export queue", .serialized)
@MainActor
struct ExportQueueTests {
    @Test func runsInFIFOOrder() async throws {
        let queue = ExportQueue()
        var events: [String] = []
        let first = try enqueue(queue, "first.mov") { _ in
            events.append("first-start")
            try? await Task.sleep(for: .milliseconds(80))
            events.append("first-finish")
        }
        let second = try enqueue(queue, "second.mov") { _ in
            events.append("second-start")
            events.append("second-finish")
        }

        #expect(first.started)
        #expect(!second.started)
        #expect(second.queuePosition == 1)
        #expect(await waitUntil { !queue.hasActivity })
        #expect(events == ["first-start", "first-finish", "second-start", "second-finish"])
    }

    @Test func cancelingActiveJobAdvancesQueue() async throws {
        let queue = ExportQueue()
        var secondRan = false
        let first = try enqueue(queue, "active.mov") { _ in
            try? await Task.sleep(for: .seconds(30))
        }
        let second = try enqueue(queue, "next.mov") { _ in secondRan = true }

        queue.cancel(first.jobID)

        #expect(await waitUntil {
            queue.job(first.jobID)?.status == .canceled && queue.job(second.jobID)?.status == .completed
        })
        #expect(secondRan)
    }

    @Test func cancelingWaitingJobDoesNotRunIt() async throws {
        let queue = ExportQueue()
        var waitingRan = false
        _ = try enqueue(queue, "waiting-blocker.mov") { _ in
            try? await Task.sleep(for: .milliseconds(100))
        }
        let waiting = try enqueue(queue, "waiting.mov") { _ in waitingRan = true }

        queue.cancel(waiting.jobID)

        #expect(queue.job(waiting.jobID)?.status == .canceled)
        #expect(await waitUntil { !queue.hasActivity })
        #expect(!waitingRan)
    }

    @Test func reservesDestinationUntilFailureFinishes() async throws {
        let queue = ExportQueue()
        let outputURL = temporaryURL("reserved.mov")
        _ = try queue.enqueueForTesting(outputURL: outputURL) { service in
            try? await Task.sleep(for: .milliseconds(80))
            service.error = "Render failed"
        }

        #expect(throws: ExportQueueError.self) {
            try queue.enqueueForTesting(outputURL: outputURL) { _ in }
        }
        #expect(await waitUntil { queue.jobs.first?.status == .failed })

        let retry = try queue.enqueueForTesting(outputURL: outputURL) { _ in }
        #expect(await waitUntil { queue.job(retry.jobID)?.status == .completed })
    }

    @Test func reportsProgress() async throws {
        let queue = ExportQueue()
        let progressJob = try enqueue(queue, "progress.xml") { service in
            service.onPhaseChange?(.exporting)
            service.onProgressChange?(0.42)
            try? await Task.sleep(for: .milliseconds(80))
        }
        #expect(await waitUntil { queue.job(progressJob.jobID)?.progress == 0.42 })
        #expect(await waitUntil { queue.job(progressJob.jobID)?.status == .completed })
    }

    @Test func scopesHistoryByProject() async throws {
        let queue = ExportQueue()
        let first = try enqueue(queue, "project-first.xml", projectID: "project-a") { _ in }
        let second = try enqueue(queue, "project-second.xml", projectID: "project-b") { _ in }
        #expect(await waitUntil { !queue.hasActivity })
        #expect(queue.jobs(for: "project-a").map(\.id) == [first.jobID])
        #expect(queue.jobs(for: "project-b").map(\.id) == [second.jobID])

        queue.clearFinished(for: "project-a")

        #expect(queue.jobs(for: "project-a").isEmpty)
        #expect(queue.jobs(for: "project-b").map(\.id) == [second.jobID])
    }

    private func enqueue(
        _ queue: ExportQueue,
        _ name: String,
        projectID: String = "test-project",
        operation: @escaping @MainActor (ExportService) async -> Void
    ) throws -> ExportQueueSubmission {
        try queue.enqueueForTesting(outputURL: temporaryURL(name), projectID: projectID, operation: operation)
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("export-queue-\(name)")
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private extension ExportQueue {
    func job(_ id: UUID) -> ExportJob? { jobs.first { $0.id == id } }
}
