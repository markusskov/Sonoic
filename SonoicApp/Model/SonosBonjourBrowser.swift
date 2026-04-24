import Foundation

@MainActor
final class SonosBonjourBrowser: NSObject {
    struct Service: Identifiable, Equatable {
        let id: String
        let instanceName: String
        let roomName: String
        var host: String?
        var port: Int?

        var isResolved: Bool {
            host != nil && port != nil
        }
    }

    var onServicesChanged: (([Service]) -> Void)?
    var onFailure: ((String?) -> Void)?

    private let browser = NetServiceBrowser()
    private var trackedServices: [String: NetService] = [:]
    private var serviceSnapshots: [String: Service] = [:]
    private var isBrowsing = false

    override init() {
        super.init()
        browser.delegate = self
    }

    func startBrowsing() {
        guard !isBrowsing else {
            return
        }

        isBrowsing = true
        onFailure?(nil)
        browser.searchForServices(ofType: "_sonos._tcp.", inDomain: "local.")
    }

    func refresh() {
        stopBrowsing(clearResults: false)
        startBrowsing()
    }

    func stopBrowsing(clearResults: Bool = false) {
        browser.stop()
        isBrowsing = false

        for service in trackedServices.values {
            service.stop()
        }

        trackedServices.removeAll()

        if clearResults {
            serviceSnapshots.removeAll()
            publishServices()
        }
    }

    private func addDiscoveredService(_ service: NetService) {
        trackedServices[service.name] = service
        serviceSnapshots[service.name] = snapshot(for: service)
        service.delegate = self
        service.resolve(withTimeout: 5)
        publishServices()
    }

    private func removeDiscoveredService(_ service: NetService) {
        trackedServices.removeValue(forKey: service.name)
        serviceSnapshots.removeValue(forKey: service.name)
        publishServices()
    }

    private func updateResolvedService(_ service: NetService) {
        serviceSnapshots[service.name] = snapshot(
            for: service,
            host: normalizedHostName(service.hostName),
            port: service.port
        )
        publishServices()
    }

    private func snapshot(for service: NetService, host: String? = nil, port: Int? = nil) -> Service {
        let parsedServiceID = service.name.split(separator: "@", maxSplits: 1).first.map(String.init)
            ?? service.name
        let parsedRoomName = service.name.split(separator: "@", maxSplits: 1).dropFirst().first.map(String.init)
            ?? service.name
        let resolvedPort: Int?
        if let port,
           port > 0
        {
            resolvedPort = port
        } else {
            resolvedPort = nil
        }

        return Service(
            id: parsedServiceID,
            instanceName: service.name,
            roomName: parsedRoomName,
            host: host,
            port: resolvedPort
        )
    }

    private func normalizedHostName(_ hostName: String?) -> String? {
        hostName?
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .sonoicNonEmptyTrimmed
    }

    private func publishServices() {
        let mergedServices = Dictionary(grouping: serviceSnapshots.values, by: \.id)
            .values
            .compactMap { groupedServices in
                groupedServices.first(where: \.isResolved) ?? groupedServices.first
            }
            .sorted { lhs, rhs in
                lhs.roomName.localizedCaseInsensitiveCompare(rhs.roomName) == .orderedAscending
            }

        onServicesChanged?(mergedServices)
    }
}

extension SonosBonjourBrowser: NetServiceBrowserDelegate {
    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        addDiscoveredService(service)
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        removeDiscoveredService(service)
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didNotSearch errorDict: [String : NSNumber]
    ) {
        isBrowsing = false
        onFailure?(NetService.error(from: errorDict))
    }
}

extension SonosBonjourBrowser: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        updateResolvedService(sender)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        onFailure?(NetService.error(from: errorDict))
    }
}

private extension NetService {
    static func error(from errorDict: [String: NSNumber]) -> String {
        if let code = errorDict["NSNetServicesErrorCode"]?.intValue {
            return "Bonjour discovery failed (\(code))."
        }

        return "Bonjour discovery failed."
    }
}
