import Foundation

final class SonosSOAPValuesParser: NSObject, XMLParserDelegate {
    private let expectedElements: Set<String>
    private var parsedValues: [String: String] = [:]
    private var capturedValue = ""
    private var capturingElementName: String?

    init(expectedElements: Set<String>) {
        self.expectedElements = expectedElements
    }

    func parse(_ data: Data) throws -> [String: String] {
        parsedValues = [:]
        capturedValue = ""
        capturingElementName = nil

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw parser.parserError ?? SonosControlTransport.TransportError.invalidResponse
        }

        return parsedValues
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        let localName = normalizedElementName(for: qName ?? elementName)
        guard expectedElements.contains(localName),
              parsedValues[localName] == nil
        else {
            return
        }

        capturingElementName = localName
        capturedValue = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard capturingElementName != nil else {
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
        guard let capturingElementName else {
            return
        }

        let localName = normalizedElementName(for: qName ?? elementName)
        guard localName == capturingElementName else {
            return
        }

        if let parsedValue = capturedValue.sonoicNonEmptyTrimmed {
            parsedValues[capturingElementName] = parsedValue
        }

        self.capturingElementName = nil
    }

    private func normalizedElementName(for elementName: String) -> String {
        elementName.sonosXMLLocalName
    }
}
