import Foundation
import Testing
@testable import Sonoic

struct SonosFavoritesDIDLParserTests {
    @Test
    @MainActor
    func preservesFullResMetadataWhenAlreadyWrapped() throws {
        let playbackMetadataXML = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <item id="track-1">
            <dc:title>Real Song</dc:title>
          </item>
        </DIDL-Lite>
        """
        let escapedPlaybackMetadataXML = """
        &lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/"&gt;
          &lt;item id="track-1"&gt;
            &lt;dc:title&gt;Real Song&lt;/dc:title&gt;
          &lt;/item&gt;
        &lt;/DIDL-Lite&gt;
        """
        let parser = SonosFavoritesDIDLParser()
        let xml = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/">
          <item id="favorite-1">
            <dc:title>Morning Mix</dc:title>
            <res>x-sonosapi-stream:s1234?sid=204</res>
            <r:resMD>\(escapedPlaybackMetadataXML)</r:resMD>
          </item>
        </DIDL-Lite>
        """

        let favorite = try #require(parser.parse(xml).first)
        let parsedPlaybackMetadataXML = try #require(favorite.playbackMetadataXML)

        #expect(favorite.title == "Morning Mix")
        #expect(favorite.playbackURI == "x-sonosapi-stream:s1234?sid=204")
        #expect(favorite.kind == .item)
        #expect(parsedPlaybackMetadataXML.sonoicTrimmed == playbackMetadataXML.sonoicTrimmed)
    }

    @Test
    @MainActor
    func wrapsFragmentResMetadataInDIDLRoot() throws {
        let escapedFragmentMetadataXML = """
        &lt;item id="track-2"&gt;&lt;dc:title&gt;Wrapped Song&lt;/dc:title&gt;&lt;/item&gt;
        """
        let parser = SonosFavoritesDIDLParser()
        let xml = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/">
          <item id="favorite-2">
            <dc:title>Evening Mix</dc:title>
            <res>x-rincon-cpcontainer:0006206cspotify%3aplaylist%3a123</res>
            <r:resMD>\(escapedFragmentMetadataXML)</r:resMD>
          </item>
        </DIDL-Lite>
        """

        let favorite = try #require(parser.parse(xml).first)
        let parsedPlaybackMetadataXML = try #require(favorite.playbackMetadataXML)

        #expect(parsedPlaybackMetadataXML.contains("<DIDL-Lite"))
        #expect(parsedPlaybackMetadataXML.contains("Wrapped Song"))
        #expect(parsedPlaybackMetadataXML.contains("<item id=\"track-2\">"))
    }

    @Test
    @MainActor
    func marksContainerFavoritesAsCollections() throws {
        let parser = SonosFavoritesDIDLParser()
        let xml = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <container id="favorite-playlist">
            <dc:title>Kitchen Playlist</dc:title>
            <res>x-rincon-cpcontainer:0006206cspotify%3aplaylist%3a123?sid=9</res>
          </container>
        </DIDL-Lite>
        """

        let favorite = try #require(parser.parse(xml).first)

        #expect(favorite.kind == .collection)
        #expect(favorite.isCollectionLike)
        #expect(favorite.isPlaylistLike)
        #expect(favorite.service == .spotify)
    }

    @Test
    @MainActor
    func separatesPlaylistFavoritesFromOtherCollections() {
        let playlist = SonosFavoriteItem(
            id: "playlist",
            title: "Road Trip",
            subtitle: nil,
            artworkURL: nil,
            service: .appleMusic,
            playbackURI: "x-rincon-cpcontainer:1006206cplaylist%3a123?sid=204",
            playbackMetadataXML: "<upnp:class>object.container.playlistContainer</upnp:class>",
            kind: .collection
        )
        let album = SonosFavoriteItem(
            id: "album",
            title: "Road Trip",
            subtitle: nil,
            artworkURL: nil,
            service: .appleMusic,
            playbackURI: "x-rincon-cpcontainer:1006206calbum%3a123?sid=204",
            playbackMetadataXML: "<upnp:class>object.container.album.musicAlbum</upnp:class>",
            kind: .collection
        )
        let station = SonosFavoriteItem(
            id: "station",
            title: "Road Trip",
            subtitle: nil,
            artworkURL: nil,
            service: .appleMusic,
            playbackURI: "x-sonosapi-radio:station%3a123?sid=204",
            playbackMetadataXML: "<upnp:class>object.item.audioItem.audioBroadcast</upnp:class>",
            kind: .collection
        )

        #expect(playlist.isCollectionLike)
        #expect(playlist.isPlaylistLike)
        #expect(album.isCollectionLike)
        #expect(!album.isPlaylistLike)
        #expect(station.isCollectionLike)
        #expect(!station.isPlaylistLike)
    }
}
