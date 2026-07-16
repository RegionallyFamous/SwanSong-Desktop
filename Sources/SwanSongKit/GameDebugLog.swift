import Foundation

public enum GameDebugFocusState: String, Codable, Equatable, Sendable {
    case keyboardActive = "keyboard-active"
    case keyboardInactive = "keyboard-inactive"
    case applicationInactive = "application-inactive"
}

public struct GameDebugSession: Codable, Equatable, Sendable {
    public let appVersion: String
    public let appBuild: String
    public let engineBackend: String
    public let engineBuildID: String
    public let gameTitle: String
    public let romSHA256: String
    public let romByteCount: Int
    public let romChecksum: UInt16
    public let hardwareModel: String
    public let openIPLIdentifier: String
    public let controllerName: String?

    public init(
        appVersion: String,
        appBuild: String,
        engineBackend: String,
        engineBuildID: String,
        gameTitle: String,
        romSHA256: String,
        romByteCount: Int,
        romChecksum: UInt16,
        hardwareModel: String,
        openIPLIdentifier: String,
        controllerName: String?
    ) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.engineBackend = engineBackend
        self.engineBuildID = engineBuildID
        self.gameTitle = gameTitle
        self.romSHA256 = romSHA256
        self.romByteCount = romByteCount
        self.romChecksum = romChecksum
        self.hardwareModel = hardwareModel
        self.openIPLIdentifier = openIPLIdentifier
        self.controllerName = controllerName
    }
}

public struct GameDebugFrame: Codable, Equatable, Sendable {
    public let sequenceIndex: UInt64
    public let frameNumber: UInt64
    public let elapsedSeconds: Double
    public let width: Int
    public let height: Int
    public let isVertical: Bool
    public let keyboardInputMask: UInt32
    public let keyboardInputs: [String]
    public let controllerInputMask: UInt32
    public let controllerInputs: [String]
    public let effectiveInputMask: UInt32
    public let effectiveInputs: [String]
    public let focus: GameDebugFocusState
    public let isPaused: Bool
    public let isFastForwarding: Bool
    public let isFrameStep: Bool
    public let audioFrameCount: Int
    public let gameRasterSHA256: String?

    public init(
        sequenceIndex: UInt64,
        frameNumber: UInt64,
        elapsedSeconds: Double,
        width: Int,
        height: Int,
        isVertical: Bool,
        keyboardInput: EngineInput,
        controllerInput: EngineInput,
        effectiveInput: EngineInput,
        focus: GameDebugFocusState,
        isPaused: Bool,
        isFastForwarding: Bool,
        isFrameStep: Bool,
        audioFrameCount: Int,
        gameRasterSHA256: String? = nil
    ) {
        self.sequenceIndex = sequenceIndex
        self.frameNumber = frameNumber
        self.elapsedSeconds = elapsedSeconds
        self.width = width
        self.height = height
        self.isVertical = isVertical
        self.keyboardInputMask = keyboardInput.rawValue
        self.keyboardInputs = keyboardInput.debugButtonNames
        self.controllerInputMask = controllerInput.rawValue
        self.controllerInputs = controllerInput.debugButtonNames
        self.effectiveInputMask = effectiveInput.rawValue
        self.effectiveInputs = effectiveInput.debugButtonNames
        self.focus = focus
        self.isPaused = isPaused
        self.isFastForwarding = isFastForwarding
        self.isFrameStep = isFrameStep
        self.audioFrameCount = audioFrameCount
        self.gameRasterSHA256 = gameRasterSHA256
    }
}

public struct GameDebugLog: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-input-frame-log-v2"

    public let schema: String
    public let recordingStartedAt: Date
    public let exportedAt: Date
    public let session: GameDebugSession
    public let totalFrameCount: UInt64
    public let droppedFrameCount: Int
    public let frames: [GameDebugFrame]

    public init(
        recordingStartedAt: Date,
        exportedAt: Date,
        session: GameDebugSession,
        totalFrameCount: UInt64,
        droppedFrameCount: Int,
        frames: [GameDebugFrame]
    ) {
        self.schema = Self.currentSchema
        self.recordingStartedAt = recordingStartedAt
        self.exportedAt = exportedAt
        self.session = session
        self.totalFrameCount = totalFrameCount
        self.droppedFrameCount = droppedFrameCount
        self.frames = frames
    }
}

