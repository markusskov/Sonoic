import Foundation

struct SonosRenderingControlClient {
    enum ClientError: LocalizedError {
        case invalidVolume(String)
        case invalidMute(String)
        case invalidHomeTheaterValue(name: String, value: String)

        var errorDescription: String? {
            switch self {
            case let .invalidVolume(value):
                "The Sonos player returned an invalid volume value: \(value)."
            case let .invalidMute(value):
                "The Sonos player returned an invalid mute value: \(value)."
            case let .invalidHomeTheaterValue(name, value):
                "The Sonos player returned an invalid \(name) value: \(value)."
            }
        }
    }

    enum EQType: String {
        case subGain = "SubGain"
        case speechEnhanceEnabled = "SpeechEnhanceEnabled"
        case dialogLevel = "DialogLevel"
        case nightMode = "NightMode"
    }

    private let transport: SonosControlTransport

    init(transport: SonosControlTransport = SonosControlTransport()) {
        self.transport = transport
    }

    func fetchVolume(host: String) async throws -> SonoicExternalControlState.Volume {
        async let volumeLevel = fetchVolumeLevel(host: host)
        async let isMuted = fetchMuteState(host: host)
        return try await SonoicExternalControlState.Volume(level: volumeLevel, isMuted: isMuted)
    }

    func setMute(host: String, isMuted: Bool) async throws {
        _ = try await transport.performAction(
            service: .renderingControl,
            named: "SetMute",
            body: """
            <u:SetMute xmlns:u="\(SonosControlTransport.Service.renderingControl.soapNamespace)">
              <InstanceID>0</InstanceID>
              <Channel>Master</Channel>
              <DesiredMute>\(isMuted ? "1" : "0")</DesiredMute>
            </u:SetMute>
            """,
            host: host
        )
    }

    func setVolume(host: String, level: Int) async throws {
        let boundedLevel = min(max(level, 0), 100)

        _ = try await transport.performAction(
            service: .renderingControl,
            named: "SetVolume",
            body: """
            <u:SetVolume xmlns:u="\(SonosControlTransport.Service.renderingControl.soapNamespace)">
              <InstanceID>0</InstanceID>
              <Channel>Master</Channel>
              <DesiredVolume>\(boundedLevel)</DesiredVolume>
            </u:SetVolume>
            """,
            host: host
        )
    }

    func fetchHomeTheaterSettings(host: String) async throws -> SonosHomeTheaterSettings {
        async let bass = fetchBass(host: host)
        async let treble = fetchTreble(host: host)
        async let loudness = fetchLoudness(host: host)
        async let subLevel = fetchOptionalIntegerEQ(
            host: host,
            type: .subGain,
            range: SonosHomeTheaterSettings.subLevelRange
        )
        async let speechEnhancementEnabled = fetchOptionalSpeechEnhancementEnabled(host: host)
        async let dialogLevel = fetchOptionalDialogLevel(host: host)
        async let nightSoundEnabled = fetchOptionalBoolEQ(host: host, type: .nightMode)

        return try await SonosHomeTheaterSettings(
            bass: bass,
            treble: treble,
            loudness: loudness,
            subLevel: subLevel,
            speechEnhancementEnabled: speechEnhancementEnabled,
            dialogLevel: dialogLevel,
            nightSoundEnabled: nightSoundEnabled
        )
    }

    func setBass(host: String, level: Int) async throws {
        let boundedLevel = Self.bounded(level, in: SonosHomeTheaterSettings.toneRange)

        _ = try await transport.performAction(
            service: .renderingControl,
            named: "SetBass",
            body: """
            <u:SetBass xmlns:u="\(SonosControlTransport.Service.renderingControl.soapNamespace)">
              <InstanceID>0</InstanceID>
              <DesiredBass>\(boundedLevel)</DesiredBass>
            </u:SetBass>
            """,
            host: host
        )
    }

