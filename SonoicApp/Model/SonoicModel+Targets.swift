extension SonoicModel {
    var availableTargets: [SonosActiveTarget] {
        sampleTargets
    }

    func selectActiveTarget(_ target: SonosActiveTarget) {
        guard activeTarget.id != target.id else {
            return
        }

        activeTarget = target
    }

    private var sampleTargets: [SonosActiveTarget] {
        [
            SonosActiveTarget(
                id: "living-room",
                name: "Living Room",
                householdName: "Markus's Sonos",
                kind: .room,
                memberNames: ["Living Room"]
            ),
            SonosActiveTarget(
                id: "kitchen",
                name: "Kitchen",
                householdName: "Markus's Sonos",
                kind: .room,
                memberNames: ["Kitchen"]
            ),
            SonosActiveTarget(
                id: "bedroom",
                name: "Bedroom",
                householdName: "Markus's Sonos",
                kind: .room,
                memberNames: ["Bedroom"]
            ),
            SonosActiveTarget(
                id: "downstairs",
                name: "Downstairs",
                householdName: "Markus's Sonos",
                kind: .group,
                memberNames: ["Living Room", "Kitchen"]
            ),
            SonosActiveTarget(
                id: "everywhere",
                name: "Everywhere",
                householdName: "Markus's Sonos",
                kind: .group,
                memberNames: ["Living Room", "Kitchen", "Bedroom"]
            )
        ]
    }
}
