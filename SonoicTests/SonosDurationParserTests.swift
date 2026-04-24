import Foundation
import Testing
@testable import Sonoic

struct SonosDurationParserTests {
    @Test(arguments: [
        ("00:00:00", 0.0),
        ("01:02:03", 3723.0),
        ("00:03:14.500", 194.5),
    ])
    func parsesSupportedDurations(_ rawValue: String, expectedSeconds: TimeInterval) {
        let parsedValue = SonosDurationParser.parseTimeInterval(from: rawValue)
        #expect(parsedValue != nil)
        #expect(abs((parsedValue ?? 0) - expectedSeconds) < 0.0001)
    }

    @Test(arguments: [nil, "", "NOT_IMPLEMENTED", "3:15", "bad-value"])
    func rejectsUnsupportedDurations(_ rawValue: String?) {
        #expect(SonosDurationParser.parseTimeInterval(from: rawValue) == nil)
    }
}