    func setTreble(host: String, level: Int) async throws {
        let boundedLevel = Self.bounded(level, in: SonosHomeTheaterSettings.toneRange)

        _ = try await transport.performAction(
            service: .renderingControl,
            named: "SetTreble",
            body: """
            <u:SetTreble xmlns:u="\(SonosControlTransport.Service.renderingControl.soapNamespace)">
              <InstanceID>0</InstanceID>
              <DesiredTreble>\(boundedLevel)</DesiredTreble>
            </u:SetTreble>
            """,
            host: host
        )
    }

    func setLoudness(host: String, isEnabled: Bool) async throws {
        _ = try await transport.performAction(
            service: .renderingControl,
            named: "SetLoudness",
            body: """
            <u:SetLoudness xmlns:u="\(SonosControlTransport.Service.renderingControl.soapNamespace)">
              <InstanceID>0</InstanceID>
              <Channel>Master</Channel>
              <DesiredLoudness>\(Self.soapBool(isEnabled))</DesiredLoudness>
            </u:SetLoudness>
            """,
            host: host
        )
    }

    func setSubLevel(host: String, level: Int) async throws {
        try await setEQ(
            host: host,
            type: .subGain,
            value: "\(Self.bounded(level, in: SonosHomeTheaterSettings.subLevelRange))"
        )
    }

    func setSpeechEnhancement(host: String, isEnabled: Bool) async throws {
        do {
            try await setEQ(
                host: host,
                type: .speechEnhanceEnabled,
                value: Self.soapBool(isEnabled)
            )
        } catch {
            try await setEQ(
                host: host,
                type: .dialogLevel,
                value: Self.soapBool(isEnabled)
            )
        }
    }

    func setDialogLevel(host: String, level: Int) async throws {
        try await setEQ(
            host: host,
            type: .dialogLevel,
            value: "\(Self.bounded(level, in: SonosHomeTheaterSettings.dialogLevelRange))"
        )
    }

    func setNightSound(host: String, isEnabled: Bool) async throws {
        try await setEQ(host: host, type: .nightMode, value: Self.soapBool(isEnabled))
    }

    private func fetchVolumeLevel(host: String) async throws -> Int {
        let data = try await transport.performAction(
            service: .renderingControl,
            named: "GetVolume",
            body: """
            <u:GetVolume xmlns:u="\(SonosControlTransport.Service.renderingControl.soapNamespace)">
              <InstanceID>0</InstanceID>
              <Channel>Master</Channel>
            </u:GetVolume>
            """,
            host: host
        )

        let value = try SonosSOAPValueParser(expectedElement: "CurrentVolume").parse(data)
        guard let level = Int(value), (0...100).contains(level) else {
            throw ClientError.invalidVolume(value)
        }

        return level
    }

    private func fetchMuteState(host: String) async throws -> Bool {
        let data = try await transport.performAction(
            service: .renderingControl,
            named: "GetMute",
            body: """
            <u:GetMute xmlns:u="\(SonosControlTransport.Service.renderingControl.soapNamespace)">
              <InstanceID>0</InstanceID>
              <Channel>Master</Channel>
            </u:GetMute>
            """,
            host: host
        )

        let value = try SonosSOAPValueParser(expectedElement: "CurrentMute").parse(data)

        return switch value {
        case "0":
            false
        case "1":
            true
        default:
            throw ClientError.invalidMute(value)
        }
    }

    private func fetchBass(host: String) async throws -> Int {
        let data = try await transport.performAction(
            service: .renderingControl,
            named: "GetBass",
            body: """
            <u:GetBass xmlns:u="\(SonosControlTransport.Service.renderingControl.soapNamespace)">
              <InstanceID>0</InstanceID>
            </u:GetBass>
            """,
            host: host
        )

        return try parseInteger(
            try SonosSOAPValueParser(expectedElement: "CurrentBass").parse(data),
            name: "bass",
            range: SonosHomeTheaterSettings.toneRange
        )
    }

    private func fetchTreble(host: String) async throws -> Int {
        let data = try await transport.performAction(
            service: .renderingControl,
            named: "GetTreble",
            body: """
            <u:GetTreble xmlns:u="\(SonosControlTransport.Service.renderingControl.soapNamespace)">
              <InstanceID>0</InstanceID>
            </u:GetTreble>
            """,
            host: host
        )

        return try parseInteger(
            try SonosSOAPValueParser(expectedElement: "CurrentTreble").parse(data),
            name: "treble",
            range: SonosHomeTheaterSettings.toneRange
        )
    }

