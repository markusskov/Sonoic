import Foundation
import Testing
@testable import Sonoic

struct SonosSOAPValuesParserTests {
    @Test
    @MainActor
    func preservesEmptyButPresentValues() throws {
        let response = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
              <Result></Result>
              <NumberReturned>0</NumberReturned>
            </u:BrowseResponse>
          </s:Body>
        </s:Envelope>
        """

        let values = try SonosSOAPValuesParser(
            expectedElements: ["Result", "NumberReturned", "TotalMatches"]
        ).parse(Data(response.utf8))

        #expect(values["Result"] == "")
        #expect(values["NumberReturned"] == "0")
        #expect(values["TotalMatches"] == nil)
    }
}
