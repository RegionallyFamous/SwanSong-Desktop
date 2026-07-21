import Darwin
import Foundation
import Security
import SwanSongKit

@MainActor
final class SwanSongLocalMCPBridge {
    private unowned let model: AppModel
    private var server: SwanSongLocalMCPUnixServer?
    private var acceptedNonces: [String: Int64] = [:]

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard server == nil else { return }
        do {
            let server = try SwanSongLocalMCPUnixServer { [weak self] request in
                await MainActor.run {
                    self?.handle(request) ?? SwanSongLocalMCPResponse(
                        requestID: request.requestID,
                        json: nil,
                        error: SwanSongLocalMCPTransportError.unavailable.localizedDescription
                    )
                }
            }
            server.start()
            self.server = server
        } catch {
            model.presentedError = "Local MCP control could not start securely: \(error.localizedDescription)"
        }
    }

    private func handle(_ request: SwanSongLocalMCPRequest) -> SwanSongLocalMCPResponse {
        do {
            try request.validateFreshness()
            try acceptFreshNonce(request)
            guard model.debugToolsEnabled else {
                throw BridgeError("Turn on Developer Tools in SwanSong Settings before using local MCP control.")
            }
            guard UserDefaults.standard.bool(
                forKey: SwanSongLocalMCPAccess.enabledDefaultsKey
            ) else {
                throw BridgeError("Local MCP control is off in SwanSong Settings.")
            }
            return SwanSongLocalMCPResponse(
                requestID: request.requestID,
                json: try response(
                    method: request.method,
                    argumentsJSON: request.argumentsJSON
                ),
                error: nil
            )
        } catch {
            return SwanSongLocalMCPResponse(
                requestID: request.requestID,
                json: nil,
                error: error.localizedDescription
            )
        }
    }

    private func acceptFreshNonce(_ request: SwanSongLocalMCPRequest) throws {
        let oldest = SwanSongLocalMCPAccess.currentUnixSeconds()
            - SwanSongLocalMCPAccess.maximumClockSkewSeconds
        acceptedNonces = acceptedNonces.filter { $0.value >= oldest }
        guard acceptedNonces[request.nonce] == nil else {
            throw SwanSongLocalMCPTransportError.invalidRequest
        }
        acceptedNonces[request.nonce] = request.issuedAtUnixSeconds
    }

    func response(method: String, argumentsJSON: String) throws -> String {
        let arguments = try decodeArguments(argumentsJSON)
        let payload: [String: Any]
        switch method {
        case "status":
            payload = status()
        case "navigate":
            payload = try navigate(arguments)
        case "player":
            payload = try controlPlayer(arguments)
        case "studio-projects":
            payload = studioProjects()
        case "studio-action":
            payload = try runStudioAction(arguments)
        default:
            throw BridgeError("SwanSong does not allow the requested local MCP action.")
        }
        return try encode(payload)
    }

    private func studioProjects() -> [String: Any] {
        let workspace = model.studioWorkspace
        let phase: String
        let sdkSource: String
        if workspace.isRunning {
            phase = "running"
        } else if workspace.issue != nil {
            phase = "needs-attention"
        } else {
            phase = "idle"
        }
        if workspace.sdkRoot == nil {
            sdkSource = "unavailable"
        } else if workspace.usesVerifiedBundledSDK {
            sdkSource = "bundled"
        } else {
            sdkSource = "external"
        }
        return [
            "schema": "swansong-studio-projects-v1",
            "sdkConfigured": workspace.sdkRoot != nil,
            "sdkSource": sdkSource,
            "sdkVersion": workspace.sdkPackage?.version ?? "unavailable",
            "pythonVersion": workspace.pythonRuntime?.version ?? "unavailable",
            "projectCount": workspace.projectRoot == nil ? 0 : 1,
            "projects": workspace.projectRoot == nil ? [] : [[
                "slot": "current",
                "manifestOpen": true,
                "scenarioCount": workspace.playContract?.scenarios.count ?? 0,
                "hasUnsavedChanges": workspace.manifestHasUnsavedChanges
                    || workspace.scenarioPlanHasUnsavedChanges,
            ]],
            "phase": phase,
            "activeAction": workspace.activeCommandName ?? "none",
        ]
    }

    private func runStudioAction(_ arguments: [String: Any]) throws -> [String: Any] {
        guard arguments["confirmProjectWrites"] as? Bool == true else {
            throw BridgeError(
                "Set confirmProjectWrites to true after confirming the current Studio project may be built or updated."
            )
        }
        guard let action = arguments["action"] as? String else {
            throw BridgeError("action is required")
        }
        try model.studioWorkspace.runAutomationAction(named: action)
        return studioProjects()
    }

    private func status() -> [String: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        let playback: String
        if model.isLaunchingGame {
            playback = "launching"
        } else if !model.isPlaying {
            playback = "stopped"
        } else if model.isPaused {
            playback = "paused"
        } else {
            playback = "playing"
        }
        return [
            "appVersion": info["CFBundleShortVersionString"] as? String ?? "development",
            "appBuild": info["CFBundleVersion"] as? String ?? "development",
            "section": sectionName(model.section),
            "libraryCount": model.games.count,
            "hasSelectedGame": model.selectedGame != nil,
            "hasPlayingGame": model.playingGame != nil,
            "playback": playback,
            "playerBusy": model.playerStateOperationIsBusy,
            "translationProjectOpen": model.translationProject != nil,
            "storyProjectOpen": model.storyForgeWorkspace.projectSummary != nil,
        ]
    }

    private func navigate(_ arguments: [String: Any]) throws -> [String: Any] {
        guard let requested = arguments["section"] as? String,
              let section = section(named: requested) else {
            throw BridgeError(
                "section must be library, favorites, recent, homebrew, cartridges, pocket, translation, story, or studio"
            )
        }
        guard !model.isPlaying else {
            throw BridgeError("Stop the active game before changing SwanSong sections.")
        }
        model.section = section
        return status()
    }

    private func controlPlayer(_ arguments: [String: Any]) throws -> [String: Any] {
        guard let action = arguments["action"] as? String else {
            throw BridgeError("action must be play-selected, pause, resume, or stop")
        }
        switch action {
        case "play-selected":
            guard !model.isPlaying, model.selectedGame != nil else {
                throw BridgeError("Select a playable library game before asking SwanSong to start it.")
            }
            model.playSelectedGame()
        case "pause":
            guard model.isPlaying else { throw BridgeError("No game is playing.") }
            if !model.isPaused { model.togglePause() }
        case "resume":
            guard model.isPlaying else { throw BridgeError("No game is playing.") }
            if model.isPaused { model.togglePause() }
        case "stop":
            guard model.isPlaying else { throw BridgeError("No game is playing.") }
            model.stopPlaying()
        default:
            throw BridgeError("action must be play-selected, pause, resume, or stop")
        }
        return status()
    }

    private func section(named name: String) -> AppModel.Section? {
        switch name {
        case "library": .library
        case "favorites": .favorites
        case "recent": .recent
        case "homebrew": .homebrew
        case "cartridges": .cartridgeTools
        case "pocket": .pocketCore
        case "translation": .translationLab
        case "story": .storyForge
        case "studio": .gameStudio
        default: nil
        }
    }

    private func sectionName(_ section: AppModel.Section) -> String {
        switch section {
        case .library: "library"
        case .favorites: "favorites"
        case .recent: "recent"
        case .homebrew: "homebrew"
        case .cartridgeTools: "cartridges"
        case .pocketCore: "pocket"
        case .translationLab: "translation"
        case .storyForge: "story"
        case .gameStudio: "studio"
        }
    }

    private func decodeArguments(_ json: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        guard let arguments = object as? [String: Any] else {
            throw BridgeError("The local MCP arguments must be a JSON object.")
        }
        return arguments
    }

    private func encode(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return String(decoding: data, as: UTF8.self)
    }

}

