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

    @Test
    func matchesCloudFavoritesAndPlaylistsByUniqueTitle() {
        let snapshot = SonosControlAPICloudSnapshot(
            households: [
                SonosControlAPIHousehold(id: "household-1")
            ],
            groupsByHouseholdID: [:],
            favoritesByHouseholdID: [
                "household-1": [
                    SonosControlAPIFavorite(
                        id: "favorite-1",
                        name: "Easy Mode",
                        description: nil,
                        imageUrl: nil,
                        service: SonosControlAPIService(
                            id: "204",
                            name: "Apple Music",
                            imageUrl: nil
                        )
                    ),
                    SonosControlAPIFavorite(
                        id: "favorite-2",
                        name: "Duplicate",
                        description: nil,
                        imageUrl: nil,
                        service: nil
                    ),
                    SonosControlAPIFavorite(
                        id: "favorite-3",
                        name: "Duplicate",
                        description: nil,
                        imageUrl: nil,
                        service: nil
                    )
                ]
            ],
            playlistsByHouseholdID: [
                "household-1": [
                    SonosControlAPIPlaylist(
                        id: "playlist-1",
                        name: "Følelsen #",
                        type: nil,
                        trackCount: 40
                    )
                ]
            ]
        )

        #expect(snapshot.uniqueFavorite(matchingTitle: "easy   mode", householdID: "household-1")?.id == "favorite-1")
        #expect(
            snapshot.uniqueFavorite(
                matchingTitle: "easy   mode",
                householdID: "household-1",
                serviceName: "Apple Music"
            )?.id == "favorite-1"
        )
        #expect(
            snapshot.uniqueFavorite(
                matchingTitle: "easy   mode",
                householdID: "household-1",
                serviceName: "Spotify"
            ) == nil
        )
        #expect(snapshot.uniqueFavorite(matchingTitle: "duplicate", householdID: "household-1") == nil)
        #expect(snapshot.uniquePlaylist(matchingTitle: "Folelsen #", householdID: "household-1")?.id == "playlist-1")
        #expect(snapshot.hasLoadedFavorites(for: "household-1"))
        #expect(snapshot.hasLoadedPlaylists(for: "household-1"))
        #expect(!snapshot.hasLoadedFavorites(for: "missing-household"))
        #expect(!snapshot.hasLoadedPlaylists(for: "missing-household"))
    }

    @Test
    func disambiguatesCloudFavoritesWithDuplicateTitlesByServiceName() {
        let snapshot = SonosControlAPICloudSnapshot(
            households: [
                SonosControlAPIHousehold(id: "household-1")
            ],
            groupsByHouseholdID: [:],
            favoritesByHouseholdID: [
                "household-1": [
                    SonosControlAPIFavorite(
                        id: "favorite-apple-music",
                        name: "Let's Groove",
                        description: nil,
                        imageUrl: nil,
                        service: SonosControlAPIService(
                            id: "204",
                            name: "Apple Music",
                            imageUrl: nil
                        )
                    ),
                    SonosControlAPIFavorite(
                        id: "favorite-spotify",
                        name: "Let's   Groove",
                        description: nil,
                        imageUrl: nil,
                        service: SonosControlAPIService(
                            id: "3079",
                            name: "Spotify",
                            imageUrl: nil
                        )
                    )
                ]
            ]
        )

        #expect(snapshot.uniqueFavorite(matchingTitle: "let's groove", householdID: "household-1") == nil)
        #expect(
            snapshot.uniqueFavorite(
                matchingTitle: "let's groove",
                householdID: "household-1",
                serviceName: "Apple Music"
            )?.id == "favorite-apple-music"
        )
        #expect(
            snapshot.uniqueFavorite(
                matchingTitle: "let's groove",
                householdID: "household-1",
                serviceName: "Unknown Service"
            ) == nil
        )
    }

    @Test
    func selectedCommandTargetTrimsAndDisambiguatesConfiguredIDs() {
        let snapshot = SonosControlAPICloudSnapshot(
            households: [
                SonosControlAPIHousehold(id: "household-1"),
                SonosControlAPIHousehold(id: "household-2")
            ],
            groupsByHouseholdID: [
                "household-1": SonosControlAPIGroupSnapshot(
                    groups: [
                        SonosControlAPIGroup(
                            id: "shared-group",
                            name: "Kitchen",
                            coordinatorId: "player-1",
                            playerIds: ["player-1"]
                        )
                    ],
                    players: []
                ),
                "household-2": SonosControlAPIGroupSnapshot(
                    groups: [
                        SonosControlAPIGroup(
                            id: "shared-group",
                            name: "Stue",
                            coordinatorId: "player-2",
                            playerIds: ["player-2", "player-3"]
                        )
                    ],
                    players: []
                )
            ]
        )
        let settings = SonosControlAPISettings(
            mode: .fallback,
            selectedHouseholdID: "  household-2\n",
            selectedGroupID: "\tshared-group  "
        )
        let blankGroupSettings = SonosControlAPISettings(
            mode: .fallback,
            selectedHouseholdID: "household-2",
            selectedGroupID: "   \n"
        )

        let target = snapshot.selectedCommandTarget(settings: settings)

        #expect(target?.householdID == "household-2")
        #expect(target?.groupID == "shared-group")
        #expect(target?.playerID == "player-2")
        #expect(target?.coordinatorPlayerID == "player-2")
        #expect(snapshot.selectedCommandTarget(settings: blankGroupSettings) == nil)
    }

    @Test
    func resolvesCommandTargetOnlyWhenActiveTargetMatchesCloudGroup() {
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
                            playerIds: ["player-1", "player-2"]
                        )
                    ],
                    players: []
                )
            ]
        )

        #expect(snapshot.commandTarget(activeTargetID: "group-1")?.groupID == "group-1")
        #expect(snapshot.commandTarget(activeTargetID: "player-1")?.groupID == "group-1")
        #expect(snapshot.commandTarget(activeTargetID: "manual-host:192.0.2.1") == nil)
    }
}
