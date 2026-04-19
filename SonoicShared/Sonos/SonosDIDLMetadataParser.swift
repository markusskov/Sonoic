import Foundation

struct SonosDIDLMetadata: Equatable {
    var title: String?
    var artistName: String?
    var albumTitle: String?
    var albumArtURI: String?

    var isEmpty: Bool {
        title == nil && artistName == nil && albumTitle == nil && albumArtURI == nil
    }
}

final class SonosDIDLMetadataParser: NSObject, XMLParserDelegate {
    private var metadata = SonosDIDLMetadata()
    private var currentFieldName: String?
    private var capturedValue = ""

    func parse(_ xmlString: String) throws -> SonosDIDLMetadata {
        metadata = SonosDIDLMetadata()
        currentFieldName = nil
        capturedValue = ""

        let parser = XMLParser(data: Data(xmlString.utf8))
        parser.delegate = self

        guard parser.parse() else {
            throw parser.parserError ?? SonosControlTransport.TransportError.invalidResponse
        }

        return metadata
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
        case "title", "creator", "artist", "album", "albumArtURI":
            return localName
        default:
            return nil
        }
    }

    private func assign(_ value: String, to fieldName: String) {
        guard let trimmedValue = value.sonoicNonEmptyTrimmed else {
            return
        }

        switch fieldName {
        case "title":
            if metadata.title == nil {
                metadata.title = trimmedValue
            }
        case "creator", "artist":
            if metadata.artistName == nil {
                metadata.artistName = trimmedValue
            }
        case "album":
            if metadata.albumTitle == nil {
                metadata.albumTitle = trimmedValue
            }
        case "albumArtURI":
            if metadata.albumArtURI == nil {
                metadata.albumArtURI = trimmedValue
            }
        default:
            break
        }
    }
}
