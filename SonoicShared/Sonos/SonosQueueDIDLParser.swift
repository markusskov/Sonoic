import Foundation

final class SonosQueueDIDLParser: NSObject, XMLParserDelegate {
    private struct PartialItem {
        var id: String?
        var title: String?
        var artistName: String?
        var albumTitle: String?
        var artworkURL: String?
        var duration: TimeInterval?
    }

    private var items: [SonosQueueItem] = []
    private var currentItem: PartialItem?
    private var currentFieldName: String?
    private var capturedValue = ""

    func parse(_ xmlString: String) throws -> [SonosQueueItem] {
        items = []
        currentItem = nil
        currentFieldName = nil
        capturedValue = ""

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
        let localName = localName(for: qName ?? elementName)

        if localName == "item" {
            currentItem = PartialItem(id: attributeDict["id"].sonoicNonEmptyTrimmed)
            return
        }

        guard currentItem != nil,
              let fieldName = normalizedFieldName(for: localName)
        else {
            return
        }

        currentFieldName = fieldName
        capturedValue = ""

        if fieldName == "res" {
            currentItem?.duration = parseDuration(from: attributeDict["duration"])
        }
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
        let localName = localName(for: qName ?? elementName)

        if let currentFieldName,
           normalizedFieldName(for: localName) == currentFieldName
        {
            assign(capturedValue, to: currentFieldName)
            self.currentFieldName = nil
        }

        guard localName == "item",
              let currentItem
        else {
            return
        }

        items.append(
            SonosQueueItem(
                id: currentItem.id ?? "queue-item-\(items.count + 1)",
                title: currentItem.title ?? "Unknown Track",
                artistName: currentItem.artistName,
                albumTitle: currentItem.albumTitle,
                artworkURL: currentItem.artworkURL,
                duration: currentItem.duration
            )
        )
        self.currentItem = nil
    }

    private func localName(for elementName: String) -> String {
        elementName.split(separator: ":").last.map(String.init) ?? elementName
    }

    private func normalizedFieldName(for elementName: String) -> String? {
        switch elementName {
        case "title", "creator", "artist", "album", "albumArtURI", "res":
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
        default:
            break
        }
    }

    private func parseDuration(from value: String?) -> TimeInterval? {
        guard let value = value.sonoicNonEmptyTrimmed, value != "NOT_IMPLEMENTED" else {
            return nil
        }

        let components = value.split(separator: ":")
        guard components.count == 3,
              let hours = Int(components[0]),
              let minutes = Int(components[1]),
              let seconds = Int(components[2])
        else {
            return nil
        }

        return TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }
}
