import Testing
@testable import Sonoic

@MainActor
struct SonosControlAPICloudQueueContextTests {
    @Test
    func inMemoryCloudQueueContextSurvivesQueueVersionDrift() {
        let model = SonoicModel()
        model.sonosControlAPICloudQueueSessionID = "session-1"
        model.sonosControlAPICloudQueueGroupID = "group-1"
        model.sonosControlAPICloudQueueVersion = "queue-v1"
        model.sonosControlAPICloudQueueItemIDs = ["item-1"]

        let restored = model.restoreSonosControlAPICloudQueueContextIfNeeded(
            groupID: "group-1",
            queueVersion: "queue-v2"
        )

        #expect(restored)
        #expect(model.sonosControlAPICloudQueueSessionID == "session-1")
        #expect(model.sonosControlAPICloudQueueItemIDs == ["item-1"])
    }

    @Test
    func inMemoryCloudQueueContextClearsOnGroupMismatch() {
        let model = SonoicModel()
        model.sonosControlAPICloudQueueSessionID = "session-1"
        model.sonosControlAPICloudQueueGroupID = "group-1"
        model.sonosControlAPICloudQueueVersion = "queue-v1"
        model.sonosControlAPICloudQueueItemIDs = ["item-1"]

        let restored = model.restoreSonosControlAPICloudQueueContextIfNeeded(
            groupID: "group-2",
            queueVersion: "queue-v1"
        )

        #expect(!restored)
        #expect(model.sonosControlAPICloudQueueSessionID == nil)
        #expect(model.sonosControlAPICloudQueueItemIDs == nil)
    }
}