public struct GameDebugLogRecorder: Sendable {
    public static let defaultMaximumRetainedFrames = 60_000

    public let session: GameDebugSession
    public let recordingStartedAt: Date
    public let maximumRetainedFrames: Int
    public private(set) var frames: [GameDebugFrame]
    public private(set) var totalFrameCount: UInt64
    public private(set) var droppedFrameCount: Int

    public init(
        session: GameDebugSession,
        recordingStartedAt: Date = Date(),
        maximumRetainedFrames: Int = Self.defaultMaximumRetainedFrames
    ) {
        self.session = session
        self.recordingStartedAt = recordingStartedAt
        self.maximumRetainedFrames = max(1, maximumRetainedFrames)
        self.frames = []
        self.frames.reserveCapacity(min(self.maximumRetainedFrames, 4_096))
        self.totalFrameCount = 0
        self.droppedFrameCount = 0
    }

    public mutating func record(
        frame: EngineVideoFrame,
        keyboardInput: EngineInput,
        controllerInput: EngineInput,
        effectiveInput: EngineInput,
        focus: GameDebugFocusState,
        isPaused: Bool,
        isFastForwarding: Bool,
        isFrameStep: Bool,
        audioFrameCount: Int,
        recordedAt: Date = Date()
    ) {
        if frames.count >= maximumRetainedFrames {
            let trimCount = min(
                frames.count,
                max(1, maximumRetainedFrames / 10)
            )
            frames.removeFirst(trimCount)
            droppedFrameCount += trimCount
        }
        frames.append(
            GameDebugFrame(
                sequenceIndex: totalFrameCount,
                frameNumber: frame.number,
                elapsedSeconds: max(
                    0,
                    recordedAt.timeIntervalSince(recordingStartedAt)
                ),
                width: frame.width,
                height: frame.height,
                isVertical: frame.isVertical,
                keyboardInput: keyboardInput,
                controllerInput: controllerInput,
                effectiveInput: effectiveInput,
                focus: focus,
                isPaused: isPaused,
                isFastForwarding: isFastForwarding,
                isFrameStep: isFrameStep,
                audioFrameCount: max(0, audioFrameCount),
                gameRasterSHA256: try? TranslationRouteCheckpoint.fingerprint(frame)
            )
        )
        totalFrameCount += 1
    }

    public func snapshot(exportedAt: Date = Date()) -> GameDebugLog {
        GameDebugLog(
            recordingStartedAt: recordingStartedAt,
            exportedAt: exportedAt,
            session: session,
            totalFrameCount: totalFrameCount,
            droppedFrameCount: droppedFrameCount,
            frames: frames
        )
    }
}

public extension EngineInput {
    var debugButtonNames: [String] {
        var names: [String] = []
        var knownMask: UInt32 = 0
        for item in Self.debugButtons where contains(item.input) {
            names.append(item.name)
            knownMask |= item.input.rawValue
        }
        let unknownMask = rawValue & ~knownMask
        if unknownMask != 0 {
            names.append(String(format: "unknown:0x%08x", unknownMask))
        }
        return names
    }

    var debugSummary: String {
        let names = debugButtonNames
        return names.isEmpty ? "None" : names.joined(separator: "+")
    }

    private static var debugButtons: [(name: String, input: EngineInput)] {
        [
            ("Y1", .y1), ("Y2", .y2), ("Y3", .y3), ("Y4", .y4),
            ("X1", .x1), ("X2", .x2), ("X3", .x3), ("X4", .x4),
            ("B", .b), ("A", .a), ("Start", .start),
            ("Volume", .volume), ("Power", .power),
            ("Up", .pocketChallengeUp),
            ("Right", .pocketChallengeRight),
            ("Down", .pocketChallengeDown),
            ("Left", .pocketChallengeLeft),
            ("Pass", .pocketChallengePass),
            ("Circle", .pocketChallengeCircle),
            ("Clear", .pocketChallengeClear),
            ("View", .pocketChallengeView),
            ("Escape", .pocketChallengeEscape),
        ]
    }
}
