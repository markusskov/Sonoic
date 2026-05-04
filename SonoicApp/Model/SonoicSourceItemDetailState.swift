import Foundation

struct SonoicSourceItemDetailState: Equatable {
    var item: SonoicSourceItem
    var sections: [SonoicSourceItemDetailSection]
    var status: SonoicLoadStatus
    var lastUpdatedAt: Date?

    init(
        item: SonoicSourceItem,
        sections: [SonoicSourceItemDetailSection] = [],
        status: SonoicLoadStatus = .idle,
        lastUpdatedAt: Date? = nil
    ) {
        self.item = item
        self.sections = sections
        self.status = status
        self.lastUpdatedAt = lastUpdatedAt
    }

    var isLoading: Bool {
        status.isLoading
    }

    var failureDetail: String? {
        status.failureDetail
    }
}

struct SonoicSourceItemDetailSection: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String?
    var items: [SonoicSourceItem]

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        items: [SonoicSourceItem]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.items = items
    }
}
