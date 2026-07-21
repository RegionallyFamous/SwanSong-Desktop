import Foundation

public enum SwanSongEngineServiceContract {
    public static let serviceName = "3J8H48TP7P.com.regionallyfamous.swansong.engine-service"
    public static let protocolVersion = 1
    public static let maximumROMBytes = 16 * 1_024 * 1_024
    public static let maximumStateBytes = 64 * 1_024 * 1_024
    public static let maximumPersistenceBytes = 32 * 1_024 * 1_024
}

public struct SwanSongEngineServiceConfiguration: Codable, Sendable {
    public let protocolVersion: Int
    public let sampleRate: UInt32
    public let rtcMode: EngineRTCMode
    public let hardwareModel: EngineHardwareModel

    public init(
        sampleRate: UInt32,
        rtcMode: EngineRTCMode,
        hardwareModel: EngineHardwareModel
    ) {
        protocolVersion = SwanSongEngineServiceContract.protocolVersion
        self.sampleRate = sampleRate
        self.rtcMode = rtcMode
        self.hardwareModel = hardwareModel
    }
}

public struct SwanSongEngineServiceCapability: Codable, Sendable {
    public let protocolVersion: Int
    public let backendName: String
    public let buildID: String
    public let abiVersion: UInt32
    public let capabilitiesRaw: UInt64

    public init(
        protocolVersion: Int,
        backendName: String,
        buildID: String,
        abiVersion: UInt32,
        capabilitiesRaw: UInt64
    ) {
        self.protocolVersion = protocolVersion
        self.backendName = backendName
        self.buildID = buildID
        self.abiVersion = abiVersion
        self.capabilitiesRaw = capabilitiesRaw
    }
}

public struct SwanSongEngineFramePacket: Codable, Sendable {
    public let video: EngineVideoFrame
    public let audio: EngineAudioBatch

    public init(video: EngineVideoFrame, audio: EngineAudioBatch) {
        self.video = video
        self.audio = audio
    }
}

/// Data-only Objective-C surface for the embedded engine XPC service. Every
/// payload is size-checked and decoded into a versioned Codable contract on
/// either side; no arbitrary object classes cross the process boundary.
@objc public protocol SwanSongEngineServiceProtocol {
    func capability(withReply reply: @escaping (Data?, String?) -> Void)
    func configure(_ configuration: Data, withReply reply: @escaping (String?) -> Void)
    func loadROM(_ rom: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func stagePersistence(_ persistence: Data, withReply reply: @escaping (String?) -> Void)
    func nextFrame(inputRawValue: UInt32, withReply reply: @escaping (Data?, String?) -> Void)
    func reset(withReply reply: @escaping (String?) -> Void)
    func capturePersistence(withReply reply: @escaping (Data?, String?) -> Void)
    func captureState(withReply reply: @escaping (Data?, String?) -> Void)
    func captureMemory(_ region: String, withReply reply: @escaping (Data?, String?) -> Void)
    func restoreState(_ state: Data, withReply reply: @escaping (String?) -> Void)
    func stop(withReply reply: @escaping (String?) -> Void)
}
