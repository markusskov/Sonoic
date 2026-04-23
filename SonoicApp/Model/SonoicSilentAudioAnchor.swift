import Foundation

struct SonoicSilentAudioAnchor {
    nonisolated private static let anchorDurationSeconds = 60 * 60
    nonisolated(unsafe) private let fileManager: FileManager

    nonisolated init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    nonisolated func fileURL() throws -> URL {
        let cachesDirectoryURL = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let fileURL = cachesDirectoryURL.appending(path: "sonoic-silence-anchor-\(Self.anchorDurationSeconds)s.wav")

        if !fileManager.fileExists(atPath: fileURL.path()) {
            try makeSilentWaveData().write(to: fileURL, options: .atomic)
        }

        return fileURL
    }

    nonisolated private func makeSilentWaveData() -> Data {
        let sampleRate = 8_000
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 8
        let durationSeconds = Self.anchorDurationSeconds
        let bytesPerSample = Int(bitsPerSample / 8)
        let dataByteCount = sampleRate * durationSeconds * Int(channelCount) * bytesPerSample
        let byteRate = sampleRate * Int(channelCount) * bytesPerSample
        let blockAlign = channelCount * UInt16(bytesPerSample)

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(littleEndian: UInt32(36 + dataByteCount))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(littleEndian: UInt32(16))
        data.append(littleEndian: UInt16(1))
        data.append(littleEndian: channelCount)
        data.append(littleEndian: UInt32(sampleRate))
        data.append(littleEndian: UInt32(byteRate))
        data.append(littleEndian: blockAlign)
        data.append(littleEndian: bitsPerSample)
        data.append(contentsOf: "data".utf8)
        data.append(littleEndian: UInt32(dataByteCount))
        data.append(Data(repeating: 128, count: dataByteCount))
        return data
    }
}

private extension Data {
    nonisolated mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { buffer in
            append(buffer.bindMemory(to: UInt8.self))
        }
    }
}
