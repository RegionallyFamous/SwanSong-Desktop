import Foundation

public final class SwanSongEngineServiceClient: @unchecked Sendable {
    public static var isEmbeddedServiceAvailable: Bool {
        let service = Bundle.main.bundleURL
            .appendingPathComponent("Contents/XPCServices", isDirectory: true)
            .appendingPathComponent("SwanSongEngineService.xpc", isDirectory: true)
        return FileManager.default.fileExists(atPath: service.path)
    }

    private let connection: NSXPCConnection
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {
        connection = NSXPCConnection(
            serviceName: SwanSongEngineServiceContract.serviceName
        )
        connection.remoteObjectInterface = NSXPCInterface(
            with: SwanSongEngineServiceProtocol.self
        )
        connection.resume()
    }

    deinit { connection.invalidate() }

    public func capability() async throws -> SwanSongEngineServiceCapability {
        let data = try await dataReply { $0.capability(withReply: $1) }
        return try decoder.decode(SwanSongEngineServiceCapability.self, from: data)
    }

    public func configure(_ configuration: SwanSongEngineServiceConfiguration) async throws {
        let data = try encoder.encode(configuration)
        try await emptyReply { $0.configure(data, withReply: $1) }
    }

    public func load(rom: Data) async throws -> ROMMetadata {
        guard rom.count <= SwanSongEngineServiceContract.maximumROMBytes else {
            throw SwanSongEngineServiceClientError.invalidPayload
        }
        let data = try await dataReply { $0.loadROM(rom, withReply: $1) }
        return try decoder.decode(ROMMetadata.self, from: data)
    }

    public func stagePersistence(_ persistence: EnginePersistence) async throws {
        let data = try encoder.encode(persistence)
        guard data.count <= SwanSongEngineServiceContract.maximumPersistenceBytes else {
            throw SwanSongEngineServiceClientError.invalidPayload
        }
        try await emptyReply { $0.stagePersistence(data, withReply: $1) }
    }

    public func nextFrame(input: EngineInput) async throws -> SwanSongEngineFramePacket {
        let data = try await dataReply {
            $0.nextFrame(inputRawValue: input.rawValue, withReply: $1)
        }
        return try decoder.decode(SwanSongEngineFramePacket.self, from: data)
    }

    public func reset() async throws {
        try await emptyReply { $0.reset(withReply: $1) }
    }

    public func capturePersistence() async throws -> EnginePersistence {
        let data = try await dataReply { $0.capturePersistence(withReply: $1) }
        return try decoder.decode(EnginePersistence.self, from: data)
    }

    public func captureState() async throws -> Data {
        let data = try await dataReply { $0.captureState(withReply: $1) }
        guard data.count <= SwanSongEngineServiceContract.maximumStateBytes else {
            throw SwanSongEngineServiceClientError.invalidPayload
        }
        return data
    }

    public func captureMemory(_ region: EngineMemoryRegion) async throws -> Data {
        try await dataReply { $0.captureMemory(region.rawValue, withReply: $1) }
    }

    public func restoreState(_ state: Data) async throws {
        guard !state.isEmpty,
              state.count <= SwanSongEngineServiceContract.maximumStateBytes else {
            throw SwanSongEngineServiceClientError.invalidPayload
        }
        try await emptyReply { $0.restoreState(state, withReply: $1) }
    }

    public func stop() async throws {
        try await emptyReply { $0.stop(withReply: $1) }
        connection.invalidate()
    }

    private func proxy(
        errorHandler: @escaping @Sendable (Error) -> Void
    ) throws -> SwanSongEngineServiceProtocol {
        guard let proxy = connection.remoteObjectProxyWithErrorHandler(errorHandler)
                as? SwanSongEngineServiceProtocol else {
            throw SwanSongEngineServiceClientError.unavailable
        }
        return proxy
    }

    private func dataReply(
        _ invoke: @escaping (
            SwanSongEngineServiceProtocol,
            @escaping (Data?, String?) -> Void
        ) -> Void
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate<Data>(continuation)
            do {
                let remote = try proxy { error in gate.fail(error) }
                invoke(remote) { data, error in
                    if let error { gate.fail(SwanSongEngineServiceClientError.remote(error)) }
                    else if let data { gate.succeed(data) }
                    else { gate.fail(SwanSongEngineServiceClientError.invalidPayload) }
                }
            } catch {
                gate.fail(error)
            }
        }
    }

    private func emptyReply(
        _ invoke: @escaping (
            SwanSongEngineServiceProtocol,
            @escaping (String?) -> Void
        ) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate<Void>(continuation)
            do {
                let remote = try proxy { error in gate.fail(error) }
                invoke(remote) { error in
                    if let error { gate.fail(SwanSongEngineServiceClientError.remote(error)) }
                    else { gate.succeed(()) }
                }
            } catch {
                gate.fail(error)
            }
        }
    }
}

private final class ContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func succeed(_ value: Value) { finish(.success(value)) }
    func fail(_ error: Error) { finish(.failure(error)) }

    private func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}

public enum SwanSongEngineServiceClientError: LocalizedError, Sendable {
    case unavailable
    case invalidPayload
    case remote(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "SwanSong’s isolated engine service is unavailable."
        case .invalidPayload:
            "SwanSong’s isolated engine returned an invalid payload."
        case let .remote(detail): detail
        }
    }
}
