import Foundation

struct SonosMusicServicesClient {
    private let transport: SonosControlTransport
    private let descriptorParser = SonosMusicServiceDescriptorListParser()
    private let accountsParser = SonosMusicServiceAccountsParser()

    init(transport: SonosControlTransport = SonosControlTransport()) {
        self.transport = transport
    }

    func fetchProbeSnapshot(host: String) async throws -> SonosMusicServiceProbeSnapshot {
        let resolvedServiceList = try await fetchAvailableServices(host: host)
        let accounts = try await fetchAccounts(host: host)

        return SonosMusicServiceProbeSnapshot(
            observedAt: .now,
            serviceListVersion: resolvedServiceList.version,
            services: resolvedServiceList.services,
            accounts: accounts
        )
    }

    private func fetchAvailableServices(host: String) async throws -> AvailableServiceList {
        let data = try await transport.performAction(
            service: .musicServices,
            named: "ListAvailableServices",
            body: """
            <u:ListAvailableServices xmlns:u="\(SonosControlTransport.Service.musicServices.soapNamespace)">
            </u:ListAvailableServices>
            """,
            host: host
        )

        let values = try SonosSOAPValuesParser(
            expectedElements: [
                "AvailableServiceDescriptorList",
                "AvailableServiceListVersion",
            ]
        ).parse(data)
        let descriptorList = try requiredValue(named: "AvailableServiceDescriptorList", in: values)

        return AvailableServiceList(
            version: values["AvailableServiceListVersion"]?.sonoicNonEmptyTrimmed,
            services: try descriptorParser.parse(descriptorList)
        )
    }

    private func fetchAccounts(host: String) async throws -> [SonosMusicServiceAccountSummary] {
        let data = try await transport.performGET(resource: "/status/accounts", host: host)
        return try accountsParser.parse(data)
    }

    private func requiredValue(named elementName: String, in values: [String: String]) throws -> String {
        guard let value = values[elementName] else {
            throw SonosControlTransport.TransportError.missingValue(elementName)
        }

        return value
    }
}

private struct AvailableServiceList {
    var version: String?
    var services: [SonosMusicServiceDescriptor]
}

private final class SonosMusicServiceDescriptorListParser: NSObject, XMLParserDelegate {
    private var services: [SonosMusicServiceDescriptor] = []
    private var currentService: SonosMusicServiceDescriptor?

    func parse(_ xml: String) throws -> [SonosMusicServiceDescriptor] {
        services = []
        currentService = nil

        guard let data = xml.data(using: .utf8) else {
            throw SonosControlTransport.TransportError.invalidResponse
        }

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw parser.parserError ?? SonosControlTransport.TransportError.invalidResponse
        }

        return services
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        switch elementName.sonosXMLLocalName {
        case "Service":
            currentService = SonosMusicServiceDescriptor(
                id: attributeDict["Id"] ?? "",
                name: attributeDict["Name"] ?? "Unknown",
                uri: attributeDict["Uri"]?.sonoicNonEmptyTrimmed,
                secureURI: attributeDict["SecureUri"]?.sonoicNonEmptyTrimmed,
                containerType: attributeDict["ContainerType"]?.sonoicNonEmptyTrimmed,
                capabilities: attributeDict["Capabilities"]?.sonoicNonEmptyTrimmed,
                authPolicy: nil,
                presentationMapURI: nil,
                stringsURI: nil
            )
        case "Policy":
            currentService?.authPolicy = attributeDict["Auth"]?.sonoicNonEmptyTrimmed
        case "PresentationMap":
            currentService?.presentationMapURI = attributeDict["Uri"]?.sonoicNonEmptyTrimmed
        case "Strings":
            currentService?.stringsURI = attributeDict["Uri"]?.sonoicNonEmptyTrimmed
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
        guard elementName.sonosXMLLocalName == "Service",
              let currentService,
              !currentService.id.isEmpty
        else {
            return
        }

        services.append(currentService)
        self.currentService = nil
    }
}

private final class SonosMusicServiceAccountsParser: NSObject, XMLParserDelegate {
    private var accounts: [SonosMusicServiceAccountSummary] = []
    private var currentAccount: MutableAccount?
    private var capturedElementName: String?
    private var capturedValue = ""

    func parse(_ data: Data) throws -> [SonosMusicServiceAccountSummary] {
        accounts = []
        currentAccount = nil
        capturedElementName = nil
        capturedValue = ""

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw parser.parserError ?? SonosControlTransport.TransportError.invalidResponse
        }

        return accounts
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        let localName = elementName.sonosXMLLocalName

        if localName == "Account" {
            guard attributeDict["Deleted"] != "1" else {
                currentAccount = nil
                return
            }

            currentAccount = MutableAccount(
                serviceType: attributeDict["Type"] ?? "",
                serialNumber: attributeDict["SerialNum"] ?? ""
            )
            return
        }

        guard currentAccount != nil,
              ["UN", "NN", "OADevID", "Key"].contains(localName)
        else {
            return
        }

        capturedElementName = localName
        capturedValue = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard capturedElementName != nil else {
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
        let localName = elementName.sonosXMLLocalName

        if localName == "Account" {
            guard let currentAccount,
                  !currentAccount.serviceType.isEmpty,
                  !currentAccount.serialNumber.isEmpty
            else {
                self.currentAccount = nil
                return
            }

            accounts.append(currentAccount.summary)
            self.currentAccount = nil
            return
        }

        guard let capturedElementName,
              localName == capturedElementName
        else {
            return
        }

        currentAccount?.apply(value: capturedValue, for: capturedElementName)
        self.capturedElementName = nil
        capturedValue = ""
    }
}

private struct MutableAccount {
    var serviceType: String
    var serialNumber: String
    var nickname: String?
    var hasUsername = false
    var hasOAuthDeviceID = false
    var hasKey = false

    var summary: SonosMusicServiceAccountSummary {
        SonosMusicServiceAccountSummary(
            serviceType: serviceType,
            serialNumber: serialNumber,
            nickname: nickname,
            hasUsername: hasUsername,
            hasOAuthDeviceID: hasOAuthDeviceID,
            hasKey: hasKey
        )
    }

    mutating func apply(value: String, for elementName: String) {
        let trimmedValue = value.sonoicNonEmptyTrimmed

        switch elementName {
        case "UN":
            hasUsername = trimmedValue != nil
        case "NN":
            nickname = trimmedValue
        case "OADevID":
            hasOAuthDeviceID = trimmedValue != nil
        case "Key":
            hasKey = trimmedValue != nil
        default:
            break
        }
    }
}
