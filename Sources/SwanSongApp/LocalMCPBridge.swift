import Foundation
import SwanSongKit

@MainActor
final class SwanSongLocalMCPBridge {
    private unowned let model: AppModel
    private var observer: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: SwanSongLocalMCPAccess.requestNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let values = notification.userInfo as? [String: String] else { return }
            Task { @MainActor [weak self, values] in
                self?.handle(values)
            }
        }
    }

    private func handle(_ values: [String: String]) {
        guard let requestID = values["requestID"],
              let presentedToken = values["token"],
              let method = values["method"] else { return }

        do {
            guard UserDefaults.standard.bool(
                forKey: SwanSongLocalMCPAccess.enabledDefaultsKey
            ) else {
                throw BridgeError("Local MCP control is off in SwanSong Settings.")
            }
            guard let expectedToken = try SwanSongLocalMCPAccess.readToken(),
                  expectedToken == presentedToken else {
                throw BridgeError("The local MCP token is missing or no longer valid.")
            }
            respond(
                requestID: requestID,
                token: presentedToken,
                json: try response(
                    method: method,
                    argumentsJSON: values["arguments"] ?? "{}"
                ),
                error: nil
            )
        } catch {
            respond(
                requestID: requestID,
                token: presentedToken,
                json: nil,
                error: error.localizedDescription
            )
        }
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
        default:
            throw BridgeError("SwanSong does not allow the requested local MCP action.")
        }
        return try encode(payload)
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
        ]
    }

    private func navigate(_ arguments: [String: Any]) throws -> [String: Any] {
        guard let requested = arguments["section"] as? String,
              let section = section(named: requested) else {
            throw BridgeError(
                "section must be library, favorites, recent, homebrew, pocket, or translation"
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
        case "pocket": .pocketCore
        case "translation": .translationLab
        default: nil
        }
    }

    private func sectionName(_ section: AppModel.Section) -> String {
        switch section {
        case .library: "library"
        case .favorites: "favorites"
        case .recent: "recent"
        case .homebrew: "homebrew"
        case .pocketCore: "pocket"
        case .translationLab: "translation"
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

    private func respond(
        requestID: String,
        token: String,
        json: String?,
        error: String?
    ) {
        var values = [
            "requestID": requestID,
            "token": token,
        ]
        values["json"] = json
        values["error"] = error
        DistributedNotificationCenter.default().postNotificationName(
            SwanSongLocalMCPAccess.responseNotification,
            object: nil,
            userInfo: values,
            deliverImmediately: true
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
