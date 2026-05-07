import Testing
@testable import Sonoic

struct SonosControlAPICloudStateTests {
    @Test
    func summarizesCloudSnapshotCounts() {
        let snapshot = SonosControlAPICloudSnapshot(
            households: [
                SonosControlAPIHousehold(id: "household-1")
            ],
            groupsByHouseholdID: [
                "household-1": SonosControlAPIGroupSnapshot(
                    groups: [
                        SonosControlAPIGroup(
                            id: "group-1",
                            name: "Stue",
                            coordinatorId: "player-1",
                            playerIds: ["player-1"]
                        )
                    ],
                    players: [
                        SonosControlAPIPlayer(
                            id: "player-1",
                            name: "Stue",
                            roomName: "Stue",
                            deviceIds: nil
                        )
                    ]
                )
            ]
        )

        #expect(snapshot.summary == "1 household · 1 group · 1 player")
        #expect(SonosControlAPICloudState(status: .verified(snapshot)).detail == snapshot.summary)
    }
}
