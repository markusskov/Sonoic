import Testing
@testable import Sonoic

struct SonosControlAPIQueueCurrentIndexResolverTests {
    @Test
    func resolvesExactItemIDBeforeNumericFallback() {
        let index = SonoicSonosControlAPIQueueCurrentIndexResolver.currentIndex(
            itemIDs: ["one", "2", "three"],
            candidates: ["2", "three"]
        )

        #expect(index == 1)
    }

    @Test
    func resolvesMetadataExactIDBeforeStatusNumericFallback() {
        let index = SonoicSonosControlAPIQueueCurrentIndexResolver.currentIndex(
            itemIDs: ["sonoic-1", "sonoic-2", "sonoic-3"],
            candidates: ["1", "sonoic-3"]
        )

        #expect(index == 2)
    }

    @Test
    func resolvesOneBasedNumericIndexWhenNoExactIDMatches() {
        let index = SonoicSonosControlAPIQueueCurrentIndexResolver.currentIndex(
            itemIDs: ["sonoic-1", "sonoic-2", "sonoic-3"],
            candidates: ["2"]
        )

        #expect(index == 1)
    }

    @Test
    func rejectsOutOfRangeNumericIndex() {
        let index = SonoicSonosControlAPIQueueCurrentIndexResolver.currentIndex(
            itemIDs: ["sonoic-1", "sonoic-2", "sonoic-3"],
            candidates: ["4"]
        )

        #expect(index == nil)
    }

    @Test
    func ignoresEmptyCandidates() {
        let index = SonoicSonosControlAPIQueueCurrentIndexResolver.currentIndex(
            itemIDs: ["sonoic-1", "sonoic-2"],
            candidates: [nil, " ", ""]
        )

        #expect(index == nil)
    }
}
