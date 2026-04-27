import Foundation
import Testing
@testable import Sonoic

struct SonosQueueDIDLParserTests {
    @Test
    @MainActor
    func parsesDirectQueueItemMetadata() throws {
        let parser = SonosQueueDIDLParser()
        let xml = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
          <item id="Q:0/1">
            <dc:title>The River</dc:title>
            <dc:creator>Bruce Springsteen</dc:creator>
            <upnp:album>The Essential Bruce Springsteen</upnp:album>
            <upnp:albumArtURI>https://example.com/river.jpg</upnp:albumArtURI>
            <res duration="00:05:00">x-sonos-http:librarytrack%3ai.river.m4p?sid=204&amp;flags=8232&amp;sn=7</res>
          </item>
        </DIDL-Lite>
        """

        let item = try #require(try parser.parse(xml).first)

        #expect(item.title == "The River")
        #expect(item.artistName == "Bruce Springsteen")
        #expect(item.albumTitle == "The Essential Bruce Springsteen")
        #expect(item.artworkURL == "https://example.com/river.jpg")
        #expect(item.duration == 300)
    }

    @Test
    @MainActor
    func fallsBackToNestedResourceMetadata() throws {
        let nestedMetadataXML = """
        &lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"&gt;
          &lt;item id="librarytrack:i.river"&gt;
            &lt;dc:title&gt;The River&lt;/dc:title&gt;
            &lt;dc:creator&gt;Bruce Springsteen&lt;/dc:creator&gt;
            &lt;upnp:album&gt;The Essential Bruce Springsteen&lt;/upnp:album&gt;
            &lt;upnp:albumArtURI&gt;https://example.com/river.jpg&lt;/upnp:albumArtURI&gt;
          &lt;/item&gt;
        &lt;/DIDL-Lite&gt;
        """
        let parser = SonosQueueDIDLParser()
        let xml = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/">
          <item id="Q:0/1">
            <r:resMD>\(nestedMetadataXML)</r:resMD>
          </item>
        </DIDL-Lite>
        """

        let item = try #require(try parser.parse(xml).first)

        #expect(item.title == "The River")
        #expect(item.artistName == "Bruce Springsteen")
        #expect(item.albumTitle == "The Essential Bruce Springsteen")
        #expect(item.artworkURL == "https://example.com/river.jpg")
    }
}
