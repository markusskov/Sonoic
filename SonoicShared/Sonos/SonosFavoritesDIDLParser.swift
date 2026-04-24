import Foundation

final class SonosFavoritesDIDLParser: NSObject, XMLParserDelegate {
    private struct PartialItem {
        var id: String?
        var kind: SonosFavoriteItem.Kind = .item
        var title: String?
        var artistName: String?
        var albumTitle: String?
        var artworkURL: String?
        var playbackURI: String?
        var playbackMetadataXML: String?
        var service: SonosServiceDescriptor?
    }

    private static let didlNamespaces = """
    xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" \
    xmlns:dc="http://purl.org/dc/elements/1.1/" \
    xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
    xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"
    """

    private var items: [SonosFavoriteItem] = []
    private var currentItem: PartialItem?
    private var currentItemElementName: String?
    private var currentFieldName: String?
    private var capturedValue = ""
    private var currentItemXML = ""

    func parse(_ xmlString: String) throws -> [SonosFavoriteItem] {
        items = []
        currentItem = nil
        currentItemElementName = nil
        currentFieldName = nil
        capturedValue = ""
        currentItemXML = ""

        guard xmlString.sonoicNonEmptyTrimmed != nil else {
            return []
        }

        let parser = XMLParser(data: Data(xmlString.utf8))
        parser.delegate = self

        guard parser.parse() else {
            throw parser.parserError ?? SonosControlTransport.TransportError.invalidResponse
        }

        return items
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        let rawElementName = qName ?? elementName
        let localName = rawElementName.sonosXMLLocalName

        if localName == "item" || localName == "container" {
            currentItem = PartialItem(
                id: attributeDict["id"].sonoicNonEmptyTrimmed,
                kind: localName == "container" ? .collection : .item
            )
            currentItemElementName = localName
            currentItemXML = openingTag(named: rawElementName, attributes: attributeDict)
            return
        }

        guard currentItem != nil else {
            return
        }

        currentItemXML.append(openingTag(named: rawElementName, attributes: attributeDict))

        guard let fieldName = normalizedFieldName(for: localName) else {
            return
        }

        currentFieldName = fieldName
        capturedValue = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentItem != nil else {
            return
        }

        currentItemXML.append(escapedXMLValue(string))

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
        let rawElementName = qName ?? elementName
        let localName = rawElementName.sonosXMLLocalName

        guard currentItem != nil else {
            return
        }

        if let currentFieldName,
           normalizedFieldName(for: localName) == currentFieldName
        {
            assign(capturedValue, to: currentFieldName)
            self.currentFieldName = nil
        }

        currentItemXML.append(closingTag(named: rawElementName))

        guard localName == currentItemElementName,
              let currentItem
        else {
            return
        }

        guard let playbackURI = currentItem.playbackURI?.sonoicNonEmptyTrimmed else {
            resetCurrentItem()
            return
        }

        items.append(
            SonosFavoriteItem(
                id: currentItem.id ?? "favorite-\(items.count + 1)",
                title: currentItem.title ?? "Untitled Favorite",
                subtitle: subtitle(for: currentItem),
                artworkURL: currentItem.artworkURL,
                service: currentItem.service ?? SonosServiceCatalog.descriptor(from: playbackURI),
                playbackURI: playbackURI,
                playbackMetadataXML: playbackMetadataXML(for: currentItem),
                kind: currentItem.kind
            )
        )

        resetCurrentItem()
    }

    private func normalizedFieldName(for elementName: String) -> String? {
        switch elementName {
        case "title", "creator", "artist", "album", "albumArtURI", "res", "resMD", "description":
            return elementName
        default:
            return nil
        }
    }

    private func assign(_ value: String, to fieldName: String) {
        guard let value = value.sonoicNonEmptyTrimmed else {
            return
        }

        switch fieldName {
        case "title":
            if currentItem?.title == nil {
                currentItem?.title = value
            }
        case "creator", "artist":
            if currentItem?.artistName == nil {
                currentItem?.artistName = value
            }
        case "album":
            if currentItem?.albumTitle == nil {
                currentItem?.albumTitle = value
            }
        case "albumArtURI":
            if currentItem?.artworkURL == nil {
                currentItem?.artworkURL = value
            }
        case "res":
            if currentItem?.playbackURI == nil {
                currentItem?.playbackURI = value
            }
        case "resMD":
            if currentItem?.playbackMetadataXML == nil {
                currentItem?.playbackMetadataXML = value
            }
        case "description":
            if currentItem?.service == nil {
                currentItem?.service = SonosServiceCatalog.descriptor(named: value)
            }
        default:
            break
        }
    }

    private func subtitle(for item: PartialItem) -> String? {
        var parts: [String] = []

        if let artistName = item.artistName?.sonoicNonEmptyTrimmed {
            parts.append(artistName)
        }

        if let albumTitle = item.albumTitle?.sonoicNonEmptyTrimmed, !parts.contains(albumTitle) {
            parts.append(albumTitle)
        }

        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: " • ")
    }

    private func wrappedDIDL(for itemXML: String) -> String {
        """
        <DIDL-Lite \(Self.didlNamespaces)>
        \(itemXML)
        </DIDL-Lite>
        """
    }

    private func playbackMetadataXML(for item: PartialItem) -> String {
        if let playbackMetadataXML = item.playbackMetadataXML?.sonoicNonEmptyTrimmed {
            if playbackMetadataXML.localizedCaseInsensitiveContains("<DIDL-Lite") {
                return playbackMetadataXML
            }

            return wrappedDIDL(for: playbackMetadataXML)
        }

        return wrappedDIDL(for: currentItemXML)
    }

    private func resetCurrentItem() {
        currentItem = nil
        currentItemElementName = nil
        currentFieldName = nil
        capturedValue = ""
        currentItemXML = ""
    }

    private func openingTag(named name: String, attributes: [String: String]) -> String {
        let serializedAttributes = attributes
            .map { key, value in
                " \(key)=\"\(escapedXMLValue(value))\""
            }
            .sorted()
            .joined()
        return "<\(name)\(serializedAttributes)>"
    }

    private func closingTag(named name: String) -> String {
        "</\(name)>"
    }

    private func escapedXMLValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
