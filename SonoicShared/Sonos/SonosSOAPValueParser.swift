import Foundation

final class SonosSOAPValueParser: NSObject, XMLParserDelegate {
    private let expectedElement: String
    private var capturedValue = ""
    private var parsedValue: String?
    private var isCapturingValue = false

    init(expectedElement: String) {
        self.expectedElement = expectedElement
    }

    func parse(_ data: Data) throws -> String {
        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw parser.parserError ?? SonosControlTransport.TransportError.invalidResponse
        }

        guard let parsedValue else {
            throw SonosControlTransport.TransportError.missingValue(expectedElement)
        }

        return parsedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        guard matches(elementName) || matches(qName) else {
            return
        }

        capturedValue = ""
        isCapturingValue = true
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isCapturingValue else {
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
        guard isCapturingValue, matches(elementName) || matches(qName) else {
            return
        }

        parsedValue = capturedValue
        isCapturingValue = false
    }

    private func matches(_ elementName: String?) -> Bool {
        guard let elementName else {
            return false
        }

        return elementName.sonosXMLLocalName == expectedElement
    }
}
