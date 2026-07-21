import Foundation
import SwanSongKit

private final class EngineService: NSObject, SwanSongEngineServiceProtocol {
    private let lock = NSRecursiveLock()
    private var engine: EngineSession?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func capability(withReply reply: @escaping (Data?, String?) -> Void) {
        locked {
            returning(reply) {
                let engine = try EngineSession()
                return try encoder.encode(
                    SwanSongEngineServiceCapability(
                        protocolVersion: SwanSongEngineServiceContract.protocolVersion,
                        backendName: engine.backendName,
                        buildID: engine.buildID,
                        abiVersion: engine.abiVersion,
                        capabilitiesRaw: engine.capabilities.rawValue
                    )
                )
            }
        }
    }

    func configure(_ configuration: Data, withReply reply: @escaping (String?) -> Void) {
        locked {
            completing(reply) {
                guard configuration.count <= 16 * 1_024 else {
                    throw ServiceError.invalidPayload
                }
                let decoded = try decoder.decode(
                    SwanSongEngineServiceConfiguration.self,
                    from: configuration
                )
                guard decoded.protocolVersion
                        == SwanSongEngineServiceContract.protocolVersion,
                      (8_000 ... 192_000).contains(decoded.sampleRate) else {
                    throw ServiceError.invalidPayload
                }
                engine = try EngineSession(
                    sampleRate: decoded.sampleRate,
                    rtcMode: decoded.rtcMode,
                    hardwareModel: decoded.hardwareModel
                )
            }
        }
    }

    func loadROM(_ rom: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        locked {
            returning(reply) {
                guard rom.count >= GameROMValidationPolicy.minimumByteCount,
                      rom.count <= SwanSongEngineServiceContract.maximumROMBytes else {
                    throw ServiceError.invalidPayload
                }
                return try encoder.encode(try requireEngine().load(rom: rom))
            }
        }
    }

    func stagePersistence(_ persistence: Data, withReply reply: @escaping (String?) -> Void) {
        locked {
            completing(reply) {
                guard persistence.count
                        <= SwanSongEngineServiceContract.maximumPersistenceBytes else {
                    throw ServiceError.invalidPayload
                }
                try requireEngine().stagePersistence(
                    try decoder.decode(EnginePersistence.self, from: persistence)
                )
            }
        }
    }

    func nextFrame(
        inputRawValue: UInt32,
        withReply reply: @escaping (Data?, String?) -> Void
    ) {
        locked {
            returning(reply) {
                let engine = try requireEngine()
                try engine.setInput(EngineInput(rawValue: inputRawValue))
                try engine.runFrame()
                return try encoder.encode(
                    SwanSongEngineFramePacket(
                        video: try engine.videoFrame(),
                        audio: try engine.audioBatch()
                    )
                )
            }
        }
    }

    func reset(withReply reply: @escaping (String?) -> Void) {
        locked { completing(reply) { try requireEngine().reset() } }
    }

    func capturePersistence(withReply reply: @escaping (Data?, String?) -> Void) {
        locked {
            returning(reply) {
                try encoder.encode(try requireEngine().capturePersistence())
            }
        }
    }

    func captureState(withReply reply: @escaping (Data?, String?) -> Void) {
        locked {
            returning(reply) {
                let state = try requireEngine().captureState()
                guard state.count <= SwanSongEngineServiceContract.maximumStateBytes else {
                    throw ServiceError.invalidPayload
                }
                return state
            }
        }
    }

    func captureMemory(
        _ region: String,
        withReply reply: @escaping (Data?, String?) -> Void
    ) {
        locked {
            returning(reply) {
                guard let region = EngineMemoryRegion(rawValue: region) else {
                    throw ServiceError.invalidPayload
                }
                return try requireEngine().captureMemory(region)
            }
        }
    }

    func restoreState(_ state: Data, withReply reply: @escaping (String?) -> Void) {
        locked {
            completing(reply) {
                guard !state.isEmpty,
                      state.count <= SwanSongEngineServiceContract.maximumStateBytes else {
                    throw ServiceError.invalidPayload
                }
                try requireEngine().restoreState(state)
            }
        }
    }

    func stop(withReply reply: @escaping (String?) -> Void) {
        locked {
            completing(reply) {
                if let engine { try engine.unload() }
                engine = nil
            }
        }
    }

    private func locked(_ operation: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        operation()
    }

    private func requireEngine() throws -> EngineSession {
        guard let engine else { throw ServiceError.notConfigured }
        return engine
    }

    private func completing(
        _ reply: @escaping (String?) -> Void,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            reply(nil)
        } catch {
            reply(error.localizedDescription)
        }
    }

    private func returning(
        _ reply: @escaping (Data?, String?) -> Void,
        operation: () throws -> Data
    ) {
        do {
            reply(try operation(), nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }
}

private enum ServiceError: LocalizedError {
    case invalidPayload
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidPayload: "The isolated engine rejected an invalid payload."
        case .notConfigured: "The isolated engine session is not configured."
        }
    }
}

private final class EngineServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let service = EngineService()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(
            with: SwanSongEngineServiceProtocol.self
        )
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

private let delegate = EngineServiceDelegate()
private let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