private final class SwanSongLocalMCPUnixServer: @unchecked Sendable {
    typealias Handler = @Sendable (SwanSongLocalMCPRequest) async -> SwanSongLocalMCPResponse

    private let handler: Handler
    private let queue = DispatchQueue(label: "com.regionallyfamous.swansong.mcp-listener")
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var isStopped = false

    init(handler: @escaping Handler) throws {
        self.handler = handler
        try SwanSongLocalMCPAccess.preparePrivateDirectory()
        try SwanSongLocalMCPAccess.removeSocketIfPresent()

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw SwanSongUnixSocketIO.posixError() }
        do {
            var noSignal: Int32 = 1
            guard setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &noSignal,
                socklen_t(MemoryLayout<Int32>.size)
            ) == 0 else { throw SwanSongUnixSocketIO.posixError() }
            var address = try SwanSongUnixSocketIO.unixAddress(
                path: SwanSongLocalMCPAccess.socketURL.path
            )
            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0 else { throw SwanSongUnixSocketIO.posixError() }
            guard chmod(SwanSongLocalMCPAccess.socketURL.path, 0o600) == 0,
                  listen(descriptor, 8) == 0 else {
                throw SwanSongUnixSocketIO.posixError()
            }
            listener = descriptor
        } catch {
            close(descriptor)
            try? SwanSongLocalMCPAccess.removeSocketIfPresent()
            throw error
        }
    }

    deinit { stop() }

    func start() {
        queue.async { [weak self] in self?.acceptLoop() }
    }

    func stop() {
        lock.lock()
        guard !isStopped else { lock.unlock(); return }
        isStopped = true
        let descriptor = listener
        listener = -1
        lock.unlock()
        if descriptor >= 0 {
            shutdown(descriptor, SHUT_RDWR)
            close(descriptor)
        }
        try? SwanSongLocalMCPAccess.removeSocketIfPresent()
    }

    private func acceptLoop() {
        while true {
            lock.lock()
            let descriptor = listener
            let stopped = isStopped
            lock.unlock()
            guard !stopped, descriptor >= 0 else { return }
            let connection = accept(descriptor, nil, nil)
            if connection < 0 {
                if errno == EINTR { continue }
                return
            }
            Task.detached(priority: .userInitiated) { [weak self] in
                await self?.serve(connection)
            }
        }
    }

    private func serve(_ descriptor: Int32) async {
        defer { close(descriptor) }
        do {
            try SwanSongUnixSocketIO.setTimeout(descriptor, seconds: 5)
            try verifyPeer(descriptor)
            let data = try SwanSongUnixSocketIO.readLine(from: descriptor)
            let request = try JSONDecoder().decode(SwanSongLocalMCPRequest.self, from: data)
            try request.validateFreshness()
            var responseData = try JSONEncoder().encode(await handler(request))
            responseData.append(0x0a)
            try SwanSongUnixSocketIO.writeAll(responseData, to: descriptor)
        } catch {
            // Authentication failures deliberately close without an oracle.
        }
    }

    private func verifyPeer(_ descriptor: Int32) throws {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(descriptor, &uid, &gid) == 0, uid == geteuid() else {
            throw SwanSongLocalMCPTransportError.peerRejected
        }
        var pid: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) == 0,
              pid > 0,
              SwanSongMCPCodeSignature.trusts(pid: pid) else {
            throw SwanSongLocalMCPTransportError.peerRejected
        }
    }
}

