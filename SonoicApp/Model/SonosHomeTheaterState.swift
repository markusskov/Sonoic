import Foundation

enum SonosHomeTheaterState: Equatable {
    case idle
    case loading
    case loaded(SonosHomeTheaterSettings)
    case failed(String)

    var settings: SonosHomeTheaterSettings? {
        guard case let .loaded(settings) = self else {
            return nil
        }

        return settings
    }

    var failureDetail: String? {
        guard case let .failed(detail) = self else {
            return nil
        }

        return detail
    }
}
