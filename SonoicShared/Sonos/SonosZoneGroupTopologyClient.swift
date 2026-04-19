import Foundation

struct SonosZoneGroupTopology: Equatable {
    struct Group: Equatable {
        var id: String
        var coordinatorID: String
        var members: [Member]
    }

    struct Member: Equatable {
        var id: String
        var name: String
        var host: String?
        var satellites: [Satellite]
    }

    struct Satellite: Equatable {
        var id: String
        var name: String
        var host: String?
    }

    var groups: [Group]

    func member(matchingTargetID targetID: String?, host: String) -> Member? {
        let normalizedLookupHost = normalizedHost(host)

        for group in groups {
            if let targetID,
               let matchingMember = group.members.first(where: { $0.id == targetID })
            {
                return matchingMember
            }

            if let matchingMember = group.members.first(where: { normalizedHost($0.host) == normalizedLookupHost }) {
                return matchingMember
            }
        }

        return nil
    }

    private func normalizedHost(_ host: String?) -> String? {
        host.sonoicNonEmptyTrimmed?.lowercased()
    }
}

struct SonosZoneGroupTopologyClient {
    private let transport: SonosControlTransport

    init(transport: SonosControlTransport = SonosControlTransport()) {
        self.transport = transport
    }

    func fetchTopology(host: String) async throws -> SonosZoneGroupTopology {
        let data = try await transport.performAction(
            service: .zoneGroupTopology,
            named: "GetZoneGroupState",
            body: """
            <u:GetZoneGroupState xmlns:u="\(SonosControlTransport.Service.zoneGroupTopology.soapNamespace)">
            </u:GetZoneGroupState>
            """,
            host: host
        )

        let zoneGroupStateXML = try SonosSOAPValueParser(expectedElement: "ZoneGroupState").parse(data)
        return try SonosZoneGroupTopologyParser().parse(zoneGroupStateXML)
    }
}

private final class SonosZoneGroupTopologyParser: NSObject, XMLParserDelegate {
    private struct ParsedGroup {
        var id: String
        var coordinatorID: String
        var members: [SonosZoneGroupTopology.Member] = []
    }

    private var groups: [SonosZoneGroupTopology.Group] = []
    private var currentGroup: ParsedGroup?
    private var currentDirectMemberIndex: Int?

    func parse(_ xmlString: String) throws -> SonosZoneGroupTopology {
        groups = []
        currentGroup = nil
        currentDirectMemberIndex = nil

        let parser = XMLParser(data: Data(xmlString.utf8))
        parser.delegate = self

        guard parser.parse() else {
            throw parser.parserError ?? SonosControlTransport.TransportError.invalidResponse
        }

        return SonosZoneGroupTopology(groups: groups)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        let localName = normalizedElementName(qName ?? elementName)

        switch localName {
        case "ZoneGroup":
            guard let id = attributeDict["ID"].sonoicNonEmptyTrimmed,
                  let coordinatorID = attributeDict["Coordinator"].sonoicNonEmptyTrimmed
            else {
                return
            }

            currentGroup = ParsedGroup(id: id, coordinatorID: coordinatorID)
            currentDirectMemberIndex = nil

        case "ZoneGroupMember":
            guard var currentGroup,
                  let member = member(from: attributeDict)
            else {
                return
            }

            currentGroup.members.append(member)
            currentDirectMemberIndex = currentGroup.members.indices.last
            self.currentGroup = currentGroup

        case "Satellite":
            guard var currentGroup,
                  let currentDirectMemberIndex,
                  let satellite = satellite(from: attributeDict)
            else {
                return
            }

            currentGroup.members[currentDirectMemberIndex].satellites.append(satellite)
            self.currentGroup = currentGroup

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = normalizedElementName(qName ?? elementName)

        switch localName {
        case "ZoneGroup":
            guard let currentGroup else {
                return
            }

            groups.append(
                SonosZoneGroupTopology.Group(
                    id: currentGroup.id,
                    coordinatorID: currentGroup.coordinatorID,
                    members: currentGroup.members
                )
            )
            self.currentGroup = nil
            currentDirectMemberIndex = nil

        case "ZoneGroupMember":
            currentDirectMemberIndex = nil

        default:
            break
        }
    }

    private func member(from attributes: [String: String]) -> SonosZoneGroupTopology.Member? {
        guard let id = attributes["UUID"].sonoicNonEmptyTrimmed,
              let name = attributes["ZoneName"].sonoicNonEmptyTrimmed
        else {
            return nil
        }

        return SonosZoneGroupTopology.Member(
            id: id,
            name: name,
            host: host(from: attributes["Location"]),
            satellites: []
        )
    }

    private func satellite(from attributes: [String: String]) -> SonosZoneGroupTopology.Satellite? {
        guard let id = attributes["UUID"].sonoicNonEmptyTrimmed,
              let name = attributes["ZoneName"].sonoicNonEmptyTrimmed
        else {
            return nil
        }

        return SonosZoneGroupTopology.Satellite(
            id: id,
            name: name,
            host: host(from: attributes["Location"])
        )
    }

    private func host(from location: String?) -> String? {
        guard let location = location.sonoicNonEmptyTrimmed,
              let url = URL(string: location),
              let host = url.host
        else {
            return nil
        }

        return host
    }

    private func normalizedElementName(_ elementName: String) -> String {
        elementName.sonosXMLLocalName
    }
}