private enum SwanSongMCPCodeSignature {
    static func trusts(pid: pid_t) -> Bool {
        guard let peer = signingIdentity(pid: pid),
              peer.identifier == SwanSongLocalMCPAccess.officialClientIdentifier,
              let own = signingIdentity(pid: getpid()) else {
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
        if let ownTeam = own.teamIdentifier, !ownTeam.isEmpty {
            return peer.teamIdentifier == ownTeam && peer.valid
        }
        #if DEBUG
        return peer.valid
        #else
        return false
        #endif
    }

    private static func signingIdentity(
        pid: pid_t
    ) -> (identifier: String, teamIdentifier: String?, valid: Bool)? {
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return nil }
        var path = [CChar](repeating: 0, count: 4_096)
        let pathLength = proc_pidpath(pid, &path, UInt32(path.count))
        guard pathLength > 0 else { return nil }
        let pathBytes = path.prefix(Int(pathLength)).map {
            UInt8(bitPattern: $0)
        }
        let codeURL = URL(
            fileURLWithPath: String(decoding: pathBytes, as: UTF8.self)
        ) as CFURL
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(codeURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
              let values = information as? [String: Any],
              let identifier = values[kSecCodeInfoIdentifier as String] as? String else {
            return nil
        }
        let valid = SecCodeCheckValidity(code, [], nil) == errSecSuccess
        return (
            identifier,
            values[kSecCodeInfoTeamIdentifier as String] as? String,
            valid
        )
    }
}

private struct BridgeError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