    private func fetchLoudness(host: String) async throws -> Bool {
        let data = try await transport.performAction(
            service: .renderingControl,
            named: "GetLoudness",
            body: """
            <u:GetLoudness xmlns:u="\(SonosControlTransport.Service.renderingControl.soapNamespace)">
              <InstanceID>0</InstanceID>
              <Channel>Master</Channel>
            </u:GetLoudness>
            """,
            host: host
        )

        return try parseBool(
            try SonosSOAPValueParser(expectedElement: "CurrentLoudness").parse(data),
            name: "loudness"
        )
    }

    private func fetchOptionalSpeechEnhancementEnabled(host: String) async -> Bool? {
        if let explicitValue = await fetchOptionalBoolEQ(host: host, type: .speechEnhanceEnabled) {
            return explicitValue
        }

        guard let dialogValue = await fetchOptionalEQValue(host: host, type: .dialogLevel) else {
            return nil
        }

        return try? parseBool(dialogValue, name: "speech enhancement")
    }

    private func fetchOptionalDialogLevel(host: String) async -> Int? {
        guard await fetchOptionalBoolEQ(host: host, type: .speechEnhanceEnabled) != nil,
              let value = await fetchOptionalEQValue(host: host, type: .dialogLevel)
        else {
            return nil
        }

        return try? parseInteger(
            value,
            name: "dialog level",
            range: SonosHomeTheaterSettings.dialogLevelRange
        )
    }

    private func fetchOptionalIntegerEQ(host: String, type: EQType, range: ClosedRange<Int>) async -> Int? {
        guard let value = await fetchOptionalEQValue(host: host, type: type) else {
            return nil
        }

        return try? parseInteger(value, name: type.rawValue, range: range)
    }

    private func fetchOptionalBoolEQ(host: String, type: EQType) async -> Bool? {
        guard let value = await fetchOptionalEQValue(host: host, type: type) else {
            return nil
        }

        return try? parseBool(value, name: type.rawValue)
    }

    private func fetchOptionalEQValue(host: String, type: EQType) async -> String? {
        do {
            return try await fetchEQ(host: host, type: type)
        } catch {
            return nil
        }
    }

    private func fetchEQ(host: String, type: EQType) async throws -> String {
        let data = try await transport.performAction(
            service: .renderingControl,
            named: "GetEQ",
            body: """
            <u:GetEQ xmlns:u="\(SonosControlTransport.Service.renderingControl.soapNamespace)">
              <InstanceID>0</InstanceID>
              <EQType>\(type.rawValue)</EQType>
            </u:GetEQ>
            """,
            host: host
        )

        return try SonosSOAPValueParser(expectedElement: "CurrentValue").parse(data)
    }

    private func setEQ(host: String, type: EQType, value: String) async throws {
        _ = try await transport.performAction(
            service: .renderingControl,
            named: "SetEQ",
            body: """
            <u:SetEQ xmlns:u="\(SonosControlTransport.Service.renderingControl.soapNamespace)">
              <InstanceID>0</InstanceID>
              <EQType>\(type.rawValue)</EQType>
              <DesiredValue>\(value)</DesiredValue>
            </u:SetEQ>
            """,
            host: host
        )
    }

    private func parseInteger(_ value: String, name: String, range: ClosedRange<Int>) throws -> Int {
        guard let parsedValue = Int(value), range.contains(parsedValue) else {
            throw ClientError.invalidHomeTheaterValue(name: name, value: value)
        }

        return parsedValue
    }

    private func parseBool(_ value: String, name: String) throws -> Bool {
        switch value {
        case "0":
            return false
        case "1":
            return true
        default:
            throw ClientError.invalidHomeTheaterValue(name: name, value: value)
        }
    }

    private static func bounded(_ value: Int, in range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func soapBool(_ value: Bool) -> String {
        value ? "1" : "0"
    }
}
