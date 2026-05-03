import Foundation

extension SonoicMusicKitRequestGate {
    func fetchTopCharts(for destination: SonoicAppleMusicBrowseDestination) async throws -> [AppleMusicItemMetadataSection] {
        let types: String
        switch destination {
        case .appleMusicPlaylists:
            types = "playlists"
        case .popularRecommendations:
            types = "songs,albums,playlists"
        case .categories, .playlistsForYou, .newReleases, .radioShows:
            types = "songs,albums,playlists"
        }

        let chartResponse: AppleMusicChartResponse = try await fetchDecoded(
            path: "/v1/catalog/\(try await storefrontCountryCode())/charts",
            queryItems: [
                URLQueryItem(name: "types", value: types),
                URLQueryItem(name: "chart", value: "most-played"),
                URLQueryItem(name: "limit", value: "10")
            ]
        )
        return chartResponse.results.sections()
    }

    func fetchDefaultRecommendations(limit: Int) async throws -> [AppleMusicItemMetadataSection] {
        let response: AppleMusicRecommendationResponse = try await fetchDecoded(
            path: "/v1/me/recommendations",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "include", value: "contents")
            ]
        )
        return response.sections()
    }

    func fetchLiveRadioStations() async throws -> [AppleMusicItemMetadataSection] {
        let response: AppleMusicLibraryResponse = try await fetchDecoded(
            path: "/v1/catalog/\(try await storefrontCountryCode())/stations",
            queryItems: [
                URLQueryItem(name: "filter[featured]", value: "apple-music-live-radio"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )
        let items = response.data.compactMap { resource in
            AppleMusicItemMetadata.metadata(from: resource, origin: .catalogSearch)
        }

        guard !items.isEmpty else {
            return []
        }

        return [
            AppleMusicItemMetadataSection(
                id: "live-radio",
                title: "Live Radio",
                subtitle: nil,
                items: items
            )
        ]
    }

    func fetchCatalogGenres(limit: Int) async throws -> [AppleMusicGenreMetadata] {
        let genreResponse: AppleMusicGenreResponse = try await fetchDecoded(
            path: "/v1/catalog/\(try await storefrontCountryCode())/genres",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
        )
        return genreResponse.data.compactMap { genre in
            guard let name = genre.attributes?.name else {
                return nil
            }

            return AppleMusicGenreMetadata(id: genre.id, title: name)
        }
    }
}
