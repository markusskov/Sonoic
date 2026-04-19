extension String {
    nonisolated var sonosXMLLocalName: String {
        split(separator: ":").last.map(String.init) ?? self
    }
}
