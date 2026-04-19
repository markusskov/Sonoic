import Foundation

struct SonosDeviceInfo: Equatable {
    var roomName: String
    var modelName: String?
    var friendlyName: String?
    var serialNumber: String?
    var udn: String?

    var playerDetail: String? {
        if let modelName = modelName.sonoicNonEmptyTrimmed {
            return modelName
        }

        guard let friendlyName = friendlyName.sonoicNonEmptyTrimmed, friendlyName != roomName else {
            return nil
        }

        return friendlyName
    }

    var preferredTargetID: String? {
        if let udn = udn.sonoicNonEmptyTrimmed {
            return udn.replacingOccurrences(of: "uuid:", with: "")
        }

        return serialNumber.sonoicNonEmptyTrimmed
    }
}

struct SonosDeviceInfoClient {
    private let transport: SonosControlTransport

    init(transport: SonosControlTransport = SonosControlTransport()) {
        self.transport = transport
    }

    func fetchDeviceInfo(host: String) async throws -> SonosDeviceInfo {
        let data = try await transport.performGET(resource: "/xml/device_description.xml", host: host)
        return try SonosDeviceDescriptionParser().parse(data)
    }
}

private final class SonosDeviceDescriptionParser: NSObject, XMLParserDelegate {
    private var roomName: String?
    private var modelName: String?
    private var friendlyName: String?
    private var serialNumber: String?
    private var udn: String?
    private var currentFieldName: String?
    private var capturedValue = ""

    func parse(_ data: Data) throws -> SonosDeviceInfo {
        roomName = nil
        modelName = nil
        friendlyName = nil
        serialNumber = nil
        udn = nil
        currentFieldName = nil
        capturedValue = ""

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw parser.parserError ?? SonosControlTransport.TransportError.invalidResponse
        }

        guard let resolvedRoomName = roomName.sonoicNonEmptyTrimmed ?? friendlyName.sonoicNonEmptyTrimmed else {
            throw SonosControlTransport.TransportError.missingValue("roomName")
        }

        return SonosDeviceInfo(
            roomName: resolvedRoomName,
            modelName: modelName.sonoicNonEmptyTrimmed,
            friendlyName: friendlyName.sonoicNonEmptyTrimmed,
            serialNumber: serialNumber.sonoicNonEmptyTrimmed,
            udn: udn.sonoicNonEmptyTrimmed
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        guard let fieldName = normalizedFieldName(for: qName ?? elementName) else {
            return
        }

        currentFieldName = fieldName
        capturedValue = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentFieldName != nil else {
            return
        }

        capturedValue.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard let currentFieldName,
              normalizedFieldName(for: qName ?? elementName) == currentFieldName
        else {
            return
        }

        assign(capturedValue, to: currentFieldName)
        self.currentFieldName = nil
    }

    private func normalizedFieldName(for elementName: String) -> String? {
        let localName = elementName.sonosXMLLocalName

        switch localName {
        case "roomName", "modelName", "friendlyName", "serialNum", "UDN":
            return localName
        default:
            return nil
        }
    }

    private func assign(_ value: String, to fieldName: String) {
        let trimmedValue = value.sonoicNonEmptyTrimmed
        guard let trimmedValue else {
            return
        }

        switch fieldName {
        case "roomName":
            if roomName == nil {
                roomName = trimmedValue
            }
        case "modelName":
            if modelName == nil {
                modelName = trimmedValue
            }
        case "friendlyName":
            if friendlyName == nil {
                friendlyName = trimmedValue
            }
        case "serialNum":
            if serialNumber == nil {
                serialNumber = trimmedValue
            }
        case "UDN":
            if udn == nil {
                udn = trimmedValue
            }
        default:
            break
        }
    }

}
