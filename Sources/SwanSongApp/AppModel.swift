import AppKit
import Foundation
import Observation
import SwanSongKit
import UniformTypeIdentifiers

private final class StateLoadUndoActionTarget: NSObject {
    weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
    }

    func perform() {
        Task { @MainActor [weak model] in
            model?.undoLastStateLoad()
        }
    }
}

private enum HomebrewCatalogAppError: LocalizedError {
    case libraryChanged

    var errorDescription: String? {
        switch self {
        case .libraryChanged:
            "The library changed while the game was downloading. No install changes were kept; try again."
        }
    }
}

struct PlayerVideoActivityDiagnosticState: Sendable {
    static let defaultWarningRearmFrameThreshold = 600

    let warningRearmFrameThreshold: Int
    private(set) var issue: FrameActivityIssue?
    private(set) var showsWarning = false
    private(set) var isSnoozed = false
    private(set) var framesSinceDismissal = 0
    private(set) var dismissalCount = 0

    var isDegraded: Bool { issue != nil }

    init(
        warningRearmFrameThreshold: Int = PlayerVideoActivityDiagnosticState
            .defaultWarningRearmFrameThreshold
    ) {
        self.warningRearmFrameThreshold = max(1, warningRearmFrameThreshold)
    }

    mutating func observe(_ report: FrameActivityReport) {
        if report.hasMeaningfulMotion {
            reset()
            return
        }
        guard let issue = report.issue else { return }

        self.issue = issue
        if isSnoozed {
            framesSinceDismissal += 1
            if framesSinceDismissal >= currentWarningRearmFrameThreshold {
                isSnoozed = false
                framesSinceDismissal = 0
                showsWarning = true
            }
        } else {
            showsWarning = true
        }
    }

    mutating func dismissWarning() {
        guard isDegraded else { return }
        showsWarning = false
        isSnoozed = true
        framesSinceDismissal = 0
        dismissalCount += 1
    }

    mutating func presentWarning() {
        guard isDegraded else { return }
        showsWarning = true
        isSnoozed = false
        framesSinceDismissal = 0
    }

    mutating func reset() {
        issue = nil
        showsWarning = false
        isSnoozed = false
        framesSinceDismissal = 0
        dismissalCount = 0
    }

    private var currentWarningRearmFrameThreshold: Int {
        let exponent = min(max(dismissalCount - 1, 0), 2)
        return warningRearmFrameThreshold * (1 << exponent)
    }
}

@MainActor
@Observable
final class AppModel {
    private static let homebrewCatalogConsentDefaultsKey =
        "SwanSong.homebrewCatalogConsent.v1"
    private static let debugToolsDefaultsKey = "SwanSong.debugToolsEnabled.v1"
    private struct GameLaunchIdentityError: LocalizedError {
        let title: String

        var errorDescription: String? {
            "\(title)’s game bytes no longer match the system identity recorded when it was added. Re-add the original game as a new library entry before playing it."
        }
    }

    private enum TranslationRAMInspectionOutcome: Sendable {
        case success(
            comparison: TranslationRAMComparison,
            textReport: TranslationRAMTextReport?,
            textIssue: String?,
            pointerReport: TranslationRAMPointerReport?,
            pointerIssue: String?
        )
        case failure(String)
    }

    private struct RetiringEmulationSession: Sendable {
        let id: UUID
        let task: Task<Void, Never>
        let finalization: PlayerSessionFinalization
    }

    private struct StateLoadRollbackPoint: Sendable {
        let sessionGeneration: UUID
        let gameID: GameRecord.ID
        let state: Data
        let frame: EngineVideoFrame
    }

    private struct PendingPlayerRetirement {
        let preservingPlayerPresentation: Bool
    }

    private struct PreviousSessionSaveError: LocalizedError {
        let failure: PlayerSessionPersistenceFailure

        var errorDescription: String? {
            "SwanSong could not safely save \(failure.gameTitle) before starting another game: \(failure.detail)"
        }
    }

    private struct PlayerStateRollbackCreationError: LocalizedError {
        let underlying: Error

        var errorDescription: String? {
            "A rollback point could not be created: \(underlying.localizedDescription)"
        }
    }

    private struct StatePreviewUnavailableError: LocalizedError {
        let detail: String

        var errorDescription: String? {
            "The saved-moment preview is missing or damaged, so SwanSong left the current game unchanged. \(detail)"
        }
    }

    private enum PlayerLaunchIntent: Equatable {
        case game(id: GameRecord.ID, title: String)
        case translation(
            continuation: TranslationLaunchContinuation,
            projectPath: String,
            title: String
        )
    }

    private enum TranslationLaunchContinuation: Equatable {
        case play(role: TranslationROMRole, recordingFromCleanBoot: Bool)
        case replay(role: TranslationROMRole, route: TranslationRoute)
        case verifyRoute(TranslationRoute)
        case verifySuite
        case locateVisualDivergence(TranslationRoute)
    }

    enum Section: String, CaseIterable, Identifiable {
        case library = "Library"
        case favorites = "Favorites"
        case recent = "Recently Played"
        case homebrew = "Homebrew"
        case pocketCore = "Analogue Pocket"
        case translationLab = "Translation Lab"
        case storyForge = "Story Forge"
        case gameStudio = "SwanSong Studio"

        var id: Self { self }

        var symbol: String {
            switch self {
            case .library: "square.grid.2x2"
            case .favorites: "star"
            case .recent: "clock"
            case .homebrew: "shippingbox"
            case .pocketCore: "sdcard"
            case .translationLab: "character.book.closed"
            case .storyForge: "book.pages"
            case .gameStudio: "hammer"
            }
        }
    }

    enum TranslationComparisonPhase: Equatable {
        case preparing
        case replaying(TranslationROMRole)
        case capturing(TranslationROMRole)

        var title: String {
            switch self {
            case .preparing:
                "Preparing patched ROM"
            case let .replaying(role):
                "Replaying \(role.title)"
            case let .capturing(role):
                "Capturing \(role.title)"
            }
        }

        var role: TranslationROMRole? {
            switch self {
            case .preparing:
                nil
            case let .replaying(role), let .capturing(role):
                role
            }
        }
    }

    enum TranslationTestCaseStatus: Equatable {
        case notRun
        case partial
        case readyForReview
        case needsWork
        case approved
        case integrityIssue

        var title: String {
            switch self {
            case .notRun: "Not run"
            case .partial: "Partial"
            case .readyForReview: "Ready to review"
            case .needsWork: "Needs work"
            case .approved: "Approved"
            case .integrityIssue: "Integrity issue"
            }
        }

        var symbol: String {
            switch self {
            case .notRun: "circle.dashed"
            case .partial: "circle.lefthalf.filled"
            case .readyForReview: "checkmark.bubble"
            case .needsWork: "exclamationmark.bubble.fill"
            case .approved: "checkmark.seal.fill"
            case .integrityIssue: "exclamationmark.shield.fill"
            }
        }
    }

    enum PlayerStateOperation: Equatable {
        case saving
        case loading
        case undoingLoad
        case resetting
        case rewinding

        var title: String {
            switch self {
            case .saving: "Saving state…"
            case .loading: "Loading state…"
            case .undoingLoad: "Undoing state load…"
            case .resetting: "Resetting game…"
            case .rewinding: "Rewinding…"
            }
        }
    }

    struct TranslationTestCaseCoverage {
        let original: TranslationEvidenceSummary?
        let patched: TranslationEvidenceSummary?
        let status: TranslationTestCaseStatus

        var capturedCount: Int {
            (original == nil ? 0 : 1) + (patched == nil ? 0 : 1)
        }
    }

    private enum TranslationPipelineCompletion {
        case none
        case playPatched
        case verifyRoute(TranslationRoute)
        case locateVisualDivergence(TranslationRoute)
    }

    private static let guardedTranslationPackStages: [TranslationToolkitStage] = [
        .status,
        .qa,
        .validate,
        .packStrict,
        .status,
    ]

    var section: Section = .library
    var games: [GameRecord] = []
    var selectedGameID: GameRecord.ID?
    var presentedError: String? {
        didSet {
            if let presentedError { appDiagnostic("error: \(presentedError)") }
        }
    }
    var presentedNotice: String? {
        didSet {
            if let presentedNotice { appDiagnostic("notice: \(presentedNotice)") }
        }
    }
    var playingGameID: GameRecord.ID?
    var currentFrame: EngineVideoFrame?
    var playerFailure: PlayerFailureState?
    var isLaunchingGame = false
    var isFinalizingFailedSession = false
    var terminationIsInProgress = false
    var playerLaunchStage: PlayerLaunchStage?
    var playerLaunchNeedsAttention = false
    var lastAudioFrameCount = 0
    var keyboardInput: EngineInput = []
    var controllerInput: EngineInput = []
    var controllerPhysicalElements: Set<ControllerElement> = []
    var controllerAvailableElements: Set<ControllerElement> = []
    var controllerProfile: ControllerProfile = .default
    var controllerLearningControl: WonderSwanControl?
    var connectedControllerName: String?
    var controllerBatterySummary: ControllerBatterySummary?
    private(set) var debugToolsEnabled = false
    var debugOverlayIsVisible = false
    private(set) var debugGameplayHasFocus = false
    private(set) var debugLastEffectiveInput: EngineInput = []
    private(set) var debugLogIsRecording = false
    private(set) var debugLogFrameCount = 0
    private(set) var debugLogDroppedFrameCount = 0
    private(set) var debugLastExportURL: URL?
    var unavailableControllerBindings: [ControllerBinding] {
        guard connectedControllerName != nil else { return [] }
        return controllerProfile.unavailableBindings(
            for: controllerAvailableElements
        )
    }
    /// The Settings live test reflects the saved mapping even when no game is
    /// running. Gameplay delivery remains separately gated through
    /// `controllerInput` and `playerIsInteractive`.
    var controllerPreviewInput: EngineInput {
        controllerProfile.input(for: controllerPhysicalElements)
    }
    var isPaused = false
    var isFastForwarding = false
    var audioQueueMilliseconds = 0.0
    var droppedAudioBatches = 0
    var recoveredAudioDiscontinuities = 0
    var playerVideoActivityNeedsAttention: Bool {
        playerVideoActivityDiagnostic.showsWarning
    }
    var playerVideoActivityIssue: FrameActivityIssue? {
        playerVideoActivityDiagnostic.issue
    }
    var playerVideoActivityIsDegraded: Bool {
        playerVideoActivityDiagnostic.isDegraded
    }
    var gameImportIsBusy = false
    var homebrewCatalogConsentGranted = false
    private(set) var homebrewCatalogIsConfigured = false
    var homebrewCatalog: HomebrewCatalog?
    var selectedHomebrewEntryID: String?
    var homebrewCatalogIsLoading = false
    var homebrewCatalogIssue: String?
    var homebrewCatalogLastUpdatedAt: Date?
    var homebrewInstallingEntryID: String?
    var homebrewInstallProgress: Double?
    var homebrewInstallPhase: String?
    var homebrewInstallIssue: String?
    var homebrewInstallIssueEntryID: String?
    var gameArtwork: [GameRecord.ID: GameArtworkRecord] = [:]
    var managedGameHealth: [GameRecord.ID: ManagedGameHealth] = [:]
    var checkingManagedGameIDs: Set<GameRecord.ID> = []
    var repairingGameID: GameRecord.ID?
    var quickStateSavedAt: Date?
    var timelineStates: [GameStateSummary] = []
    var isStateTimelinePresented = false
    var isRewindPresented = false
    var rewindCheckpoints: [RewindCheckpoint] = []
    var selectedRewindCheckpointID: RewindCheckpoint.ID?
    var playerStateOperation: PlayerStateOperation?
    var playerStateNeedsNaturalFrame = false
    var stateLoadUndoMessage: String?
    var translationProjects: [TranslationProject] = []
    var translationProject: TranslationProject?
    var translationReadiness: TranslationReadiness?
    var translationCommandOutput = ""
    var translationToolPhase: String?
    var translationToolIsRunning = false
    var activeTranslationRole: TranslationROMRole?
    var translationRouteIsRecording = false
    var translationRouteRecordingIsPreparing = false
    var translationTestCaseNamingRequestID = 0
    var translationReplayProgress: Double?
    var latestTranslationRoute: TranslationRoute?
    var latestTranslationRouteURL: URL?
    var translationRoutes: [TranslationRouteSummary] = []
    var translationTestCaseName = ""
    var translationTestCaseNote = ""
    var lastTranslationEvidenceURL: URL?
    var translationEvidence: [TranslationEvidenceSummary] = []
    var selectedTranslationEvidenceID: TranslationEvidenceSummary.ID?
    var translationEvidenceReviewStatus: TranslationEvidenceReviewStatus = .unreviewed
    var translationEvidenceReviewNote = ""
    var translationEvidenceFrameComparison: TranslationEvidenceFrameComparison?
    var translationEvidenceFrameComparisonIssue: String?
    var translationPrivateArtifacts: [TranslationPrivateArtifactSummary] = []
    var selectedTranslationPrivateArtifactID: TranslationPrivateArtifactSummary.ID?
    var translationPrivateStorageStatus: TranslationPrivateStorageStatus?
    var isTranslationTextIntakePresented = false
    var translationTextIntakeIsRecognizing = false
    var translationTextIntakeIssue: String?
    var translationTextIntakeSelection: TranslationPixelRect?
    var translationTextIntakeSession: TranslationTextIntakeSession?
    var translationTextIntakeDrafts: [String: String] = [:]
    var translationTextIntakeManualDraft = ""
    var translationTextIntakeHasSavedArtifact = false
    var translationDraftSession: TranslationDraftSession?
    var translationDraftTargetDrafts: [String: String] = [:]
    var translationDraftIssue: String?
    var translationDraftHasSavedArtifact = false
    var translationRAMComparison: TranslationRAMComparison?
    var translationRAMInspectionIssue: String?
    var translationRAMTextReport: TranslationRAMTextReport?
    var translationRAMTextInspectionIssue: String?
    var translationRAMPointerReport: TranslationRAMPointerReport?
    var translationRAMPointerInspectionIssue: String?
    var translationRAMInspectionIsLoading = false
    var isTranslationRAMInspectorPresented = false
    var isTranslationVisualDivergencePresented = false
    var translationVisualDivergenceIsRunning = false
    var translationVisualDivergenceProgress: TranslationVisualDivergenceRunner.Progress?
    var translationVisualDivergenceResult: TranslationVisualDivergenceResult?
    var translationVisualDivergenceIssue: String?
    var lastTranslationDiagnosticURL: URL?
    var translationBaselines: [TranslationRouteBaselineSummary] = []
    var translationSuiteRuns: [TranslationSuiteRunSummary] = []
    var translationSuiteCurrentCaseIndex: Int?
    var translationSuiteTotalCaseCount = 0
    var translationSuiteCaseResults: [TranslationSuiteCaseResult] = []
    var isCapturingTranslationEvidence = false
    var translationComparisonPhase: TranslationComparisonPhase?
    var fitWindowRequestID = 0

    var hasEmulationSessionPendingFinalization: Bool {
        emulationTask != nil || retiringEmulationSession != nil
    }

    let engineBackendName: String
    let engineBuildID: String
    let engineCanExecute: Bool
    let studioWorkspace: SwanSDKWorkspaceModel
    let storyForgeWorkspace: StoryForgeWorkspaceModel

    private let store: GameLibraryStore
    private let saveStore: GameSaveStore
    private let stateStore: GameStateStore
    private let managedGameStore: ManagedGameStore
    private let homebrewCatalogClient: HomebrewCatalogClient
    private let homebrewCatalogCacheStore: HomebrewCatalogCacheStore
    private let homebrewCatalogSignatureVerifier: HomebrewCatalogSignatureVerifier
    private let homebrewCatalogHighWaterStore: any HomebrewCatalogHighWaterStoring
    private let homebrewCatalogMinimumRevision: Int
    private let artworkStore: GameArtworkStore
    private let controllerProfileStore: ControllerProfileStore
    private let translationWorkspaceStore: TranslationWorkspaceStore
    private let translationEvidenceStore = TranslationEvidenceStore()
    private let translationPrivateArtifactStore = TranslationPrivateArtifactStore()
    private let importer = GameImporter()
    private let gameImportPlanner = GameImportPlanner()
    private let batchImporter: GameBatchImporter
    private let audioOutput = AudioOutput()
    private let controller = ControllerInput()
    private var emulationTask: Task<Void, Never>?
    private var emulationFinalization: PlayerSessionFinalization?
    private var retiringEmulationSession: RetiringEmulationSession?
    private var emulationGeneration = UUID()
    private var activeRunner: EmulationRunner?
    private var activeGameStateSessionIdentity: GameStateSessionIdentity?
    private var stateLoadUndoPoint: StateLoadRollbackPoint?
    private weak var stateLoadUndoManager: UndoManager?
    private var stateLoadUndoTarget: StateLoadUndoActionTarget?
    private var stateLoadUndoActionName = "Load State"
    private var playerStateTransactionTask: Task<Void, Never>?
    private var playerStateTransactionID = UUID()
    private var pendingPlayerRetirement: PendingPlayerRetirement?
    private var discardFinalPersistenceGenerations: Set<UUID> = []
    private var playerFailureRetryIntent: PlayerLaunchIntent?
    private var frameAdvanceGate = FrameAdvanceGate()
    private var frameActivityMonitor = FrameActivityMonitor()
    private var playerVideoActivityDiagnostic = PlayerVideoActivityDiagnosticState()
    private var applicationIsActive = true
    private var debugLogRecorder: GameDebugLogRecorder?
    private var pendingAutomaticArtworkGameID: GameRecord.ID?
    private var managedGameHealthScanGeneration = UUID()
    private var pendingRepairPlayGameID: GameRecord.ID?
    private var homebrewCatalogRefreshTask: Task<Void, Never>?
    private var homebrewCatalogRefreshGeneration = UUID()
    private var homebrewInstallTask: Task<Void, Never>?
    private var homebrewCatalogRefreshAttemptedThisSession = false
    private var playerReturnSection: Section = .library
    private let pacingPolicy = FramePacingPolicy()
    private var inactivityPauseWasApplied = false
    private var automatedQuickStateFrames: [UInt64] = {
        let environment = ProcessInfo.processInfo.environment
        let value = environment["SWAN_SONG_QUICK_STATE_FRAMES"]
            ?? environment["SWAN_SONG_QUICK_STATE_FRAME"]
            ?? ""
        return value.split(separator: ",").compactMap { UInt64($0) }.sorted()
    }()
    private var automatedStopAtFrame = ProcessInfo.processInfo.environment[
        "SWAN_SONG_STOP_AT_FRAME"
    ].flatMap(UInt64.init)
    #if SWAN_SONG_AUTOMATION
    private let automatedDebugLogURL = ProcessInfo.processInfo.environment[
        "SWAN_SONG_DEBUG_LOG_PATH"
    ].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    private var automatedCaptureFrame = ProcessInfo.processInfo.environment[
        "SWAN_SONG_CAPTURE_FRAME"
    ].flatMap(UInt64.init)
    private var automatedCaptureFrameURL = ProcessInfo.processInfo.environment[
        "SWAN_SONG_CAPTURE_FRAME_PATH"
    ].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    private var automatedQuickStateLoadFrame = ProcessInfo.processInfo.environment[
        "SWAN_SONG_LOAD_QUICK_STATE_FRAME"
    ].flatMap(UInt64.init)
    private var automatedResetFrame = ProcessInfo.processInfo.environment[
        "SWAN_SONG_RESET_FRAME"
    ].flatMap(UInt64.init)
    private var automatedStateLoadPreviewURL = ProcessInfo.processInfo.environment[
        "SWAN_SONG_STATE_LOAD_PREVIEW_PATH"
    ].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    private var automatedRewindAtFrame = ProcessInfo.processInfo.environment[
        "SWAN_SONG_REWIND_AT_FRAME"
    ].flatMap(UInt64.init)
    private let automatedRewindReferenceFrame = ProcessInfo.processInfo.environment[
        "SWAN_SONG_REWIND_REFERENCE_FRAME"
    ].flatMap(UInt64.init)
    private let automatedRewindBeforeURL = ProcessInfo.processInfo.environment[
        "SWAN_SONG_REWIND_BEFORE_PATH"
    ].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    private let automatedRewindAfterURL = ProcessInfo.processInfo.environment[
        "SWAN_SONG_REWIND_AFTER_PATH"
    ].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    private var automatedRewindUndoAtFrame = ProcessInfo.processInfo.environment[
        "SWAN_SONG_REWIND_UNDO_AT_FRAME"
    ].flatMap(UInt64.init)
    private let automatedRewindUndoRestoredURL = ProcessInfo.processInfo.environment[
        "SWAN_SONG_REWIND_UNDO_RESTORED_PATH"
    ].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    private var automatedRewindReferenceWasCaptured = false
    private var automatedRewindHasCompleted = false
    private var automatedRewindUndoWasRequested = false
    private var automatedRewindUndoHasCompleted = false
    private var automatedRewindHistoryHasRebuilt = false
    #endif
    private var resumeAfterTimeline = false
    private var rewindBuffer = RewindBuffer()
    private var resumeAfterRewind = false
    private let rewindCaptureFrameInterval: UInt64 = 15
    private var playerStateOperationGeneration = UUID()
    private var playerStateOperationMayResumePlayback = false
    private var playerFrameProductionIsInFlight = false
    private var playerFrameProductionWaiters: [CheckedContinuation<Void, Never>] = []
    private var nextPresentedFrameNumber: UInt64?
    private var didHandleInitialLaunchArguments = false
    #if SWAN_SONG_AUTOMATION
    private let allowsAutomatedPCV2InputProbe: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["SWAN_SONG_ALLOW_AUTOMATED_PCV2_INPUT"] == "1"
            && environment["SWAN_SONG_HEADLESS"] == "1"
            && environment["SWAN_SONG_DATA_DIR"]?.isEmpty == false
    }()
    #else
    private let allowsAutomatedPCV2InputProbe = false
    #endif
    private var activeTranslationROMURL: URL?
    private var translationRouteRecorder: TranslationRouteRecorder?
    private var translationReplayRoute: TranslationRoute?
    private var translationReplayFrameIndex: UInt64 = 0
    private var translationEvidenceRoute: TranslationRoute?
    private var translationEvidenceRouteFrameNumber: UInt64?
    private var translationComparisonRoute: TranslationRoute?
    private var translationSuiteQueue: [TranslationRouteSummary] = []
    private var translationSuiteStartedAt: Date?
    private var translationComparisonIsTransitioning = false
    private var translationVisualDivergenceTask: Task<Void, Never>?
    private var translationVisualDivergenceRoute: TranslationRoute?
    private var translationVisualDivergenceGeneration = UUID()
    private var translationTextIntakeTask: Task<Void, Never>?
    private var translationTextIntakeGeneration = UUID()
    private var translationTextIntakeCapture: TranslationCaptureImage?
    private var translationTextIntakeEvidenceID: TranslationEvidenceSummary.ID?
    private var ephemeralTranslationGameID: GameRecord.ID?
    private var automatedTranslationRouteEndFrame = ProcessInfo.processInfo.environment[
        "SWAN_SONG_TRANSLATION_ROUTE_END_FRAME"
    ].flatMap(UInt64.init)
    private var automatedTranslationEvidenceFrame = ProcessInfo.processInfo.environment[
        "SWAN_SONG_TRANSLATION_EVIDENCE_FRAME"
    ].flatMap(UInt64.init)
    private var automatedTranslationComparisonAfterRecording = ProcessInfo.processInfo.environment[
        "SWAN_SONG_TRANSLATION_COMPARE_AFTER_RECORDING"
    ] == "1"
    private let automatedTranslationTestCaseName = ProcessInfo.processInfo.environment[
        "SWAN_SONG_TRANSLATION_TEST_CASE_NAME"
    ]
    private let automatedTranslationTestCaseNote = ProcessInfo.processInfo.environment[
        "SWAN_SONG_TRANSLATION_TEST_CASE_NOTE"
    ] ?? ""
    private let automatedTranslationPCV2InputProbe = ProcessInfo.processInfo.environment[
        "SWAN_SONG_TRANSLATION_PCV2_INPUT_PROBE"
    ] == "1"
    private let translationProjectDefaultsKey = "SwanSong.translationProjectPath"
    private let translationWorkspaceIsEnvironmentConfigured: Bool

    init(
        store: GameLibraryStore = .defaultStore(),
        saveStore: GameSaveStore = .defaultStore(),
        stateStore: GameStateStore = .defaultStore(),
        managedGameStore: ManagedGameStore = .defaultStore(),
        homebrewCatalogURL: URL = HomebrewCatalogClient.catalogURL,
        homebrewCatalogClientOverride: HomebrewCatalogClient? = nil,
        homebrewCatalogCacheStore: HomebrewCatalogCacheStore? = nil,
        homebrewCatalogSignatureVerifier: HomebrewCatalogSignatureVerifier = HomebrewCatalogProductionTrust.verifier,
        homebrewCatalogHighWaterStore: any HomebrewCatalogHighWaterStoring = HomebrewCatalogKeychainHighWaterStore(),
        homebrewCatalogMinimumRevision: Int = HomebrewCatalogProductionTrust.minimumRevision,
        artworkStore: GameArtworkStore = .defaultStore(),
        controllerProfileStore: ControllerProfileStore = .defaultStore(),
        translationWorkspaceStore: TranslationWorkspaceStore = .defaultStore(),
        engineCanExecuteOverride: Bool? = nil,
        studioWorkspaceOverride: SwanSDKWorkspaceModel? = nil,
        storyForgeWorkspaceOverride: StoryForgeWorkspaceModel? = nil
    ) {
        self.store = store
        self.saveStore = saveStore
        self.stateStore = stateStore
        self.managedGameStore = managedGameStore
        self.homebrewCatalogClient = homebrewCatalogClientOverride
            ?? HomebrewCatalogClient(sourceURL: homebrewCatalogURL)
        self.homebrewCatalogCacheStore = homebrewCatalogCacheStore
            ?? HomebrewCatalogCacheStore(
                directoryURL: store.fileURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("Homebrew", isDirectory: true)
            )
        self.homebrewCatalogSignatureVerifier = homebrewCatalogSignatureVerifier
        self.homebrewCatalogIsConfigured = !homebrewCatalogSignatureVerifier
            .trustedKeys.isEmpty
        self.homebrewCatalogHighWaterStore = homebrewCatalogHighWaterStore
        self.homebrewCatalogMinimumRevision = homebrewCatalogMinimumRevision
        self.artworkStore = artworkStore
        self.batchImporter = GameBatchImporter(managedStore: managedGameStore)
        self.controllerProfileStore = controllerProfileStore
        self.translationWorkspaceStore = translationWorkspaceStore
        self.debugToolsEnabled = UserDefaults.standard.bool(
            forKey: Self.debugToolsDefaultsKey
        )
        #if SWAN_SONG_AUTOMATION
        if ProcessInfo.processInfo.environment["SWAN_SONG_ENABLE_DEBUG_TOOLS"] == "1" {
            self.debugToolsEnabled = true
        }
        #endif
        self.translationWorkspaceIsEnvironmentConfigured = ProcessInfo.processInfo.environment[
            "SWAN_SONG_TRANSLATION_PROJECT"
        ] != nil
        if let engineCanExecuteOverride {
            engineBackendName = engineCanExecuteOverride ? "Fixture" : "Unavailable"
            engineBuildID = engineCanExecuteOverride ? "fixture-engine-v1" : "unavailable"
            engineCanExecute = engineCanExecuteOverride
        } else if let engine = try? EngineSession() {
            engineBackendName = engine.backendName
            engineBuildID = engine.buildID
            engineCanExecute = engine.capabilities.contains(.execution)
        } else {
            engineBackendName = "Unavailable"
            engineBuildID = "unavailable"
            engineCanExecute = false
        }
        studioWorkspace = studioWorkspaceOverride ?? SwanSDKWorkspaceModel(
            engineName: engineBackendName,
            engineBuildID: engineBuildID
        )
        storyForgeWorkspace = storyForgeWorkspaceOverride ?? StoryForgeWorkspaceModel()
        controllerProfile = (try? controllerProfileStore.load()) ?? .default
        controller.onChange = { [weak self] elements in
            self?.handleControllerElements(elements)
        }
        controller.onConnectionChange = { [weak self] name, availableElements, batterySummary in
            self?.connectedControllerName = name
            self?.controllerAvailableElements = availableElements
            self?.controllerBatterySummary = batterySummary
            if name == nil {
                self?.controllerLearningControl = nil
            }
        }
        connectedControllerName = controller.connectedControllerName
        controllerBatterySummary = controller.batterySummary
        controllerPhysicalElements = controller.pressedElements
        controllerAvailableElements = controller.availableElements
        controllerInput = controllerProfile.input(for: controllerPhysicalElements)
        homebrewCatalogConsentGranted = UserDefaults.standard.bool(
            forKey: Self.homebrewCatalogConsentDefaultsKey
        )
        do {
            games = try store.load().games
            loadGameArtwork()
            try? managedGameStore.prune(
                retaining: games.compactMap(\.managedROM)
            )
        } catch {
            presentedError = "The game library could not be read: \(error.localizedDescription)"
        }
        loadCachedHomebrewCatalog()
        loadTranslationWorkspace()
        refreshManagedGameHealth()
    }

    func handleInitialLaunchArguments() {
        guard !didHandleInitialLaunchArguments else { return }
        didHandleInitialLaunchArguments = true
        if ProcessInfo.processInfo.environment["SWAN_SONG_TRANSLATION_APPROVE_BASELINE"] == "1",
           translationProject != nil {
            approveLatestPatchedEvidenceAsBaseline()
            return
        }
        if ProcessInfo.processInfo.environment["SWAN_SONG_TRANSLATION_VERIFY_SUITE"] == "1",
           translationProject != nil,
           !translationRoutes.isEmpty {
            verifyTranslationSuite()
            return
        }
        if ProcessInfo.processInfo.environment["SWAN_SONG_TRANSLATION_VERIFY_ROUTE"] == "1",
           translationProject != nil,
           latestTranslationRoute != nil {
            verifyLatestTranslationRoute()
            return
        }
        if ProcessInfo.processInfo.environment[
            "SWAN_SONG_TRANSLATION_LOCATE_FIRST_CHANGE"
        ] == "1",
           translationProject != nil,
           latestTranslationRoute != nil {
            locateFirstTranslationVisualChange()
            return
        }
        if ProcessInfo.processInfo.environment["SWAN_SONG_TRANSLATION_BUILD_AND_RUN"] == "1",
           translationProject != nil {
            buildAndRunTranslation()
            return
        }
        if let roleValue = ProcessInfo.processInfo.environment["SWAN_SONG_TRANSLATION_ROLE"],
           let role = TranslationROMRole(rawValue: roleValue.lowercased()),
           translationProject != nil {
            playTranslationROM(role)
            return
        }
        if let folderPath = ProcessInfo.processInfo.environment[
            "SWAN_SONG_IMPORT_GAME_FOLDER"
        ], !folderPath.isEmpty {
            importGames(in: URL(fileURLWithPath: folderPath, isDirectory: true))
            return
        }
        if ProcessInfo.processInfo.environment["SWAN_SONG_SELECT_FIRST_GAME"] == "1" {
            selectedGameID = games.first?.id
            return
        }
        let environmentROM = ProcessInfo.processInfo.environment["SWAN_SONG_INITIAL_ROM"]
        let argumentROM = CommandLine.arguments.dropFirst().first(where: {
            ["ws", "wsc", "pc2", "pcv2", "zip"].contains(
                URL(fileURLWithPath: $0).pathExtension.lowercased()
            )
        })
        guard let argument = environmentROM ?? argumentROM else { return }
        importGame(at: URL(fileURLWithPath: argument))
    }

    var visibleGames: [GameRecord] {
        switch section {
        case .library:
            games
        case .favorites:
            games.filter(\.isFavorite)
        case .recent:
            games
                .filter { $0.lastPlayedAt != nil }
                .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        case .homebrew:
            []
        case .pocketCore:
            []
        case .translationLab:
            []
        case .storyForge:
            []
        case .gameStudio:
            []
        }
    }

    var homebrewCatalogEntries: [HomebrewCatalogEntry] {
        (homebrewCatalog?.entries ?? []).sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    func latestHomebrewRelease(
        for entry: HomebrewCatalogEntry
    ) -> HomebrewCatalogRelease? {
        entry.releases.max(by: Self.homebrewReleaseSortsBefore)
    }

    func installedHomebrewGame(for entry: HomebrewCatalogEntry) -> GameRecord? {
        games.first { game in
            game.homebrewCatalogOrigin?.catalogID == homebrewCatalog?.catalogID
                && game.homebrewCatalogOrigin?.entryID == entry.id
        }
    }

    func homebrewUpdateIsAvailable(for entry: HomebrewCatalogEntry) -> Bool {
        guard let installed = installedHomebrewGame(for: entry),
              let origin = installed.homebrewCatalogOrigin,
              let release = latestHomebrewRelease(for: entry),
              origin.assetSHA256.lowercased()
                != release.asset.sha256.lowercased() else { return false }
        guard origin.version != release.version else { return false }
        let installedReleasedAt = origin.releasedAt
            ?? entry.releases.first(where: {
                $0.version == origin.version
                    && $0.asset.sha256 == origin.assetSHA256
            })?.releasedAt
        guard let installedReleasedAt else { return false }
        return Self.homebrewReleaseSortsBefore(
            releasedAt: installedReleasedAt,
            version: origin.version,
            digest: origin.assetSHA256,
            than: release.releasedAt,
            version: release.version,
            digest: release.asset.sha256
        )
    }

    func showInstalledHomebrewInLibrary(_ entry: HomebrewCatalogEntry) {
        guard let game = installedHomebrewGame(for: entry) else { return }
        selectedGameID = game.id
        section = .library
    }

    func playInstalledHomebrew(_ entry: HomebrewCatalogEntry) {
        guard let game = installedHomebrewGame(for: entry) else { return }
        guard homebrewInstallTask == nil, !gameImportIsBusy else {
            homebrewInstallIssueEntryID = entry.id
            homebrewInstallIssue = "Finish the current library operation before playing this game."
            return
        }
        playerReturnSection = .homebrew
        selectedGameID = game.id
        play(game.id)
    }

    func enableHomebrewCatalog() {
        guard homebrewCatalogIsConfigured else {
            homebrewCatalogIssue = "The signed Homebrew Catalog has not been published for this SwanSong build yet."
            return
        }
        homebrewCatalogConsentGranted = true
        UserDefaults.standard.set(
            true,
            forKey: Self.homebrewCatalogConsentDefaultsKey
        )
        refreshHomebrewCatalog()
    }

    func declineHomebrewCatalog() {
        section = .library
    }

    func stopUsingHomebrewCatalog() {
        guard homebrewInstallTask == nil else {
            presentedNotice = "Finish or cancel the current Homebrew install before stopping use of the catalog."
            return
        }
        homebrewCatalogRefreshGeneration = UUID()
        homebrewCatalogRefreshTask?.cancel()
        homebrewCatalogRefreshTask = nil
        homebrewCatalogIsLoading = false
        homebrewCatalogRefreshAttemptedThisSession = false
        homebrewCatalogConsentGranted = false
        UserDefaults.standard.removeObject(
            forKey: Self.homebrewCatalogConsentDefaultsKey
        )
        homebrewCatalog = nil
        selectedHomebrewEntryID = nil
        homebrewCatalogLastUpdatedAt = nil
        homebrewCatalogIssue = nil

        do {
            try homebrewCatalogCacheStore.remove()
            presentedNotice = "Stopped using the Homebrew Catalog and removed its saved catalog copy. Installed games were not changed."
        } catch {
            presentedError = "SwanSong stopped using the Homebrew Catalog, but its saved catalog copy could not be removed safely. \(error.localizedDescription)"
        }
    }

    func loadHomebrewCatalogIfNeeded() {
        // Catalog network access is always attached to an explicit Load or
        // Refresh action. Launch and navigation may use a locally cached,
        // reverified catalog but never create a request on their own.
    }

    func refreshHomebrewCatalog() {
        guard homebrewCatalogIsConfigured,
              homebrewCatalogConsentGranted else { return }
        guard homebrewCatalogRefreshTask == nil,
              homebrewInstallTask == nil else { return }
        homebrewCatalogRefreshAttemptedThisSession = true
        homebrewCatalogIssue = nil
        homebrewCatalogIsLoading = true
        let client = homebrewCatalogClient
        let cacheStore = homebrewCatalogCacheStore
        let verifier = homebrewCatalogSignatureVerifier
        let highWaterStore = homebrewCatalogHighWaterStore
        let minimumRevision = homebrewCatalogMinimumRevision
        let sourceURL = client.catalogSourceURL
        let refreshGeneration = UUID()
        homebrewCatalogRefreshGeneration = refreshGeneration
        homebrewCatalogRefreshTask = Task { [weak self] in
            defer {
                if self?.homebrewCatalogRefreshGeneration == refreshGeneration {
                    self?.homebrewCatalogIsLoading = false
                    self?.homebrewCatalogRefreshTask = nil
                }
            }
            do {
                var wireBundle: HomebrewCatalogWireBundle?
                var authenticated: AuthenticatedHomebrewCatalog?
                for attempt in 0..<2 {
                    let candidate = try await client.fetchCatalogBundle()
                    do {
                        let verified = try await Task.detached(
                            priority: .userInitiated
                        ) {
                            try verifier.verify(
                                catalogData: candidate.catalogData,
                                signatureData: candidate.signatureData
                            )
                        }.value
                        wireBundle = candidate
                        authenticated = verified
                        break
                    } catch let error as HomebrewCatalogSignatureError
                        where attempt == 0
                            && Self.shouldRetryHomebrewCatalogPair(error) {
                        continue
                    }
                }
                guard let wireBundle, let authenticated else {
                    throw HomebrewCatalogSignatureError.noTrustedSignature
                }
                try Task.checkCancellation()
                let catalog = try await Task.detached(priority: .userInitiated) {
                    try Self.decodeHomebrewCatalog(
                        wireBundle.catalogData,
                        sourceURL: sourceURL
                    )
                }.value
                try Task.checkCancellation()
                guard let self,
                      homebrewCatalogRefreshGeneration == refreshGeneration,
                      homebrewCatalogConsentGranted,
                      homebrewCatalogIsConfigured else { return }

                // This small commit is intentionally actor-isolated. Stop Using
                // cannot interleave between the final ownership check and these
                // writes, and detached verification/decode has no side effects
                // that could recreate the cache after cancellation.
                let currentState = try highWaterStore.load(
                    catalogID: catalog.catalogID
                )
                let nextState = try HomebrewCatalogRollbackPolicy.nextState(
                    catalog: catalog,
                    authenticated: authenticated,
                    trustedKeys: verifier.trustedKeys,
                    minimumRevision: minimumRevision,
                    currentState: currentState
                )
                try Task.checkCancellation()
                let cacheBundle = HomebrewCatalogCachedBundle(
                    catalogData: wireBundle.catalogData,
                    signatureData: wireBundle.signatureData
                )
                // Re-read, compare, advance trust, and publish the dependent
                // cache while holding one cross-process lock. A stale process
                // therefore cannot replace a newer process's verified cache.
                try highWaterStore.advance(
                    to: nextState,
                    publishingWhileLocked: {
                        try cacheStore.store(cacheBundle)
                    }
                )
                homebrewCatalog = catalog
                homebrewCatalogLastUpdatedAt = catalog.generatedAt
                if selectedHomebrewEntryID == nil {
                    selectedHomebrewEntryID = catalog.entries.first?.id
                }
                homebrewCatalogIssue = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      !Task.isCancelled,
                      homebrewCatalogRefreshGeneration == refreshGeneration,
                      homebrewCatalogConsentGranted else { return }
                appDiagnostic(
                    "homebrew catalog refresh failed reason=\(String(reflecting: error))"
                )
                if homebrewCatalog == nil {
                    homebrewCatalogIssue = "The Homebrew Catalog could not be loaded. \(error.localizedDescription)"
                } else if error is HomebrewCatalogError
                            || error is HomebrewCatalogAppError
                            || error is HomebrewCatalogSignatureError
                            || error is HomebrewCatalogRollbackError
                            || error is HomebrewCatalogHighWaterStoreError {
                    homebrewCatalogIssue = "The catalog update could not be verified. SwanSong is showing the last verified catalog saved on this Mac."
                } else {
                    homebrewCatalogIssue = "GitHub could not be reached. SwanSong is showing the last verified catalog saved on this Mac."
                }
            }
        }
    }

    func cancelHomebrewInstall() {
        homebrewInstallTask?.cancel()
    }

    func installHomebrew(_ entry: HomebrewCatalogEntry) {
        guard let catalog = homebrewCatalog,
              let entry = catalog.entries.first(where: { $0.id == entry.id }),
              let release = latestHomebrewRelease(for: entry) else { return }
        guard homebrewInstallTask == nil,
              !gameImportIsBusy,
              repairingGameID == nil else {
            homebrewInstallIssueEntryID = entry.id
            homebrewInstallIssue = "Finish the current library operation before adding this game."
            return
        }
        if let installed = installedHomebrewGame(for: entry),
           installed.id == playingGameID {
            homebrewInstallIssueEntryID = entry.id
            homebrewInstallIssue = "Stop this game before installing an update."
            return
        }

        let previousGames = games
        let client = homebrewCatalogClient
        let managedGameStore = managedGameStore
        homebrewInstallingEntryID = entry.id
        homebrewInstallProgress = 0
        homebrewInstallPhase = "Downloading…"
        homebrewInstallIssue = nil
        homebrewInstallIssueEntryID = nil
        gameImportIsBusy = true
        homebrewInstallTask = Task { [weak self] in
            guard let model = self else { return }
            var createdReference: ManagedGameReference?
            defer {
                model.homebrewInstallingEntryID = nil
                model.homebrewInstallProgress = nil
                model.homebrewInstallPhase = nil
                model.homebrewInstallTask = nil
                model.gameImportIsBusy = false
            }
            do {
                let data = try await client.fetchAsset(release.asset) { progress in
                    Task { @MainActor [weak model] in
                        guard model?.homebrewInstallingEntryID == entry.id else { return }
                        model?.homebrewInstallProgress = progress
                    }
                }
                try Task.checkCancellation()
                model.homebrewInstallPhase = "Verifying and adding to Library…"
                let result = try await Task.detached(priority: .userInitiated) {
                    try HomebrewCatalogInstaller(assetData: data).install(
                        entry: entry,
                        release: release,
                        catalogID: catalog.catalogID,
                        into: previousGames,
                        managedStore: managedGameStore
                    )
                }.value
                createdReference = result.createdReference
                try Task.checkCancellation()
                guard model.games == previousGames else {
                    throw HomebrewCatalogAppError.libraryChanged
                }
                model.games = result.games
                model.selectedGameID = result.gameID
                do {
                    try model.persist()
                } catch {
                    model.games = previousGames
                    throw error
                }
                model.invalidateManagedGameHealthScan()
                model.managedGameHealth[result.gameID] = .healthy
                model.checkingManagedGameIDs.remove(result.gameID)
                try? model.managedGameStore.prune(
                    retaining: model.games.compactMap(\.managedROM)
                )
                model.homebrewInstallIssue = nil
                model.homebrewInstallIssueEntryID = nil
                model.presentedNotice = switch result.action {
                case .installed, .adopted:
                    "Added \(entry.title) to Library."
                case .updated:
                    "Updated \(entry.title) to version \(release.version) without changing its saves or library identity."
                case .unchanged:
                    "\(entry.title) is already installed."
                }
            } catch is CancellationError {
                if let createdReference {
                    model.rollbackManagedImports(
                        [createdReference],
                        retaining: previousGames
                    )
                }
                model.homebrewInstallIssue = nil
                model.homebrewInstallIssueEntryID = nil
            } catch {
                if let createdReference {
                    model.rollbackManagedImports(
                        [createdReference],
                        retaining: model.games
                    )
                }
                model.homebrewInstallIssueEntryID = entry.id
                model.homebrewInstallIssue = "\(entry.title) was not installed. \(error.localizedDescription)"
            }
        }
    }

    private nonisolated static func homebrewReleaseSortsBefore(
        _ left: HomebrewCatalogRelease,
        _ right: HomebrewCatalogRelease
    ) -> Bool {
        homebrewReleaseSortsBefore(
            releasedAt: left.releasedAt,
            version: left.version,
            digest: left.asset.sha256,
            than: right.releasedAt,
            version: right.version,
            digest: right.asset.sha256
        )
    }

    private nonisolated static func homebrewReleaseSortsBefore(
        releasedAt candidateDate: Date?,
        version candidateVersion: String,
        digest candidateDigest: String,
        than comparisonDate: Date?,
        version comparisonVersion: String,
        digest comparisonDigest: String
    ) -> Bool {
        switch (candidateDate, comparisonDate) {
        case let (candidateDate?, comparisonDate?) where candidateDate != comparisonDate:
            return candidateDate < comparisonDate
        case (nil, .some):
            return true
        case (.some, nil):
            return false
        default:
            if candidateVersion != comparisonVersion {
                return candidateVersion < comparisonVersion
            }
            return candidateDigest < comparisonDigest
        }
    }

    var selectedGame: GameRecord? {
        games.first { $0.id == selectedGameID }
    }

    func gameConfidence(for game: GameRecord) -> GameConfidence {
        let romIntegrity: GameROMIntegrity
        if game.managedROM == nil {
            romIntegrity = game.metadata.checksumIsValid ? .unmanaged : .checksumMismatch
        } else if checkingManagedGameIDs.contains(game.id) {
            romIntegrity = .checking
        } else {
            romIntegrity = switch managedGameHealth[game.id] {
            case .healthy:
                game.metadata.checksumIsValid ? .verified : .checksumMismatch
            case .missing:
                .missing
            case .changed:
                .changed
            case .invalidReference:
                .invalidReference
            case nil:
                .checking
            }
        }

        let launchReadiness: GameLaunchReadiness
        switch romIntegrity {
        case .checking:
            launchReadiness = .checkingGame
        case .missing, .changed, .invalidReference:
            launchReadiness = .gameUnavailable
        case .verified, .checksumMismatch, .unmanaged:
            if !engineCanExecute {
                launchReadiness = .engineUnavailable
            } else {
                launchReadiness = .ready
            }
        }

        return GameConfidence(
            launchReadiness: launchReadiness,
            compatibility: game.compatibilityEvidence?.status ?? .untested,
            romIntegrity: romIntegrity
        )
    }

    var playingGame: GameRecord? {
        games.first { $0.id == playingGameID }
    }

    var isPlaying: Bool {
        playingGameID != nil
    }

    var playerFailureCanRetry: Bool {
        playerFailure != nil && playerFailureRetryIntent != nil
    }

    var playerFailureRetryTitle: String {
        guard case let .translation(continuation, _, _)? = playerFailureRetryIntent else {
            return "Try Again"
        }
        switch continuation {
        case .play:
            return "Try Again"
        case .replay:
            return "Restart Replay"
        case .verifyRoute:
            return "Restart Verification"
        case .verifySuite:
            return "Restart Suite"
        case .locateVisualDivergence:
            return "Restart First-Change Search"
        }
    }

    var playerFailureReturnTitle: String {
        playerReturnTitle
    }

    var playerReturnTitle: String {
        "Back to \(playerReturnDestinationTitle)"
    }

    var playerReturnDestinationTitle: String {
        activeTranslationRole == nil
            ? playerReturnSection.rawValue
            : Section.translationLab.rawValue
    }

    var playerIsInteractive: Bool {
        isPlaying
            && playerFailure == nil
            && !isFinalizingFailedSession
            && !terminationIsInProgress
            && activeRunner != nil
    }

    var canAdvanceFrame: Bool {
        playerIsInteractive
            && isPaused
            && currentFrame != nil
            && !translationComparisonIsActive
            && !translationComparisonIsTransitioning
            && !translationRouteRecordingIsPreparing
            && !isCapturingTranslationEvidence
            && playerStateOperation == nil
            && !isRewindPresented
    }

    private var playerControlPolicy: PlayerControlPolicy {
        PlayerControlPolicy(
            playerIsInteractive: playerIsInteractive,
            hasCurrentFrame: currentFrame != nil,
            stateOperationIsBusy: playerStateOperation != nil,
            translationComparisonIsActive: translationComparisonIsActive,
            translationComparisonIsTransitioning: translationComparisonIsTransitioning,
            translationRouteRecordingIsPreparing: translationRouteRecordingIsPreparing,
            translationRouteIsRecording: translationRouteIsRecording
        )
    }

    var canTogglePause: Bool {
        playerControlPolicy.canTogglePause && !isRewindPresented
    }

    var canResetGame: Bool {
        playerControlPolicy.canResetGame && !isRewindPresented
    }

    var canToggleFastForward: Bool {
        playerControlPolicy.canToggleFastForward && !isRewindPresented
    }

    var selectedRewindCheckpoint: RewindCheckpoint? {
        guard let selectedRewindCheckpointID else { return nil }
        return rewindCheckpoints.first { $0.id == selectedRewindCheckpointID }
    }

    var rewindRetainedSeconds: TimeInterval {
        guard let first = rewindCheckpoints.first,
              let last = rewindCheckpoints.last,
              last.frameNumber >= first.frameNumber else { return 0 }
        return Double(last.frameNumber - first.frameNumber)
            / rewindBuffer.configuration.nominalFramesPerSecond
    }

    var canShowRewind: Bool {
        playerIsInteractive
            && currentFrame != nil
            && rewindCheckpoints.count >= 2
            && playerStateOperation == nil
            && !playerStateNeedsNaturalFrame
            && !isStateTimelinePresented
            && !translationRouteIsRecording
            && !translationRouteRecordingIsPreparing
            && !translationReplayIsActive
            && !translationComparisonIsActive
            && !translationComparisonIsTransitioning
            && !isCapturingTranslationEvidence
    }

    var canResumeSelectedRewindCheckpoint: Bool {
        canShowRewind && isRewindPresented && selectedRewindCheckpoint != nil
    }

    func rewindSecondsBack(for checkpoint: RewindCheckpoint) -> TimeInterval {
        guard let newest = rewindCheckpoints.last,
              newest.frameNumber >= checkpoint.frameNumber else { return 0 }
        return Double(newest.frameNumber - checkpoint.frameNumber)
            / rewindBuffer.configuration.nominalFramesPerSecond
    }

    var playerStateOperationIsBusy: Bool {
        playerStateOperation != nil || playerStateNeedsNaturalFrame
    }

    var canUndoStateLoad: Bool {
        guard let rollback = stateLoadUndoPoint else { return false }
        return playerIsInteractive
            && playerStateOperation == nil
            && !playerStateNeedsNaturalFrame
            && rollback.sessionGeneration == emulationGeneration
            && rollback.gameID == playingGameID
    }

    var translationReplayIsActive: Bool {
        translationReplayRoute != nil
    }

    var translationComparisonIsActive: Bool {
        translationComparisonPhase != nil
    }

    var selectedTranslationRouteProofIssue: String? {
        latestTranslationRoute?.proofEligibility.issue
    }

    var canReplayLatestTranslationRoute: Bool {
        activeTranslationRole != nil
            && playerIsInteractive
            && !playerStateOperationIsBusy
            && latestTranslationRoute?.proofEligibility == .proofReady
            && !translationRouteIsRecording
            && !translationRouteRecordingIsPreparing
            && !translationReplayIsActive
            && !translationComparisonIsActive
    }

    var canStartCleanBootRouteRecording: Bool {
        activeTranslationRole == .original
            && playerIsInteractive
            && !playerStateOperationIsBusy
            && !isLaunchingGame
            && !translationRouteIsRecording
            && !translationRouteRecordingIsPreparing
            && !translationReplayIsActive
            && !translationComparisonIsActive
    }

    var translationSuiteBlockingIssue: String? {
        guard !translationRoutes.isEmpty else { return "Record at least one route test first." }
        let invalidCount = translationRoutes.count {
            switch $0.route.proofEligibility {
            case .invalidV2, .invalidV3: true
            default: false
            }
        }
        if invalidCount > 0 {
            return "\(invalidCount) route\(invalidCount == 1 ? " is" : "s are") invalid. Repair or re-record \(invalidCount == 1 ? "it" : "them") before running the full suite."
        }
        let rtcMigrationCount = translationRoutes.count {
            $0.route.proofEligibility == .rtcStartUnknown
        }
        if rtcMigrationCount > 0 {
            return "\(rtcMigrationCount) version 2 route\(rtcMigrationCount == 1 ? " did" : "s did") not record RTC mode or seed. Re-record every version 2 case with deterministic UTC \(TranslationRouteRTCContext.proofSeedUTC) (Unix \(TranslationRouteRTCContext.proofSeedUnixSeconds)) before running the full suite."
        }
        let legacyCount = translationRoutes.count {
            $0.route.proofEligibility == .legacyStartUnknown
        }
        guard legacyCount > 0 else { return nil }
        return "\(legacyCount) legacy route\(legacyCount == 1 ? " has" : "s have") an unknown start state. Re-record every legacy case from a clean boot before running the full suite."
    }

    var canVerifyLatestTranslationRoute: Bool {
        engineCanExecute
            && !isPlaying
            && !translationToolIsRunning
            && translationComparisonPhase == nil
            && !translationSuiteIsActive
            && latestTranslationRoute?.proofEligibility == .proofReady
            && translationOriginalROMAvailable
    }

    var canLocateFirstTranslationVisualChange: Bool {
        engineCanExecute
            && !isPlaying
            && !translationToolIsRunning
            && translationComparisonPhase == nil
            && !translationSuiteIsActive
            && !translationVisualDivergenceIsRunning
            && latestTranslationRoute?.proofEligibility == .proofReady
            && translationOriginalROMAvailable
            && translationPatchedROMAvailable
    }

    var canVerifyTranslationSuite: Bool {
        engineCanExecute
            && !isPlaying
            && !translationToolIsRunning
            && translationComparisonPhase == nil
            && !translationSuiteIsActive
            && !translationRoutes.isEmpty
            && translationSuiteBlockingIssue == nil
            && translationOriginalROMAvailable
    }

    var translationSuiteIsActive: Bool {
        translationSuiteCurrentCaseIndex != nil && !translationSuiteQueue.isEmpty
    }

    var latestTranslationSuiteRun: TranslationSuiteRun? {
        translationSuiteRuns.first?.run
    }

    var selectedTranslationEvidenceRouteSummary: TranslationRouteSummary? {
        guard let route = selectedTranslationEvidence?.manifest?.route else { return nil }
        return translationRoutes.first { $0.routeDigest == route }
    }

    var selectedTranslationEvidenceBaseline: TranslationRouteBaselineSummary? {
        guard let route = selectedTranslationEvidenceRouteSummary else { return nil }
        return translationBaseline(for: route)
    }

    var selectedTranslationEvidenceIsBaseline: Bool {
        guard
            let evidence = selectedTranslationEvidence,
            let baseline = selectedTranslationEvidenceBaseline
        else { return false }
        return baseline.isIntact
            && baseline.baseline.evidenceName == evidence.artifact.name
    }

    var selectedTranslationEvidenceCanBecomeBaseline: Bool {
        guard
            let evidence = selectedTranslationEvidence,
            evidence.isIntact,
            evidence.manifest?.romRole == .patched,
            evidence.review?.status == .approved,
            evidence.reviewIssue == nil,
            selectedTranslationEvidenceRouteSummary != nil,
            !translationEvidenceReviewHasChanges
        else { return false }
        return !selectedTranslationEvidenceIsBaseline
    }

    var translationSuiteCurrentCaseName: String? {
        guard
            let index = translationSuiteCurrentCaseIndex,
            translationSuiteQueue.indices.contains(index)
        else { return nil }
        return translationSuiteName(for: translationSuiteQueue[index])
    }

    var translationSuiteProgress: Double? {
        guard
            let index = translationSuiteCurrentCaseIndex,
            translationSuiteTotalCaseCount > 0
        else { return nil }
        let caseProgress = translationComparisonProgress ?? 0
        return min(
            (Double(index) + caseProgress) / Double(translationSuiteTotalCaseCount),
            1
        )
    }

    func translationBaseline(
        for route: TranslationRouteSummary
    ) -> TranslationRouteBaselineSummary? {
        translationBaselines.first {
            $0.baseline.route == route.routeDigest
        }
    }

    func latestTranslationSuiteResult(
        for route: TranslationRouteSummary
    ) -> TranslationSuiteCaseResult? {
        latestTranslationSuiteRun?.cases.first {
            $0.route == route.routeDigest
        }
    }

    var translationComparisonProgress: Double? {
        guard let phase = translationComparisonPhase else { return nil }
        switch phase {
        case .preparing:
            return 0.04
        case .replaying(.original):
            return 0.08 + 0.36 * (translationReplayProgress ?? 0)
        case .capturing(.original):
            return 0.48
        case .replaying(.patched):
            return 0.52 + 0.36 * (translationReplayProgress ?? 0)
        case .capturing(.patched):
            return 0.96
        }
    }

    var selectedTranslationRouteSummary: TranslationRouteSummary? {
        guard let latestTranslationRouteURL else { return nil }
        return translationRoutes.first {
            $0.fileURL.standardizedFileURL.path
                == latestTranslationRouteURL.standardizedFileURL.path
        }
    }

    var translationTestCaseHasChanges: Bool {
        guard let summary = selectedTranslationRouteSummary else { return false }
        return (summary.testCase?.name ?? "") != translationTestCaseName
            || (summary.testCase?.note ?? "") != translationTestCaseNote
    }

    var selectedTranslationEvidence: TranslationEvidenceSummary? {
        translationEvidence.first { $0.id == selectedTranslationEvidenceID }
    }

    var selectedTranslationPrivateArtifact: TranslationPrivateArtifactSummary? {
        translationPrivateArtifacts.first {
            $0.id == selectedTranslationPrivateArtifactID
        }
    }

    var canStartTranslationTextIntake: Bool {
        guard let evidence = selectedTranslationEvidence else { return false }
        return evidence.isIntact
            && evidence.framePNG != nil
            && !translationTextIntakeIsRecognizing
    }

    var translationTextIntakeImagePixelSize: CGSize? {
        guard let capture = translationTextIntakeCapture else { return nil }
        return CGSize(width: capture.pixelWidth, height: capture.pixelHeight)
    }

    var translationTextIntakeLines: [TranslationTextIntakeLine] {
        translationTextIntakeSession?.lines ?? []
    }

    var translationTextIntakeCanSave: Bool {
        guard let session = translationTextIntakeSession else { return false }
        return !session.lines.isEmpty
            && (session.state == .reviewing || session.state == .readyToExport)
    }

    var selectedTranslationEvidenceHasTextIntake: Bool {
        guard let evidence = selectedTranslationEvidence,
              let project = translationProject else { return false }
        return (try? translationEvidenceStore.privateArtifactExists(
            .textIntake,
            evidence: evidence,
            project: project
        )) == true
    }

    var translationDraftLines: [TranslationDraftLine] {
        translationDraftSession?.lines ?? []
    }

    var translationDraftCompleteness: TranslationDraftCompleteness? {
        translationDraftSession?.completeness
    }

    var translationDraftHasAnyTargets: Bool {
        translationDraftLines.contains { line in
            !(translationDraftTargetDrafts[line.id] ?? line.targetText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
    }

    var pairedTranslationEvidence: TranslationEvidenceSummary? {
        guard
            let selected = selectedTranslationEvidence,
            let selectedManifest = selected.manifest,
            let routeSHA256 = selectedManifest.route?.sha256
        else { return nil }
        return translationEvidence.first { candidate in
            guard
                candidate.id != selected.id,
                let manifest = candidate.manifest
            else { return false }
            return manifest.romRole != selectedManifest.romRole
                && manifest.route?.sha256 == routeSHA256
        }
    }

    var canInspectSelectedTranslationRAM: Bool {
        guard
            !translationRAMInspectionIsLoading,
            let selected = selectedTranslationEvidence,
            let pair = pairedTranslationEvidence,
            selected.isIntact,
            pair.isIntact,
            let selectedManifest = selected.manifest,
            let pairManifest = pair.manifest,
            selectedManifest.romRole != pairManifest.romRole,
            let selectedRoute = selectedManifest.route,
            selectedRoute == pairManifest.route,
            selectedManifest.frameNumber == pairManifest.frameNumber,
            TranslationRAMComparison.supportedByteCounts.contains(
                selectedManifest.internalRAM.byteCount
            ),
            selectedManifest.internalRAM.byteCount == pairManifest.internalRAM.byteCount
        else { return false }
        return true
    }

    func translationTestCaseCoverage(
        for route: TranslationRouteSummary
    ) -> TranslationTestCaseCoverage {
        let matching = translationEvidence.filter {
            $0.manifest?.route?.sha256 == route.routeDigest.sha256
        }
        let original = matching.first {
            $0.manifest?.romRole == .original
        }
        let patched = matching.first {
            $0.manifest?.romRole == .patched
        }
        let status: TranslationTestCaseStatus
        if matching.contains(where: { !$0.isIntact }) {
            status = .integrityIssue
        } else if original == nil, patched == nil {
            status = .notRun
        } else if original == nil || patched == nil {
            status = .partial
        } else {
            let reviews = [original?.review?.status, patched?.review?.status]
            if reviews.contains(.needsWork) {
                status = .needsWork
            } else if reviews.allSatisfy({ $0 == .approved }) {
                status = .approved
            } else {
                status = .readyForReview
            }
        }
        return TranslationTestCaseCoverage(
            original: original,
            patched: patched,
            status: status
        )
    }

    var translationEvidenceReviewHasChanges: Bool {
        guard let evidence = selectedTranslationEvidence else { return false }
        return evidence.review?.status ?? .unreviewed != translationEvidenceReviewStatus
            || evidence.review?.note ?? "" != translationEvidenceReviewNote
    }

    var translationOriginalROMAvailable: Bool {
        guard let project = translationProject else { return false }
        return (try? project.romURL(for: .original)) != nil
    }

    var translationPatchedROMAvailable: Bool {
        guard let project = translationProject else { return false }
        return (try? project.romURL(for: .patched)) != nil
    }

    var hasAutomatedTranslationLaunch: Bool {
        ProcessInfo.processInfo.environment["SWAN_SONG_TRANSLATION_VERIFY_ROUTE"] == "1"
            || ProcessInfo.processInfo.environment["SWAN_SONG_TRANSLATION_VERIFY_SUITE"] == "1"
            || ProcessInfo.processInfo.environment[
                "SWAN_SONG_TRANSLATION_LOCATE_FIRST_CHANGE"
            ] == "1"
            || ProcessInfo.processInfo.environment["SWAN_SONG_TRANSLATION_APPROVE_BASELINE"] == "1"
            || ProcessInfo.processInfo.environment["SWAN_SONG_TRANSLATION_BUILD_AND_RUN"] == "1"
            || ProcessInfo.processInfo.environment["SWAN_SONG_TRANSLATION_ROLE"] != nil
    }

    var canImportPocketSave: Bool {
        !isPlaying
            && !hasEmulationSessionPendingFinalization
            && !terminationIsInProgress
            && selectedGame.map(hasCartridgeSave) == true
    }

    var canExportPocketSave: Bool {
        retiringEmulationSession == nil
            && !isFinalizingFailedSession
            && !terminationIsInProgress
            && activeTranslationRole == nil
            && (playingGame ?? selectedGame).map(hasCartridgeSave) == true
    }

    var selectedGameCanPlay: Bool {
        !terminationIsInProgress && selectedGame.map(canPlayGame) == true
    }

    /// Semantic input for the hardware that is currently running. The normal
    /// WonderSwan path honors the player's persisted two-cluster profile.
    /// Pocket Challenge V2 instead follows its own labeled keypad and a
    /// conventional controller layout so no two physical keys collapse into
    /// one WonderSwan alias.
    var activePlayerInput: EngineInput {
        keyboardInput.union(gameplayControllerInput)
    }

    var activeGameplayControllerInput: EngineInput {
        gameplayControllerInput
    }

    func firmwareKind(for game: GameRecord) -> WonderSwanFirmwareKind {
        switch game.resolvedHardwareModel {
        case .pocketChallengeV2: .pocketChallengeV2
        case .wonderSwanColor, .swanCrystal: .color
        case .automatic, .wonderSwan: .monochrome
        }
    }

    func canPlayGame(_ game: GameRecord) -> Bool {
        !terminationIsInProgress
            && engineCanExecute
            && !checkingManagedGameIDs.contains(game.id)
            && repairingGameID != game.id
            && managedGameHealth[game.id] != .missing
            && managedGameHealth[game.id] != .changed
            && managedGameHealth[game.id] != .invalidReference
    }

    func chooseGame() {
        let panel = NSOpenPanel()
        panel.title = "Open a WonderSwan Game"
        panel.prompt = "Open Game"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        let contentTypes = ["ws", "wsc", "pc2", "pcv2", "zip"].compactMap {
            UTType(filenameExtension: $0, conformingTo: .data)
        }
        panel.allowedContentTypes = contentTypes.isEmpty ? [.data] : contentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importGame(at: url)
    }

    func canRevealGame(_ game: GameRecord) -> Bool {
        guard game.managedROM != nil else { return true }
        return managedGameHealth[game.id] == .healthy
            && !checkingManagedGameIDs.contains(game.id)
            && repairingGameID != game.id
    }

    func revealGame(_ id: GameRecord.ID) {
        guard let game = games.first(where: { $0.id == id }) else { return }
        let location: URL
        if let reference = game.managedROM {
            guard canRevealGame(game),
                  let managedLocation = try? managedGameStore.url(for: reference) else {
                presentedNotice = "Repair or finish checking this game before revealing its private copy."
                return
            }
            location = managedLocation
        } else {
            location = game.fileURL
        }
        NSWorkspace.shared.activateFileViewerSelecting([location])
    }

    func chooseGames() {
        let panel = NSOpenPanel()
        panel.title = "Import WonderSwan Games"
        panel.message = "Choose .ws, .wsc, .pc2, .pcv2, or ZIP files containing exactly one game. SwanSong keeps a private managed copy."
        panel.prompt = "Import Games"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let contentTypes = ["ws", "wsc", "pc2", "pcv2", "zip"].compactMap {
            UTType(filenameExtension: $0, conformingTo: .data)
        }
        panel.allowedContentTypes = contentTypes.isEmpty ? [.data] : contentTypes
        guard panel.runModal() == .OK else { return }
        importGames(at: panel.urls)
    }

    func chooseGameFolder(recursively: Bool = true) {
        let panel = NSOpenPanel()
        panel.title = "Import a Folder of WonderSwan Games"
        panel.message = recursively
            ? "SwanSong will include .ws, .wsc, .pc2, .pcv2, and one-game ZIP files in this folder and its visible subfolders."
            : "SwanSong will include .ws, .wsc, .pc2, .pcv2, and one-game ZIP files directly inside this folder."
        panel.prompt = "Import Folder"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let folderURL = panel.url else { return }
        importGames(in: folderURL, recursively: recursively)
    }

    func dismissPresentedError() {
        presentedError = nil
    }

    private func resumePlayerIntent(
        _ intent: PlayerLaunchIntent,
        diagnosticContext: String,
        deferred: Bool = true
    ) {
        guard deferred else {
            performPlayerIntent(intent, diagnosticContext: diagnosticContext)
            return
        }
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.performPlayerIntent(intent, diagnosticContext: diagnosticContext)
        }
    }

    private func performPlayerIntent(
        _ intent: PlayerLaunchIntent,
        diagnosticContext: String
    ) {
        guard !terminationIsInProgress else { return }
        switch intent {
        case let .game(id, title):
            guard games.contains(where: { $0.id == id }) else {
                presentedError = "\(title) is no longer in the library, so it could not be started."
                return
            }
            appDiagnostic("\(diagnosticContext) game title=\(title)")
            selectedGameID = id
            play(id)
        case let .translation(continuation, projectPath, title):
            guard translationProject?.rootURL.standardizedFileURL.path == projectPath else {
                presentedError = "The \(title) translation project changed before setup finished. Select it again to start the test."
                return
            }
            switch continuation {
            case let .play(role, recordingFromCleanBoot):
                appDiagnostic(
                    "\(diagnosticContext) translation role=\(role.rawValue) title=\(title)"
                )
                playTranslationROM(
                    role,
                    recordingFromCleanBoot: recordingFromCleanBoot
                )
            case let .replay(role, route):
                appDiagnostic(
                    "\(diagnosticContext) translation replay role=\(role.rawValue) title=\(title)"
                )
                beginTranslationRouteReplay(role: role, route: route)
            case let .verifyRoute(route):
                appDiagnostic("\(diagnosticContext) translation verification title=\(title)")
                beginTranslationRouteVerification(route)
            case .verifySuite:
                appDiagnostic("\(diagnosticContext) translation suite title=\(title)")
                verifyTranslationSuite()
            case let .locateVisualDivergence(route):
                appDiagnostic(
                    "\(diagnosticContext) translation first visual change title=\(title)"
                )
                beginLocatingFirstTranslationVisualChange(route)
            }
        }
    }

    func importGames(in folderURL: URL, recursively: Bool = true) {
        do {
            let urls = try gameImportPlanner.files(
                in: folderURL,
                recursively: recursively
            )
            guard !urls.isEmpty else {
                presentedError = nil
                presentedNotice = "No .ws, .wsc, .pc2, .pcv2, or one-game ZIP files were found in \(folderURL.lastPathComponent)."
                return
            }
            importGames(at: urls)
        } catch {
            presentedNotice = nil
            presentedError = "That folder could not be searched for WonderSwan games."
        }
    }

    func importGames(at urls: [URL], beginPlayingFirst: Bool = false) {
        performGameImport(
            urls,
            beginPlayingFirst: beginPlayingFirst,
            reportsBatchResult: true
        )
    }

    func chooseTranslationProject() {
        let panel = NSOpenPanel()
        panel.title = "Add Translation Projects"
        panel.message = "Choose one project, project.json, or a private toolkit folder to add all of its WonderSwan projects."
        panel.prompt = "Add Projects"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json, .folder]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        linkTranslationProject(at: url)
    }

    func linkTranslationProject(at url: URL) {
        do {
            let discovered = try TranslationProject.discover(at: url)
            var addedCount = 0
            for project in discovered where !translationProjects.contains(where: { $0.id == project.id }) {
                translationProjects.append(project)
                addedCount += 1
            }
            translationProjects.sort {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            persistTranslationWorkspace()
            let preferred = discovered.first(where: { candidate in
                candidate.rootURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path
            }) ?? discovered.first
            if (activeTranslationRole != nil || translationToolIsRunning), translationProject != nil {
                presentedNotice = addedCount == 0
                    ? "Those projects are already in Translation Lab."
                    : "Added \(addedCount) translation project\(addedCount == 1 ? "" : "s"). Finish the current test before switching."
                return
            }
            if let preferred {
                selectTranslationProject(preferred.id)
                presentedNotice = addedCount == 0
                    ? "That project is already in Translation Lab."
                    : addedCount == 1
                        ? "Added \(preferred.title) to Translation Lab."
                        : "Added \(addedCount) translation projects."
            }
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func selectTranslationProject(_ id: TranslationProject.ID) {
        guard let project = translationProjects.first(where: { $0.id == id }) else { return }
        guard translationProject?.id != project.id else {
            section = .translationLab
            persistTranslationWorkspace()
            return
        }
        guard !translationToolIsRunning else {
            presentedError = "Wait for the current toolkit check to finish before switching projects."
            return
        }
        guard activeTranslationRole == nil else {
            presentedError = "Stop the active translation test before switching projects."
            return
        }
        translationProject = project
        section = .translationLab
        resetTranslationProjectState()
        refreshTranslationHistory()
        persistTranslationWorkspace()
        refreshTranslationStatus()
    }

    func unlinkTranslationProject() {
        guard !isPlaying || activeTranslationRole == nil else {
            presentedError = "Stop the active translation test before unlinking its project."
            return
        }
        guard !translationToolIsRunning else {
            presentedError = "Wait for the current toolkit check to finish before removing its project."
            return
        }
        guard let current = translationProject else { return }
        let removedIndex = translationProjects.firstIndex(where: { $0.id == current.id }) ?? 0
        translationProjects.removeAll { $0.id == current.id }
        translationProject = translationProjects.isEmpty
            ? nil
            : translationProjects[min(removedIndex, translationProjects.count - 1)]
        resetTranslationProjectState()
        refreshTranslationHistory()
        persistTranslationWorkspace()
        UserDefaults.standard.removeObject(forKey: translationProjectDefaultsKey)
        if translationProject != nil { refreshTranslationStatus() }
    }

    func refreshTranslationStatus() {
        runTranslationPipeline([.status])
    }

    func checkTranslationProject() {
        guard !isPlaying else {
            presentedError = "Stop the current test before running project checks."
            return
        }
        runTranslationPipeline([.qa, .validate, .status])
    }

    func buildAndRunTranslation() {
        guard !isPlaying else {
            presentedError = "Stop the current test before building a new patched ROM."
            return
        }
        runGuardedTranslationPack(completion: .playPatched)
    }

    func verifyLatestTranslationRoute() {
        guard !isPlaying else {
            presentedError = "Stop the current test before starting an A/B route verification."
            return
        }
        guard !translationToolIsRunning, translationComparisonPhase == nil else { return }
        guard engineCanExecute else {
            presentedError = "The live ares engine is required for route verification."
            return
        }
        guard translationOriginalROMAvailable else {
            presentedError = "The original ROM is missing from this private translation project."
            return
        }
        guard let route = latestTranslationRoute else {
            presentedError = "Record or select an input route before starting A/B verification."
            return
        }
        beginTranslationRouteVerification(route)
    }

    func locateFirstTranslationVisualChange() {
        guard !isPlaying else {
            presentedError = "Stop the current test before locating its first visual change."
            return
        }
        guard !translationToolIsRunning,
              translationComparisonPhase == nil,
              !translationVisualDivergenceIsRunning else { return }
        guard engineCanExecute else {
            presentedError = "The live ares engine is required to locate visual changes."
            return
        }
        guard translationOriginalROMAvailable, translationPatchedROMAvailable else {
            presentedError = "Both the Original and Patched ROMs must be available in this private project."
            return
        }
        guard let route = latestTranslationRoute else {
            presentedError = "Record or select an input route before locating its first visual change."
            return
        }
        beginLocatingFirstTranslationVisualChange(route)
    }

    private func beginLocatingFirstTranslationVisualChange(_ route: TranslationRoute) {
        guard !isPlaying,
              !translationToolIsRunning,
              translationComparisonPhase == nil,
              !translationVisualDivergenceIsRunning else { return }
        guard preflightTranslationROM(.original) else { return }
        do {
            try validateTranslationRouteForCurrentProject(route)
            try validateTranslationReplayTarget(.patched, route: route)
        } catch {
            presentedError = "This route cannot be compared: \(error.localizedDescription)"
            return
        }

        translationVisualDivergenceTask?.cancel()
        translationVisualDivergenceTask = nil
        translationVisualDivergenceResult = nil
        translationVisualDivergenceIssue = nil
        translationVisualDivergenceRoute = route
        translationVisualDivergenceProgress = .init(
            framesProcessed: 0,
            totalFrames: route.totalFrames,
            firstDifferenceFrameIndex: nil
        )
        translationVisualDivergenceIsRunning = true
        isTranslationVisualDivergencePresented = true
        presentedNotice = nil
        runGuardedTranslationPack(completion: .locateVisualDivergence(route))
    }

    private func beginTranslationRouteVerification(_ route: TranslationRoute) {
        guard !isPlaying, !translationToolIsRunning, translationComparisonPhase == nil else {
            return
        }
        guard preflightTranslationROM(.original) else { return }
        do {
            try validateTranslationRouteForCurrentProject(route)
        } catch {
            presentedError = "This route cannot be verified: \(error.localizedDescription)"
            return
        }

        resetTranslationSuiteExecution()
        translationComparisonRoute = route
        translationComparisonPhase = .preparing
        presentedNotice = nil
        runGuardedTranslationPack(completion: .verifyRoute(route))
    }

    func verifyTranslationSuite() {
        guard !isPlaying else {
            presentedError = "Stop the current test before starting the route suite."
            return
        }
        guard !translationToolIsRunning, translationComparisonPhase == nil else { return }
        guard engineCanExecute else {
            presentedError = "The live ares engine is required for route-suite verification."
            return
        }
        guard translationOriginalROMAvailable else {
            presentedError = "The original ROM is missing from this private translation project."
            return
        }
        guard translationSuiteBlockingIssue == nil else {
            presentedError = translationSuiteBlockingIssue
            return
        }
        guard let first = translationRoutes.first else {
            presentedError = "Record at least one input route before starting a verification suite."
            return
        }
        guard preflightTranslationROM(.original) else { return }
        do {
            for summary in translationRoutes {
                try validateTranslationRouteForCurrentProject(summary.route)
            }
        } catch {
            presentedError = "The route suite cannot start: \(error.localizedDescription)"
            return
        }

        translationSuiteQueue = translationRoutes
        translationSuiteStartedAt = Date()
        translationSuiteCurrentCaseIndex = 0
        translationSuiteTotalCaseCount = translationRoutes.count
        translationSuiteCaseResults = []
        selectTranslationRoute(first.id)
        translationComparisonRoute = first.route
        translationComparisonPhase = .preparing
        presentedNotice = nil
        runGuardedTranslationPack(completion: .verifyRoute(first.route))
    }

    func startCleanBootTranslationTest() {
        guard !isPlaying, !translationToolIsRunning else {
            presentedError = "Stop the current operation before recording a new route test."
            return
        }
        playTranslationROM(.original, recordingFromCleanBoot: true)
    }

    func playTranslationROM(
        _ role: TranslationROMRole,
        recordingFromCleanBoot: Bool = false
    ) {
        guard !terminationIsInProgress else { return }
        guard playerSessionReplacementIsAvailable() else { return }
        guard let project = translationProject else { return }
        do {
            let url = try project.romURL(for: role)
            var game = try translationGame(at: url, project: project)
            game.title = project.title
            guard engineCanExecute else {
                presentedError = "The live ares engine is required to run a translation test."
                return
            }
            games.append(game)
            selectedGameID = game.id
            play(game.id, translationRole: role, project: project, romURL: url)
            if recordingFromCleanBoot || automatedTranslationRouteEndFrame != nil {
                try armTranslationRouteRecordingFromCleanBoot()
            }
        } catch {
            if isPlaying { stopPlaying() }
            presentedError = "The \(role.title.lowercased()) test ROM could not be opened: \(error.localizedDescription)"
        }
    }

    func revealTranslationProject() {
        guard let project = translationProject else { return }
        NSWorkspace.shared.activateFileViewerSelecting([project.rootURL])
    }

    func revealLastTranslationEvidence() {
        guard let lastTranslationEvidenceURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastTranslationEvidenceURL])
    }

    func revealTranslationEvidence(_ summary: TranslationEvidenceSummary) {
        NSWorkspace.shared.activateFileViewerSelecting([summary.artifact.directoryURL])
    }

    func selectTranslationPrivateArtifact(
        _ id: TranslationPrivateArtifactSummary.ID
    ) {
        guard translationPrivateArtifacts.contains(where: { $0.id == id }) else { return }
        selectedTranslationPrivateArtifactID = id
    }

    func revealTranslationPrivateArtifact(
        _ summary: TranslationPrivateArtifactSummary
    ) {
        NSWorkspace.shared.activateFileViewerSelecting([summary.directoryURL])
    }

    func exportTranslationPrivateArtifactSummary(
        _ summary: TranslationPrivateArtifactSummary
    ) {
        let panel = NSSavePanel()
        panel.title = "Export Source-Free Artifact Summary"
        panel.message = "Exports integrity, size, status, hashes, and counts only. Captured pixels and display-owner source details stay private in the project."
        panel.prompt = "Export Summary"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(summary.name)-source-free.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, var destination = panel.url else { return }
        if destination.pathExtension.lowercased() != "json" {
            destination.appendPathExtension("json")
        }
        do {
            let output = try translationPrivateArtifactStore.exportSourceFreeSummary(
                summary,
                to: destination
            )
            NSWorkspace.shared.activateFileViewerSelecting([output])
            presentedNotice = "Exported a source-free private-artifact summary. Captures and owner details stayed in the project."
        } catch {
            presentedError = "The private-artifact summary could not be exported: \(error.localizedDescription)"
        }
    }

    func deleteTranslationPrivateArtifact(
        _ summary: TranslationPrivateArtifactSummary
    ) {
        guard let project = translationProject else { return }
        do {
            try translationPrivateArtifactStore.remove(summary, project: project)
            if selectedTranslationPrivateArtifactID == summary.id {
                selectedTranslationPrivateArtifactID = nil
            }
            refreshTranslationHistory()
            presentedNotice = "Deleted the selected private Translation Lab artifact."
        } catch {
            presentedError = "The private artifact could not be deleted: \(error.localizedDescription)"
        }
    }

    func beginTranslationTextIntake() {
        guard
            let evidence = selectedTranslationEvidence,
            evidence.isIntact,
            let framePNG = evidence.framePNG,
            let bitmap = NSBitmapImageRep(data: framePNG),
            bitmap.pixelsWide > 0,
            bitmap.pixelsHigh > 0
        else {
            presentedError = "Select an intact captured frame before extracting source text."
            return
        }
        do {
            let capture = try TranslationCaptureImage(
                encodedData: framePNG,
                encoding: .png,
                pixelWidth: bitmap.pixelsWide,
                pixelHeight: bitmap.pixelsHigh
            )
            guard capture.sha256 == evidence.manifest?.frame.sha256 else {
                throw TranslationLabError.invalidProject(
                    "the selected frame no longer matches its evidence manifest"
                )
            }
            resetTranslationTextIntake()
            translationTextIntakeCapture = capture
            translationTextIntakeEvidenceID = evidence.id
            translationTextIntakeSelection = capture.bounds
            if let project = translationProject {
                translationTextIntakeHasSavedArtifact = try translationEvidenceStore
                    .privateArtifactExists(.textIntake, evidence: evidence, project: project)
                translationDraftHasSavedArtifact = try translationEvidenceStore
                    .privateArtifactExists(.translationDraft, evidence: evidence, project: project)
                if translationTextIntakeHasSavedArtifact {
                    do {
                        try loadSavedTranslationWorkspace(
                            evidence: evidence,
                            project: project,
                            capture: capture
                        )
                    } catch {
                        translationTextIntakeIssue = "The saved private workspace could not be resumed: \(error.localizedDescription) You can select a region and create a new intake."
                    }
                }
            }
            isTranslationTextIntakePresented = true
        } catch {
            presentedError = "Source-text intake could not open this capture: \(error.localizedDescription)"
        }
    }

    func dismissTranslationTextIntake() {
        resetTranslationTextIntake()
    }

    func updateTranslationTextIntakeSelection(_ selection: TranslationPixelRect) {
        guard
            !translationTextIntakeIsRecognizing,
            let capture = translationTextIntakeCapture,
            capture.bounds.contains(selection)
        else { return }
        translationTextIntakeSelection = selection
        translationTextIntakeSession = nil
        translationTextIntakeDrafts = [:]
        translationTextIntakeIssue = nil
        translationDraftSession = nil
        translationDraftTargetDrafts = [:]
        translationDraftIssue = nil
    }

    func useFullFrameForTranslationTextIntake() {
        guard let capture = translationTextIntakeCapture else { return }
        updateTranslationTextIntakeSelection(capture.bounds)
    }

    func useDialogueBandForTranslationTextIntake() {
        guard let capture = translationTextIntakeCapture else { return }
        let top = Int((Double(capture.pixelHeight) * 0.55).rounded(.down))
        updateTranslationTextIntakeSelection(
            TranslationPixelRect(
                x: 0,
                y: top,
                width: capture.pixelWidth,
                height: capture.pixelHeight - top
            )
        )
    }

    func restartTranslationTextIntakeRegionSelection() {
        guard !translationTextIntakeIsRecognizing else { return }
        translationTextIntakeGeneration = UUID()
        translationTextIntakeTask?.cancel()
        translationTextIntakeTask = nil
        translationTextIntakeSession = nil
        translationTextIntakeDrafts = [:]
        translationTextIntakeManualDraft = ""
        translationTextIntakeIssue = nil
        translationDraftSession = nil
        translationDraftTargetDrafts = [:]
        translationDraftIssue = nil
    }

    func recognizeTranslationTextIntake() {
        guard
            !translationTextIntakeIsRecognizing,
            let capture = translationTextIntakeCapture,
            let selection = translationTextIntakeSelection,
            capture.bounds.contains(selection)
        else { return }

        let recognizer = VisionTranslationTextRecognizer()
        do {
            var session = try TranslationTextIntakeSession(
                capture: capture,
                selection: selection
            )
            let request = try session.beginRecognition(using: recognizer.descriptor)
            let generation = UUID()
            translationTextIntakeGeneration = generation
            translationTextIntakeTask?.cancel()
            translationTextIntakeSession = session
            translationTextIntakeDrafts = [:]
            translationTextIntakeIssue = nil
            translationTextIntakeIsRecognizing = true

            translationTextIntakeTask = Task { @MainActor [weak self] in
                do {
                    let observations = try await recognizer.recognizeText(in: request)
                    try Task.checkCancellation()
                    guard
                        let self,
                        self.translationTextIntakeGeneration == generation
                    else { return }
                    var completed = session
                    try completed.finishRecognition(
                        observations,
                        from: recognizer.descriptor
                    )
                    self.translationTextIntakeSession = completed
                    self.translationTextIntakeDrafts = Dictionary(
                        uniqueKeysWithValues: completed.lines.map {
                            ($0.id, $0.reviewedText)
                        }
                    )
                    self.translationTextIntakeIssue = observations.isEmpty
                        ? "No text was found in this region. Adjust the selection or type a source line manually."
                        : nil
                    self.translationTextIntakeIsRecognizing = false
                    self.translationTextIntakeTask = nil
                } catch is CancellationError {
                    guard
                        let self,
                        self.translationTextIntakeGeneration == generation
                    else { return }
                    self.translationTextIntakeIsRecognizing = false
                    self.translationTextIntakeTask = nil
                } catch {
                    guard
                        let self,
                        self.translationTextIntakeGeneration == generation
                    else { return }
                    var failed = session
                    try? failed.cancelRecognition()
                    self.translationTextIntakeSession = failed
                    self.translationTextIntakeIssue = "On-device text recognition failed: \(error.localizedDescription)"
                    self.translationTextIntakeIsRecognizing = false
                    self.translationTextIntakeTask = nil
                }
            }
        } catch {
            translationTextIntakeIssue = "Text recognition could not start: \(error.localizedDescription)"
        }
    }

    func updateTranslationTextIntakeDraft(id: String, text: String) {
        guard translationTextIntakeSession?.lines.contains(where: { $0.id == id }) == true else {
            return
        }
        translationTextIntakeDrafts[id] = text
    }

    func addManualTranslationTextIntakeLine() {
        let source = translationTextIntakeManualDraft
        guard
            let capture = translationTextIntakeCapture,
            let selection = translationTextIntakeSelection,
            capture.bounds.contains(selection)
        else { return }
        do {
            var session: TranslationTextIntakeSession
            if let current = translationTextIntakeSession {
                session = current
                if session.state == .awaitingRecognition {
                    try session.beginManualTranscription()
                }
            } else {
                session = try TranslationTextIntakeSession(
                    capture: capture,
                    selection: selection
                )
                try session.beginManualTranscription()
            }
            let id = try session.addManualLine(text: source, bounds: selection)
            translationTextIntakeSession = session
            translationTextIntakeDrafts[id] = session.lines.first {
                $0.id == id
            }?.reviewedText ?? source
            translationTextIntakeManualDraft = ""
            translationTextIntakeIssue = nil
        } catch {
            translationTextIntakeIssue = "That manual source line could not be added: \(error.localizedDescription)"
        }
    }

    func confirmTranslationTextIntakeLine(_ id: String) {
        do {
            var session = try editableTranslationTextIntakeSession()
            guard let line = session.lines.first(where: { $0.id == id }) else {
                throw TranslationTextIntakeError.lineNotFound(id)
            }
            let draft = translationTextIntakeDrafts[id] ?? line.reviewedText
            if draft != line.reviewedText {
                try session.correctLine(id: id, text: draft)
            }
            try session.confirmLine(id: id)
            translationTextIntakeSession = session
            translationTextIntakeDrafts[id] = session.lines.first {
                $0.id == id
            }?.reviewedText ?? draft
            translationTextIntakeIssue = nil
        } catch {
            translationTextIntakeIssue = "That source line could not be confirmed: \(error.localizedDescription)"
        }
    }

    func reopenTranslationTextIntakeLine(_ id: String) {
        do {
            var session = try editableTranslationTextIntakeSession()
            try session.reopenLine(id: id)
            translationTextIntakeSession = session
            translationTextIntakeIssue = nil
        } catch {
            translationTextIntakeIssue = "That source line could not be reopened: \(error.localizedDescription)"
        }
    }

    func confirmAllTranslationTextIntakeLines() {
        do {
            var session = try reviewedTranslationTextIntakeSessionApplyingDrafts()
            try session.confirmAllLines()
            translationTextIntakeSession = session
            translationTextIntakeIssue = nil
        } catch {
            translationTextIntakeIssue = "The source text is not ready: \(error.localizedDescription)"
        }
    }

    func saveTranslationTextIntake() {
        guard
            let project = translationProject,
            let evidence = selectedTranslationEvidence,
            evidence.id == translationTextIntakeEvidenceID,
            evidence.isIntact
        else {
            translationTextIntakeIssue = "The selected evidence changed. Close this intake and start again."
            return
        }
        do {
            var session = try reviewedTranslationTextIntakeSessionApplyingDrafts()
            try session.confirmAllLines()
            let intakeData = try session.encodedArtifact()

            let draft: TranslationDraftSession
            if let savedDraftData = try translationEvidenceStore.loadPrivateArtifact(
                .translationDraft,
                evidence: evidence,
                project: project
            ) {
                let savedDraft = try JSONDecoder().decode(
                    TranslationDraftArtifact.self,
                    from: savedDraftData
                )
                draft = try TranslationDraftSession(
                    draft: savedDraft,
                    encodedSourceIntake: intakeData,
                    expectedSourceLanguage: project.sourceLanguage,
                    expectedTargetLanguage: project.targetLanguage
                )
            } else {
                draft = try TranslationDraftSession(
                    encodedSourceIntake: intakeData,
                    sourceLanguage: project.sourceLanguage,
                    targetLanguage: project.targetLanguage
                )
            }

            _ = try translationEvidenceStore.savePrivateArtifact(
                intakeData,
                kind: .textIntake,
                evidence: evidence,
                project: project
            )
            try session.markExported()
            translationTextIntakeSession = session
            translationTextIntakeHasSavedArtifact = true
            translationDraftSession = draft
            translationDraftTargetDrafts = Dictionary(
                uniqueKeysWithValues: draft.lines.map { ($0.id, $0.targetText) }
            )
            translationDraftIssue = nil
            translationTextIntakeIssue = nil
            presentedNotice = "Saved \(session.lines.count) confirmed source \(session.lines.count == 1 ? "line" : "lines") privately. Target drafting is ready."
        } catch {
            translationTextIntakeIssue = "The private source-text intake could not be saved: \(error.localizedDescription)"
        }
    }

    func revealTranslationTextIntake() {
        guard
            let project = translationProject,
            let evidence = selectedTranslationEvidence,
            let url = try? translationEvidenceStore.privateArtifactURL(
                .textIntake,
                evidence: evidence,
                project: project
            ),
            (try? translationEvidenceStore.privateArtifactExists(
                .textIntake,
                evidence: evidence,
                project: project
            )) == true
        else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func updateTranslationDraftTarget(id: String, text: String) {
        guard var session = translationDraftSession,
              session.lines.contains(where: { $0.id == id }) else { return }
        translationDraftTargetDrafts[id] = text
        do {
            try session.updateManualTarget(lineID: id, text: text)
            translationDraftSession = session
            translationDraftIssue = nil
        } catch {
            translationDraftIssue = "That target draft is not valid: \(error.localizedDescription)"
        }
    }

    func reviewTranslationDraftLine(_ id: String) {
        do {
            guard var session = translationDraftSession,
                  let line = session.lines.first(where: { $0.id == id }) else {
                throw TranslationDraftError.lineNotFound(id)
            }
            try session.updateManualTarget(
                lineID: id,
                text: translationDraftTargetDrafts[id] ?? line.targetText
            )
            try session.markReviewed(lineID: id)
            translationDraftSession = session
            translationDraftTargetDrafts[id] = session.lines.first {
                $0.id == id
            }?.targetText ?? ""
            translationDraftIssue = nil
        } catch {
            translationDraftIssue = "That target draft could not be reviewed: \(error.localizedDescription)"
        }
    }

    func reopenTranslationDraftLine(_ id: String) {
        do {
            guard var session = translationDraftSession,
                  let line = session.lines.first(where: { $0.id == id }) else {
                throw TranslationDraftError.lineNotFound(id)
            }
            try session.updateManualTarget(
                lineID: id,
                text: translationDraftTargetDrafts[id] ?? line.targetText
            )
            try session.reopen(lineID: id)
            translationDraftSession = session
            translationDraftIssue = nil
        } catch {
            translationDraftIssue = "That target draft could not be reopened: \(error.localizedDescription)"
        }
    }

    func clearTranslationDraftLine(_ id: String) {
        guard var session = translationDraftSession else { return }
        do {
            try session.updateManualTarget(lineID: id, text: "")
            translationDraftSession = session
            translationDraftTargetDrafts[id] = ""
            translationDraftIssue = nil
        } catch {
            translationDraftIssue = "That target draft could not be cleared: \(error.localizedDescription)"
        }
    }

    func saveTranslationDraft() {
        guard let project = translationProject,
              let evidence = selectedTranslationEvidence,
              evidence.id == translationTextIntakeEvidenceID,
              evidence.isIntact else {
            translationDraftIssue = "The selected evidence changed. Close this workspace and start again."
            return
        }
        do {
            let editedSession = try translationDraftSessionApplyingDrafts()
            guard let intakeData = try translationEvidenceStore.loadPrivateArtifact(
                .textIntake,
                evidence: evidence,
                project: project
            ) else {
                throw TranslationDraftError.invalidSourceIntake
            }
            // Reopen the exact in-memory artifact against the source bytes and
            // current project languages at the write boundary. This prevents
            // an external edit while the sheet is open from producing a stale
            // or mislabeled replacement draft.
            let session = try TranslationDraftSession(
                draft: editedSession.makeArtifact(),
                encodedSourceIntake: intakeData,
                expectedSourceLanguage: project.sourceLanguage,
                expectedTargetLanguage: project.targetLanguage
            )
            let data = try session.encodedArtifact()
            _ = try translationEvidenceStore.savePrivateArtifact(
                data,
                kind: .translationDraft,
                evidence: evidence,
                project: project
            )
            translationDraftSession = session
            translationDraftTargetDrafts = Dictionary(
                uniqueKeysWithValues: session.lines.map { ($0.id, $0.targetText) }
            )
            translationDraftHasSavedArtifact = true
            translationDraftIssue = nil
            let progress = session.completeness
            presentedNotice = "Saved \(progress.translatedLines) of \(progress.totalLines) target \(progress.totalLines == 1 ? "draft" : "drafts") privately; \(progress.reviewedLines) reviewed."
        } catch {
            translationDraftIssue = "The private translation draft could not be saved: \(error.localizedDescription)"
        }
    }

    func revealTranslationDraft() {
        guard let project = translationProject,
              let evidence = selectedTranslationEvidence,
              let url = try? translationEvidenceStore.privateArtifactURL(
                  .translationDraft,
                  evidence: evidence,
                  project: project
              ),
              (try? translationEvidenceStore.privateArtifactExists(
                  .translationDraft,
                  evidence: evidence,
                  project: project
              )) == true else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func discardSavedTranslationDraft() {
        guard let project = translationProject,
              let evidence = selectedTranslationEvidence,
              evidence.id == translationTextIntakeEvidenceID else {
            translationTextIntakeIssue = "The selected evidence changed. Close this workspace and start again."
            return
        }
        do {
            _ = try translationEvidenceStore.removePrivateArtifact(
                .translationDraft,
                evidence: evidence,
                project: project
            )
            translationDraftSession = nil
            translationDraftTargetDrafts = [:]
            translationDraftIssue = nil
            translationDraftHasSavedArtifact = false
            translationTextIntakeIssue = nil
            if let capture = translationTextIntakeCapture,
               translationTextIntakeHasSavedArtifact {
                do {
                    try loadSavedTranslationWorkspace(
                        evidence: evidence,
                        project: project,
                        capture: capture
                    )
                    presentedNotice = "Discarded the saved target draft and opened a new blank draft from the unchanged source intake."
                } catch {
                    translationTextIntakeIssue = "The target draft was discarded, but the saved source intake still could not be resumed: \(error.localizedDescription) Create a new source intake to continue."
                }
            } else {
                presentedNotice = "Discarded the saved target draft. The source intake and evidence were not changed."
            }
        } catch {
            translationTextIntakeIssue = "The saved target draft could not be discarded: \(error.localizedDescription)"
        }
    }

    private func editableTranslationTextIntakeSession() throws -> TranslationTextIntakeSession {
        guard let session = translationTextIntakeSession else {
            throw TranslationLabError.invalidProject(
                "recognize or manually enter at least one source line first"
            )
        }
        guard session.state == .reviewing || session.state == .readyToExport else {
            throw TranslationLabError.invalidProject(
                "the current source-text intake is not editable"
            )
        }
        return session
    }

    private func reviewedTranslationTextIntakeSessionApplyingDrafts() throws
        -> TranslationTextIntakeSession {
        var session = try editableTranslationTextIntakeSession()
        for line in session.lines {
            let draft = translationTextIntakeDrafts[line.id] ?? line.reviewedText
            if draft != line.reviewedText {
                try session.correctLine(id: line.id, text: draft)
            }
        }
        return session
    }

    private func translationDraftSessionApplyingDrafts() throws -> TranslationDraftSession {
        guard var session = translationDraftSession else {
            throw TranslationLabError.invalidProject(
                "save confirmed source text before drafting its translation"
            )
        }
        for line in session.lines {
            try session.updateManualTarget(
                lineID: line.id,
                text: translationDraftTargetDrafts[line.id] ?? line.targetText
            )
        }
        return session
    }

    private func loadSavedTranslationWorkspace(
        evidence: TranslationEvidenceSummary,
        project: TranslationProject,
        capture: TranslationCaptureImage
    ) throws {
        guard let intakeData = try translationEvidenceStore.loadPrivateArtifact(
            .textIntake,
            evidence: evidence,
            project: project
        ) else { return }
        let intake = try JSONDecoder().decode(TranslationTextIntakeArtifact.self, from: intakeData)
        guard intake.schema == TranslationTextIntakeArtifact.currentSchema,
              intake.capture.sha256 == capture.sha256,
              intake.capture.pixelWidth == capture.pixelWidth,
              intake.capture.pixelHeight == capture.pixelHeight,
              capture.bounds.contains(intake.capture.selection) else {
            throw TranslationDraftError.sourceBindingMismatch
        }

        let draft: TranslationDraftSession
        if let draftData = try translationEvidenceStore.loadPrivateArtifact(
            .translationDraft,
            evidence: evidence,
            project: project
        ) {
            let artifact = try JSONDecoder().decode(TranslationDraftArtifact.self, from: draftData)
            draft = try TranslationDraftSession(
                draft: artifact,
                encodedSourceIntake: intakeData,
                expectedSourceLanguage: project.sourceLanguage,
                expectedTargetLanguage: project.targetLanguage
            )
            translationDraftHasSavedArtifact = true
        } else {
            draft = try TranslationDraftSession(
                encodedSourceIntake: intakeData,
                sourceLanguage: project.sourceLanguage,
                targetLanguage: project.targetLanguage
            )
            translationDraftHasSavedArtifact = false
        }
        translationTextIntakeSelection = intake.capture.selection
        translationDraftSession = draft
        translationDraftTargetDrafts = Dictionary(
            uniqueKeysWithValues: draft.lines.map { ($0.id, $0.targetText) }
        )
        translationDraftIssue = nil
    }

    private func resetTranslationTextIntake() {
        translationTextIntakeGeneration = UUID()
        translationTextIntakeTask?.cancel()
        translationTextIntakeTask = nil
        translationTextIntakeCapture = nil
        translationTextIntakeEvidenceID = nil
        translationTextIntakeIsRecognizing = false
        translationTextIntakeIssue = nil
        translationTextIntakeSelection = nil
        translationTextIntakeSession = nil
        translationTextIntakeDrafts = [:]
        translationTextIntakeManualDraft = ""
        translationTextIntakeHasSavedArtifact = false
        translationDraftSession = nil
        translationDraftTargetDrafts = [:]
        translationDraftIssue = nil
        translationDraftHasSavedArtifact = false
        isTranslationTextIntakePresented = false
    }

    func selectTranslationEvidence(_ id: TranslationEvidenceSummary.ID) {
        guard let evidence = translationEvidence.first(where: { $0.id == id }) else { return }
        if translationTextIntakeEvidenceID != nil,
           translationTextIntakeEvidenceID != evidence.id {
            resetTranslationTextIntake()
        }
        translationRAMComparison = nil
        translationRAMInspectionIssue = nil
        translationRAMTextReport = nil
        translationRAMTextInspectionIssue = nil
        translationRAMPointerReport = nil
        translationRAMPointerInspectionIssue = nil
        translationRAMInspectionIsLoading = false
        isTranslationRAMInspectorPresented = false
        selectedTranslationEvidenceID = evidence.id
        translationEvidenceReviewStatus = evidence.review?.status ?? .unreviewed
        translationEvidenceReviewNote = evidence.review?.note ?? ""
        refreshTranslationEvidenceFrameComparison()
    }

    func inspectSelectedTranslationRAM() {
        guard
            let project = translationProject,
            let selected = selectedTranslationEvidence,
            let pair = pairedTranslationEvidence,
            canInspectSelectedTranslationRAM
        else {
            translationRAMComparison = nil
            translationRAMInspectionIssue = "Select an intact exact-route Original/Patched evidence pair first."
            translationRAMTextReport = nil
            translationRAMTextInspectionIssue = nil
            translationRAMPointerReport = nil
            translationRAMPointerInspectionIssue = nil
            isTranslationRAMInspectorPresented = true
            return
        }

        let projectID = project.id
        let selectedID = selected.id
        let pairID = pair.id
        let store = translationEvidenceStore
        translationRAMComparison = nil
        translationRAMInspectionIssue = nil
        translationRAMTextReport = nil
        translationRAMTextInspectionIssue = nil
        translationRAMPointerReport = nil
        translationRAMPointerInspectionIssue = nil
        translationRAMInspectionIsLoading = true
        isTranslationRAMInspectorPresented = true

        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    let comparison = try store.compareInternalRAM(
                        selected,
                        pair,
                        project: project
                    )
                    let textReport: TranslationRAMTextReport?
                    let textIssue: String?
                    do {
                        textReport = try TranslationRAMTextScanner.report(for: comparison)
                        textIssue = nil
                    } catch {
                        textReport = nil
                        textIssue = "Text-buffer analysis is unavailable: \(error.localizedDescription)"
                    }

                    let pointerReport: TranslationRAMPointerReport?
                    let pointerIssue: String?
                    if let textReport {
                        do {
                            pointerReport = try TranslationRAMPointerScanner.report(
                                for: comparison,
                                textReport: textReport
                            )
                            pointerIssue = nil
                        } catch {
                            pointerReport = nil
                            pointerIssue = "Pointer-lead analysis is unavailable: \(error.localizedDescription)"
                        }
                    } else {
                        pointerReport = nil
                        pointerIssue = "Pointer leads require a current text-buffer analysis."
                    }
                    return TranslationRAMInspectionOutcome.success(
                        comparison: comparison,
                        textReport: textReport,
                        textIssue: textIssue,
                        pointerReport: pointerReport,
                        pointerIssue: pointerIssue
                    )
                } catch {
                    return TranslationRAMInspectionOutcome.failure(error.localizedDescription)
                }
            }.value

            guard
                translationProject?.id == projectID,
                selectedTranslationEvidenceID == selectedID,
                pairedTranslationEvidence?.id == pairID
            else {
                translationRAMInspectionIsLoading = false
                isTranslationRAMInspectorPresented = false
                return
            }

            translationRAMInspectionIsLoading = false
            switch outcome {
            case let .success(comparison, textReport, textIssue, pointerReport, pointerIssue):
                translationRAMComparison = comparison
                translationRAMTextReport = textReport
                translationRAMTextInspectionIssue = textIssue
                translationRAMPointerReport = pointerReport
                translationRAMPointerInspectionIssue = pointerIssue
            case let .failure(issue):
                translationRAMInspectionIssue = issue
            }
        }
    }

    func saveTranslationEvidenceReview() {
        guard let project = translationProject, let evidence = selectedTranslationEvidence else { return }
        do {
            _ = try translationEvidenceStore.saveReview(
                status: translationEvidenceReviewStatus,
                note: translationEvidenceReviewNote,
                evidence: evidence,
                project: project
            )
            refreshTranslationHistory()
            presentedNotice = "Saved the evidence review inside this private translation project."
        } catch {
            presentedError = "The evidence review could not be saved: \(error.localizedDescription)"
        }
    }

    func setSelectedTranslationEvidenceBaseline() {
        guard
            selectedTranslationEvidenceCanBecomeBaseline,
            let project = translationProject,
            let evidence = selectedTranslationEvidence,
            let route = selectedTranslationEvidenceRouteSummary
        else {
            presentedError = "Approve and save an intact patched capture before using it as a regression baseline."
            return
        }
        do {
            _ = try translationEvidenceStore.saveBaseline(
                evidence: evidence,
                route: route,
                project: project
            )
            refreshTranslationHistory()
            presentedNotice = "Saved this approved patched frame as the route’s regression baseline."
        } catch {
            presentedError = "The regression baseline could not be saved: \(error.localizedDescription)"
        }
    }

    func removeSelectedTranslationEvidenceBaseline() {
        guard
            let project = translationProject,
            let route = selectedTranslationEvidenceRouteSummary
        else { return }
        do {
            try translationEvidenceStore.removeBaseline(
                route: route,
                project: project
            )
            refreshTranslationHistory()
            presentedNotice = "Removed this route’s regression baseline without changing its evidence."
        } catch {
            presentedError = "The regression baseline could not be removed: \(error.localizedDescription)"
        }
    }

    private func approveLatestPatchedEvidenceAsBaseline() {
        guard
            let project = translationProject,
            let evidence = translationEvidence.first(where: {
                $0.isIntact
                    && $0.manifest?.romRole == .patched
                    && $0.manifest?.route != nil
            }),
            let routeDigest = evidence.manifest?.route,
            let route = translationRoutes.first(where: { $0.routeDigest == routeDigest })
        else {
            presentedError = "No intact routed patched capture is available for an automated baseline."
            return
        }
        do {
            _ = try translationEvidenceStore.saveReview(
                status: .approved,
                note: evidence.review?.note ?? "",
                evidence: evidence,
                project: project
            )
            refreshTranslationHistory()
            guard let refreshed = translationEvidence.first(where: { $0.id == evidence.id }) else {
                throw TranslationLabError.invalidProject(
                    "the approved baseline evidence disappeared during refresh"
                )
            }
            _ = try translationEvidenceStore.saveBaseline(
                evidence: refreshed,
                route: route,
                project: project
            )
            selectedTranslationEvidenceID = refreshed.id
            refreshTranslationHistory()
            presentedNotice = "Approved the latest patched evidence and saved its regression baseline."
        } catch {
            presentedError = "The automated regression baseline could not be saved: \(error.localizedDescription)"
        }
    }

    func exportSelectedTranslationDiagnostic() {
        guard let project = translationProject, let evidence = selectedTranslationEvidence else { return }
        guard evidence.isIntact else {
            presentedError = "Repair or recapture this evidence before exporting a diagnostic."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Source-Free Diagnostic"
        panel.message = "Exports only the rendered frame, input route, hashes, and review. ROM, RAM, state, and save bytes are excluded."
        panel.prompt = "Export Diagnostic"
        panel.canCreateDirectories = true
        let role = evidence.manifest?.romRole.rawValue ?? "capture"
        let frame = evidence.manifest?.frameNumber ?? 0
        panel.nameFieldStringValue = "\(project.slug)-\(role)-frame-\(frame).swsdiag"
        guard panel.runModal() == .OK, var destination = panel.url else { return }
        if destination.pathExtension.lowercased() != "swsdiag" {
            destination.appendPathExtension("swsdiag")
        }
        do {
            let diagnostic = try translationEvidenceStore.exportDiagnostic(
                evidence: evidence,
                project: project,
                to: destination
            )
            lastTranslationDiagnosticURL = diagnostic.packageURL
            NSWorkspace.shared.activateFileViewerSelecting([diagnostic.packageURL])
            presentedNotice = "Exported a source-free diagnostic with no ROM, RAM, state, or save bytes."
        } catch {
            presentedError = "The diagnostic could not be exported: \(error.localizedDescription)"
        }
    }

    func selectTranslationRoute(_ id: TranslationRouteSummary.ID) {
        guard let summary = translationRoutes.first(where: { $0.id == id }) else { return }
        latestTranslationRoute = summary.route
        latestTranslationRouteURL = summary.fileURL
        translationTestCaseName = summary.testCase?.name ?? ""
        translationTestCaseNote = summary.testCase?.note ?? ""
    }

    @discardableResult
    func saveSelectedTranslationTestCase() -> Bool {
        guard
            let project = translationProject,
            let summary = selectedTranslationRouteSummary
        else { return false }
        do {
            _ = try translationEvidenceStore.saveTestCase(
                name: translationTestCaseName,
                note: translationTestCaseNote,
                route: summary,
                project: project
            )
            refreshTranslationHistory()
            presentedNotice = "Saved the test-case name and notes without changing the immutable input route."
            return true
        } catch {
            presentedError = "The route test case could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    func importGame(at url: URL, beginPlay: Bool = true) {
        performGameImport(
            [url],
            beginPlayingFirst: beginPlay,
            reportsBatchResult: false
        )
    }

    private func performGameImport(
        _ urls: [URL],
        beginPlayingFirst: Bool,
        reportsBatchResult: Bool
    ) {
        guard !urls.isEmpty else { return }
        guard !gameImportIsBusy, repairingGameID == nil else {
            presentedNotice = "Finish the current library operation before importing games."
            return
        }
        let previousGames = games
        let previousSelection = selectedGameID
        let previousSection = section
        let batchImporter = batchImporter
        gameImportIsBusy = true
        presentedError = nil
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                batchImporter.importFiles(urls, into: previousGames)
            }.value
            guard let self else { return }
            self.gameImportIsBusy = false

            guard self.games == previousGames else {
                self.rollbackManagedImports(
                    result.createdManagedReferences,
                    retaining: self.games
                )
                self.presentedNotice = nil
                self.presentedError = "The library changed while those games were being inspected. No import changes were kept; try again."
                return
            }

            if result.successCount > 0 {
                self.games = result.games
                self.invalidateManagedGameHealthScan()
                let preservedSelection = previousSelection.flatMap { selection in
                    self.games.contains(where: { $0.id == selection }) ? selection : nil
                }
                self.selectedGameID = reportsBatchResult
                    ? preservedSelection
                    : result.importedGameIDs.first
                self.section = .library
                do {
                    try self.persist()
                    for gameID in result.importedGameIDs {
                        if self.games.first(where: { $0.id == gameID })?.managedROM != nil {
                            self.managedGameHealth[gameID] = .healthy
                            self.checkingManagedGameIDs.remove(gameID)
                        }
                    }
                    try? self.managedGameStore.prune(
                        retaining: self.games.compactMap(\.managedROM)
                    )
                } catch {
                    self.games = previousGames
                    self.selectedGameID = previousSelection
                    self.section = previousSection
                    self.rollbackManagedImports(
                        result.createdManagedReferences,
                        retaining: previousGames
                    )
                    self.presentedNotice = nil
                    let failureSuffix = result.failures.isEmpty
                        ? ""
                        : " \(result.failures.count) file\(result.failures.count == 1 ? "" : "s") also failed inspection."
                    self.presentedError = "The games were inspected, but the library could not be saved. No library changes were kept.\(failureSuffix)"
                    return
                }
            }

            if reportsBatchResult {
                self.presentBatchImportResult(result)
            } else if let failure = result.failures.first {
                self.presentedNotice = nil
                self.presentedError = "That file could not be opened as a supported game: \(failure.reason)"
            } else if result.successCount > 0 {
                self.presentedError = nil
            }

            if beginPlayingFirst,
               let gameID = result.importedGameIDs.first,
               result.successCount > 0 {
                self.play(gameID)
            }
        }
    }

    private func rollbackManagedImports(
        _ references: [ManagedGameReference],
        retaining records: [GameRecord]
    ) {
        let retained = Set(records.compactMap(\.managedROM))
        for reference in references where !retained.contains(reference) {
            try? managedGameStore.remove(reference)
        }
    }

    func repairManagedGame(
        _ id: GameRecord.ID,
        resumeAfterRepair: Bool = false
    ) {
        guard repairingGameID == nil,
              !gameImportIsBusy else {
            presentedNotice = "Finish the current library operation before repairing a game."
            return
        }
        guard let game = games.first(where: { $0.id == id }),
              game.managedROM != nil else {
            presentedError = "This legacy library entry is not a managed copy. Add the original game again to adopt it safely."
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Repair \(game.title)"
        panel.message = "Choose the exact same .ws, .wsc, .pc2, .pcv2, or one-game ZIP originally added. SwanSong verifies its SHA-256 identity before replacing the private copy."
        panel.prompt = "Verify and Repair"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let contentTypes = ["ws", "wsc", "pc2", "pcv2", "zip"].compactMap {
            UTType(filenameExtension: $0, conformingTo: .data)
        }
        panel.allowedContentTypes = contentTypes.isEmpty ? [.data] : contentTypes
        guard panel.runModal() == .OK, let sourceURL = panel.url else {
            if pendingRepairPlayGameID == id { pendingRepairPlayGameID = nil }
            return
        }
        if resumeAfterRepair { pendingRepairPlayGameID = id }
        repairManagedGame(id, from: sourceURL)
    }

    func repairManagedGame(_ id: GameRecord.ID, from sourceURL: URL) {
        guard repairingGameID == nil,
              !gameImportIsBusy else { return }
        guard let game = games.first(where: { $0.id == id }),
              let reference = game.managedROM else {
            presentedError = "That library entry cannot be repaired without its original managed-game identity."
            return
        }
        repairingGameID = id
        invalidateManagedGameHealthScan()
        presentedError = nil
        let managedGameStore = managedGameStore
        Task { [weak self] in
            let repairResult: (Result<URL, Error>, ManagedGameHealth) = await Task.detached(
                priority: .userInitiated
            ) {
                do {
                    let image = try LibraryGameImageImporter.image(from: sourceURL)
                    let location = try managedGameStore.repair(image, matching: reference)
                    return (.success(location), .healthy)
                } catch {
                    return (.failure(error), managedGameStore.health(of: reference))
                }
            }.value
            guard let self else { return }
            self.invalidateManagedGameHealthScan()
            self.repairingGameID = nil
            let matchingIDs = self.games.compactMap { candidate in
                candidate.managedROM == reference ? candidate.id : nil
            }
            for matchingID in matchingIDs {
                self.managedGameHealth[matchingID] = repairResult.1
                self.checkingManagedGameIDs.remove(matchingID)
            }
            switch repairResult.0 {
            case .success:
                guard self.games.contains(where: {
                    $0.id == id && $0.managedROM == reference
                }) else {
                    self.pendingRepairPlayGameID = nil
                    self.presentedError = "The library changed before the repair finished. The verified private copy is safe, but this entry is no longer available."
                    return
                }
                self.presentedNotice = "Repaired \(game.title) without changing its saves, states, favorites, or artwork."
                if self.pendingRepairPlayGameID == id {
                    self.pendingRepairPlayGameID = nil
                    self.play(id)
                }
            case let .failure(error):
                if repairResult.1 == .healthy {
                    // A directory fsync can fail after the atomic rename has
                    // committed. Trust the subsequent full content audit and
                    // avoid telling the user that intact bytes were rolled back.
                    self.presentedNotice = "Repaired \(game.title). The verified private copy is healthy, although macOS could not confirm the final storage sync."
                    if self.pendingRepairPlayGameID == id {
                        self.pendingRepairPlayGameID = nil
                        self.play(id)
                    }
                } else {
                    self.pendingRepairPlayGameID = nil
                    self.presentedNotice = nil
                    self.presentedError = "\(game.title) was not repaired. \(error.localizedDescription)"
                }
            }
        }
    }

    private func presentBatchImportResult(_ result: GameImportBatchResult) {
        let summary = gameImportSummary(result)
        guard !result.failures.isEmpty else {
            presentedError = nil
            presentedNotice = summary
            return
        }

        let visibleFailures = result.failures.prefix(5).map {
            "\($0.fileName): \($0.reason)"
        }
        let hiddenCount = result.failures.count - visibleFailures.count
        let hiddenSummary = hiddenCount > 0
            ? "\n…and \(hiddenCount) more file\(hiddenCount == 1 ? "" : "s")."
            : ""
        presentedNotice = nil
        presentedError = "\(summary) \(result.failures.count) file\(result.failures.count == 1 ? "" : "s") could not be imported.\n\n\(visibleFailures.joined(separator: "\n"))\(hiddenSummary)"
    }

    private func gameImportSummary(_ result: GameImportBatchResult) -> String {
        var parts: [String] = []
        if result.addedCount > 0 {
            parts.append("Added \(result.addedCount) game\(result.addedCount == 1 ? "" : "s").")
        }
        if result.updatedCount > 0 {
            parts.append("Updated \(result.updatedCount) existing game\(result.updatedCount == 1 ? "" : "s").")
        }
        if result.duplicateCount > 0 {
            parts.append("Skipped \(result.duplicateCount) duplicate selection\(result.duplicateCount == 1 ? "" : "s").")
        }
        if result.successCount == 0 {
            parts.insert("No games were imported.", at: 0)
        }
        return parts.joined(separator: " ")
    }

    func toggleFavorite(_ id: GameRecord.ID) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        games[index].isFavorite.toggle()
        do {
            try persist()
        } catch {
            games[index].isFavorite.toggle()
            presentedError = "That favorite could not be saved. Nothing changed."
        }
    }

    func updateGameCompatibilityVerdict(
        _ verdict: GameCompatibilityVerdict?,
        for id: GameRecord.ID,
        updatedAt: Date = Date()
    ) {
        updateGameCompatibilityEvidence(
            for: id,
            failureMessage: "That compatibility report could not be saved. Nothing changed."
        ) { current in
            let updated = (current ?? GameCompatibilityEvidence())
                .updatingVerdict(verdict, at: updatedAt)
            return updated.isEmpty ? nil : updated
        }
    }

    func updateGameCompatibilityNote(
        _ note: String,
        for id: GameRecord.ID,
        updatedAt: Date = Date()
    ) {
        updateGameCompatibilityEvidence(
            for: id,
            failureMessage: "That compatibility note could not be saved. Nothing changed."
        ) { current in
            let updated = (current ?? GameCompatibilityEvidence())
                .updatingNote(note, at: updatedAt)
            return updated.isEmpty ? nil : updated
        }
    }

    func resetGameCompatibilityEvidence(for id: GameRecord.ID) {
        updateGameCompatibilityEvidence(
            for: id,
            failureMessage: "That compatibility evidence could not be reset. Nothing changed."
        ) { _ in nil }
    }

    func remove(_ id: GameRecord.ID) {
        guard repairingGameID != id else {
            presentedNotice = "Finish repairing this game before removing it from the library."
            return
        }
        if playingGameID == id { stopPlaying() }
        let previousGames = games
        let previousSelection = selectedGameID
        games.removeAll { $0.id == id }
        if selectedGameID == id { selectedGameID = nil }
        do {
            try persist()
        } catch {
            games = previousGames
            selectedGameID = previousSelection
            presentedError = "That game could not be removed because the library could not be saved. Nothing changed."
            return
        }
        invalidateManagedGameHealthScan()
        gameArtwork.removeValue(forKey: id)
        managedGameHealth.removeValue(forKey: id)
        checkingManagedGameIDs.remove(id)
        try? artworkStore.remove(gameID: id)
        try? managedGameStore.prune(retaining: games.compactMap(\.managedROM))
    }

    func play(
        _ id: GameRecord.ID,
        translationRole: TranslationROMRole? = nil,
        project: TranslationProject? = nil,
        romURL: URL? = nil
    ) {
        guard !terminationIsInProgress else { return }
        guard playerSessionReplacementIsAvailable() else { return }
        guard let game = games.first(where: { $0.id == id }) else { return }
        playerReturnSection = translationRole == nil ? section : .translationLab
        if managedGameHealth[id] == .invalidReference {
            presentedError = "This library entry has lost its verified game identity and cannot be repaired safely. Re-add the original game as a new entry, confirm it works, then remove this one."
            return
        }
        if managedGameHealth[id] == .missing || managedGameHealth[id] == .changed {
            repairManagedGame(id, resumeAfterRepair: true)
            return
        }
        if checkingManagedGameIDs.contains(id) {
            presentedNotice = "SwanSong is verifying \(game.title)’s private copy. Play will be ready when the check finishes."
            return
        }
        if repairingGameID == id {
            presentedNotice = "SwanSong is repairing \(game.title). It will be ready shortly."
            return
        }
        guard engineCanExecute else {
            presentedError = "The playback engine is unavailable. Rebuild SwanSong with its ares engine, then try again."
            return
        }
        let startupKind = firmwareKind(for: game)
        let startupIdentity = WonderSwanOpenIPL.identityData(for: startupKind)
        appDiagnostic(
            "startup selected kind=\(startupKind.rawValue) source=openIPL identifier=\(WonderSwanOpenIPL.identifier)"
        )

            stopPlaying()
            let previousEmulationSession = retiringEmulationSession
            let isTranslationRun = translationRole != nil
            if let translationRole, let project, let romURL {
                activeTranslationRole = translationRole
                activeTranslationROMURL = romURL
                translationProject = project
                ephemeralTranslationGameID = id
            }
            let saveStore = saveStore
            let stateStore = stateStore
            let managedGameStore = managedGameStore
            let pacingPolicy = pacingPolicy
            playingGameID = id
            currentFrame = nil
            nextPresentedFrameNumber = nil
            playerStateNeedsNaturalFrame = false
            lastAudioFrameCount = 0
            isLaunchingGame = true
            playerLaunchStage = previousEmulationSession == nil
                ? .verifyingGame
                : .closingPreviousSession
            playerLaunchNeedsAttention = false
            isPaused = false
            inactivityPauseWasApplied = false
            isFastForwarding = false
            audioQueueMilliseconds = 0
            droppedAudioBatches = 0
            recoveredAudioDiscontinuities = 0
            resetPlayerVideoActivity()
            timelineStates = []
            isStateTimelinePresented = false
            resumeAfterTimeline = false
            resetRewindHistory()
            activeGameStateSessionIdentity = nil
            quickStateSavedAt = nil
            keyboardInput = []
            controllerInput = []
            frameAdvanceGate.reset()
            let generation = UUID()
            emulationGeneration = generation
            startPlayerLaunchWatchdog(generation: generation)

            do {
                try audioOutput.start()
            } catch {
                presentedError = "Audio output could not start: \(error.localizedDescription)"
            }

            let finalization = PlayerSessionFinalization()
            emulationFinalization = finalization
            emulationTask = Task { [weak self] in
                var sessionRunner: EmulationRunner?
                do {
                    if let previousEmulationSession {
                        // ares intentionally owns one live WonderSwan system.
                        // Await the cancelled session's final save and unload
                        // before constructing its replacement.
                        self?.playerLaunchStage = .closingPreviousSession
                        await previousEmulationSession.task.value
                        if let failure = await previousEmulationSession
                            .finalization.persistenceFailure() {
                            // Carry a failed save through a chain of rapid
                            // retries so a later session never silently loads
                            // older cartridge data.
                            await finalization.record(failure)
                        }
                        if self?.retiringEmulationSession?.id
                            == previousEmulationSession.id {
                            self?.retiringEmulationSession = nil
                        }
                    }
                    guard self?.emulationGeneration == generation, !Task.isCancelled else { return }
                    if let failure = await finalization.persistenceFailure() {
                        throw PreviousSessionSaveError(failure: failure)
                    }
                    self?.playerLaunchStage = .verifyingGame
                    let gameReference = game.managedROM
                    let gameURL = game.fileURL
                    let data = try await Task.detached(priority: .userInitiated) {
                        if let gameReference {
                            return try managedGameStore.load(gameReference)
                        }
                        return try Data(contentsOf: gameURL, options: [.mappedIfSafe])
                    }.value
                    let currentMetadata = try EngineSession.inspect(rom: data)
                    guard currentMetadata == game.metadata else {
                        throw GameLaunchIdentityError(title: game.title)
                    }
                    let stateSessionIdentity = GameStateSessionIdentity(
                        rom: data,
                        romChecksum: game.metadata.computedChecksum,
                        firmware: startupIdentity,
                        isColor: game.metadata.isColor,
                        hardwareModel: game.resolvedHardwareModel,
                        backend: self?.engineBackendName ?? "Unavailable",
                        engineBuildID: self?.engineBuildID
                    )
                    guard self?.emulationGeneration == generation,
                          !Task.isCancelled else { return }
                    self?.activeGameStateSessionIdentity = stateSessionIdentity
                    if !isTranslationRun {
                        let quickState = try? stateStore.loadQuickState(
                            gameID: game.id,
                            sessionIdentity: stateSessionIdentity
                        )
                        self?.quickStateSavedAt = quickState?.compatibility.isReady == true
                            && quickState?.previewIssue == nil
                            ? quickState?.manifest.createdAt
                            : nil
                        self?.timelineStates = (try? stateStore.listStates(
                            gameID: game.id,
                            sessionIdentity: stateSessionIdentity
                        )) ?? []
                    }
                    self?.playerLaunchStage = .startingEngine
                    let rtcMode: EngineRTCMode = isTranslationRun
                        ? .deterministic(
                            seedUnixSeconds: TranslationRouteRTCContext.proofSeedUnixSeconds
                        )
                        : .wallClock
                    let runner = try EmulationRunner(
                        rtcMode: rtcMode,
                        hardwareModel: game.resolvedHardwareModel
                    )
                    sessionRunner = runner
                    guard self?.emulationGeneration == generation,
                          !Task.isCancelled else {
                        try? await runner.stop()
                        return
                    }
                    self?.activeRunner = runner
                    self?.playerLaunchStage = .initializingSystem
                    guard self?.emulationGeneration == generation,
                          !Task.isCancelled else {
                        try? await runner.stop()
                        return
                    }
                    if !isTranslationRun {
                        self?.playerLaunchStage = .restoringSave
                        let saved = try await Task.detached(priority: .userInitiated) {
                            try saveStore.loadWithStatus(gameID: game.id)
                        }.value
                        try await runner.stagePersistence(saved.persistence)
                        if saved.recoveredPreviousGeneration {
                            self?.presentedNotice = "SwanSong recovered \(game.title)’s previous complete cartridge save because the newest generation was damaged or missing."
                        }
                        guard self?.emulationGeneration == generation,
                              !Task.isCancelled else {
                            try? await runner.stop()
                            return
                        }
                    }
                    self?.playerLaunchStage = .startingSystem
                    _ = try await runner.load(rom: data)
                    guard !Task.isCancelled,
                          self?.emulationGeneration == generation else {
                        try? await runner.stop()
                        return
                    }
                    self?.playerLaunchStage = .waitingForFirstFrame

                    var terminalError: Error?
                    var didRecordSuccessfulLaunch = false
                    do {
                        while !Task.isCancelled {
                            let isStepping = self?.frameAdvanceGate.consume(
                                whilePaused: self?.isPaused == true
                            ) == true
                            if self?.isPaused == true, !isStepping {
                                try await Task.sleep(for: .milliseconds(16))
                                continue
                            }
                            let manualInput = self?.activePlayerInput ?? []
                            let input = self?.translationInputForNextFrame(manualInput: manualInput)
                                ?? manualInput
                            guard let output = try await self?.producePlayerFrame(
                                with: runner,
                                input: input
                            ) else { break }
                            guard
                                !Task.isCancelled,
                                self?.emulationGeneration == generation
                            else { break }
                            let fastForwarding = self?.isFastForwarding == true
                            let videoFrame = self?.presentedPlayerFrame(output.video)
                                ?? output.video
                            self?.currentFrame = videoFrame
                            self?.playerStateNeedsNaturalFrame = false
                            if !isTranslationRun, !didRecordSuccessfulLaunch {
                                self?.recordSuccessfulLaunch(for: game)
                                didRecordSuccessfulLaunch = true
                            }
                            self?.lastAudioFrameCount = isStepping ? 0 : output.audio.frameCount
                            #if SWAN_SONG_AUTOMATION
                            self?.startAutomatedDebugLogIfRequested()
                            #endif
                            self?.recordDebugFrame(
                                input: input,
                                frame: videoFrame,
                                isFrameStep: isStepping
                            )
                            let audioStatus: AudioOutput.ScheduleResult?
                            if isStepping {
                                audioStatus = nil
                            } else {
                                audioStatus = self?.audioOutput.enqueue(output.audio)
                            }
                            self?.audioQueueMilliseconds = (audioStatus?.queuedSeconds ?? 0) * 1_000
                            if audioStatus?.dropped == true {
                                self?.droppedAudioBatches += 1
                            }
                            if audioStatus?.recoveredDiscontinuity == true {
                                self?.recoveredAudioDiscontinuities += 1
                                appDiagnostic(
                                    "audio transport discontinuity recovered; re-priming bounded queue"
                                )
                            }
                            self?.isLaunchingGame = false
                            self?.playerLaunchStage = nil
                            self?.playerLaunchNeedsAttention = false
                            if !isTranslationRun {
                                let isMeaningful = self?.observePlayerVideoActivity(videoFrame) == true
                                if self?.needsReachedVideoEvidence(for: game.id) == true,
                                   GameConfidence.isNonUniformNativeGameRaster(videoFrame) {
                                    self?.recordGameReachedVideo(game.id)
                                }
                                self?.captureAutomaticArtworkIfNeeded(
                                    videoFrame,
                                    isMeaningful: isMeaningful
                                )
                            }
                            #if SWAN_SONG_AUTOMATION
                            self?.captureAutomatedFrameIfRequested(videoFrame)
                            self?.captureAutomatedRewindReferenceIfRequested(videoFrame)
                            self?.triggerAutomatedRewindUndoIfRequested(at: videoFrame.number)
                            #endif
                            self?.didProduceTranslationFrame(
                                input: input,
                                frame: videoFrame
                            )
                            await self?.captureRewindCheckpointIfNeeded(
                                videoFrame,
                                runner: runner,
                                sessionGeneration: generation,
                                gameID: game.id
                            )
                            #if SWAN_SONG_AUTOMATION
                            if self?.automatedRewindAtFrame == videoFrame.number {
                                self?.automatedRewindAtFrame = nil
                                self?.rewindFiveSeconds()
                            }
                            #endif
                            if self?.automatedQuickStateFrames.first == videoFrame.number {
                                self?.automatedQuickStateFrames.removeFirst()
                                self?.saveQuickState()
                            }
                            #if SWAN_SONG_AUTOMATION
                            if self?.automatedQuickStateLoadFrame == videoFrame.number {
                                self?.automatedQuickStateLoadFrame = nil
                                self?.loadQuickState()
                            }
                            if self?.automatedResetFrame == videoFrame.number {
                                self?.automatedResetFrame = nil
                                self?.resetGame()
                            }
                            #endif
                            if self?.automatedStopAtFrame == videoFrame.number {
                                self?.automatedStopAtFrame = nil
                                #if SWAN_SONG_AUTOMATION
                                self?.exportAutomatedDebugLogIfRequested()
                                #endif
                                self?.stopPlaying()
                                break
                            }
                            if !isTranslationRun && output.video.number % 300 == 0 {
                                let snapshot = try await runner.capturePersistence()
                                try await Task.detached(priority: .utility) {
                                    try saveStore.save(snapshot, gameID: game.id)
                                }.value
                            }
                            let delay = self?.audioOutput.usesUnthrottledHeadlessMode == true
                                ? 0
                                : pacingPolicy.delaySeconds(
                                    producedAudioFrames: output.audio.frameCount,
                                    sampleRate: output.audio.sampleRate,
                                    queuedAudioSeconds: self?.audioOutput.pacingQueuedSeconds,
                                    fastForwarding: fastForwarding
                                )
                            if !isStepping, delay > 0 {
                                try await Task.sleep(
                                    nanoseconds: UInt64(delay * 1_000_000_000)
                                )
                            }
                        }
                    } catch is CancellationError {
                        // Continue through the final crash-safe save below.
                    } catch {
                        terminalError = error
                        self?.beginTerminalFailureFinalization(generation: generation)
                    }

                    let discardsFinalPersistence = self?
                        .discardFinalPersistenceGenerations.remove(generation) != nil
                    if !isTranslationRun, !discardsFinalPersistence {
                        do {
                            let finalSnapshot = try await runner.capturePersistence()
                            try await Task.detached(priority: .userInitiated) {
                                try saveStore.save(finalSnapshot, gameID: game.id)
                            }.value
                        } catch {
                            await finalization.record(
                                PlayerSessionPersistenceFailure(
                                    gameTitle: game.title,
                                    detail: error.localizedDescription
                                )
                            )
                            if terminalError == nil {
                                terminalError = error
                                self?.beginTerminalFailureFinalization(generation: generation)
                            }
                        }
                    }
                    try? await runner.stop()
                    if self?.emulationGeneration == generation {
                        self?.activeRunner = nil
                    }
                    if let terminalError {
                        let persistenceFailure = await finalization.persistenceFailure()
                        self?.handleTerminalEmulationFailure(
                            terminalError,
                            generation: generation,
                            persistenceFailure: persistenceFailure
                        )
                    }
                } catch {
                    self?.beginTerminalFailureFinalization(generation: generation)
                    if let sessionRunner {
                        try? await sessionRunner.stop()
                    }
                    if self?.emulationGeneration == generation {
                        self?.activeRunner = nil
                    }
                    let persistenceFailure = await finalization.persistenceFailure()
                    self?.handleTerminalEmulationFailure(
                        error,
                        generation: generation,
                        persistenceFailure: persistenceFailure
                    )
                }
            }
    }

    private func beginTerminalFailureFinalization(generation: UUID) {
        guard emulationGeneration == generation else { return }
        clearStateLoadUndo()
        isFinalizingFailedSession = true
        activeRunner = nil
        activeGameStateSessionIdentity = nil
        keyboardInput = []
        controllerInput = []
        frameAdvanceGate.reset()
        isPaused = false
        inactivityPauseWasApplied = false
        isFastForwarding = false
        playerStateOperationGeneration = UUID()
        playerStateOperation = nil
        playerStateOperationMayResumePlayback = false
        playerStateNeedsNaturalFrame = false
        isStateTimelinePresented = false
        resumeAfterTimeline = false
        resetRewindHistory()
        resetPlayerVideoActivity()
        audioOutput.stop()
    }

    private func handleTerminalEmulationFailure(
        _ error: Error,
        generation: UUID,
        persistenceFailure recordedPersistenceFailure: PlayerSessionPersistenceFailure?
    ) {
        guard emulationGeneration == generation else { return }
        let failedGame = playingGame
        let hadProducedFrame = currentFrame != nil
        let failedIntent = failedGame.flatMap(currentPlayerLaunchIntent)
        let managedFailureHealth = failedGame?.managedROM == nil
            ? nil
            : managedGameHealth(forLoadError: error)
        let persistenceFailure = recordedPersistenceFailure
            ?? (error as? PreviousSessionSaveError)?.failure

        // A failed final save always wins over a generic retry. Retrying could
        // otherwise load older cartridge data and make the data loss silent.
        if let persistenceFailure {
            stopPlaying()
            translationComparisonIsTransitioning = false
            resetTranslationSuiteExecution()
            presentedError = "SwanSong kept the player stopped because \(persistenceFailure.gameTitle)’s latest cartridge save could not be written: \(persistenceFailure.detail)"
            return
        }

        if error is GameSaveStoreError, let failedGame {
            // Retrying the same damaged save index cannot heal it and can hide
            // the distinction between game-media repair and save recovery.
            // Keep the failure in the player, but deliberately omit a retry.
            retirePlayerSession(preservingPlayerPresentation: true)
            translationComparisonIsTransitioning = false
            resetTranslationSuiteExecution()
            playerFailureRetryIntent = nil
            playerFailure = PlayerFailureState(
                gameID: failedGame.id,
                gameTitle: failedGame.title,
                detail: error.localizedDescription,
                phase: hadProducedFrame ? .playback : .launch
            )
            appDiagnostic("save integrity failure presented title=\(failedGame.title)")
            return
        }
        if let managedError = error as? ManagedGameStoreError,
           managedError == .unsafeStorage {
            stopPlaying()
            translationComparisonIsTransitioning = false
            resetTranslationSuiteExecution()
            presentedError = "SwanSong did not use the managed-game location because it is not a private folder owned by your account. Restore Application Support/SwanSong/Games to a regular private folder before playing or repairing games."
            return
        }
        if let failedGame, let managedFailureHealth {
            stopPlaying()
            translationComparisonIsTransitioning = false
            resetTranslationSuiteExecution()
            managedGameHealth[failedGame.id] = managedFailureHealth
            checkingManagedGameIDs.remove(failedGame.id)
            if managedFailureHealth == .invalidReference {
                presentedError = "The library identity for \(failedGame.title) is no longer valid. Re-add the original game as a new entry, confirm it works, then remove this entry. Saves, states, favorites, and artwork were not changed."
            } else {
                let condition = managedFailureHealth == .missing
                    ? "missing"
                    : "no longer matches its verified copy"
                presentedError = "The private copy for \(failedGame.title) is \(condition). Choose Repair and select the exact original game file. Saves, states, favorites, and artwork are unchanged."
            }
            return
        }

        guard let failedGame else {
            stopPlaying()
            presentedError = hadProducedFrame
                ? "The game stopped: \(error.localizedDescription)"
                : "The game could not start: \(error.localizedDescription)"
            return
        }

        retirePlayerSession(preservingPlayerPresentation: true)
        translationComparisonIsTransitioning = false
        resetTranslationSuiteExecution()
        playerFailureRetryIntent = failedIntent
        playerFailure = PlayerFailureState(
            gameID: failedGame.id,
            gameTitle: failedGame.title,
            detail: error.localizedDescription,
            phase: hadProducedFrame ? .playback : .launch
        )
        appDiagnostic(
            "player failure presented phase=\(hadProducedFrame ? "playback" : "launch") title=\(failedGame.title)"
        )
    }

    private func currentPlayerLaunchIntent(
        for game: GameRecord
    ) -> PlayerLaunchIntent? {
        guard let role = activeTranslationRole else {
            return .game(id: game.id, title: game.title)
        }
        guard let projectPath = translationProject?.rootURL.standardizedFileURL.path else {
            return nil
        }

        let continuation: TranslationLaunchContinuation
        if translationSuiteIsActive {
            continuation = .verifySuite
        } else if translationComparisonPhase != nil,
                  let route = translationComparisonRoute {
            // A/B retries restart the full pair from Original, never only the
            // failed lane.
            continuation = .verifyRoute(route)
        } else if let route = translationReplayRoute {
            continuation = .replay(role: role, route: route)
        } else {
            continuation = .play(
                role: role,
                recordingFromCleanBoot: translationRouteIsRecording
                    || translationRouteRecordingIsPreparing
            )
        }
        return .translation(
            continuation: continuation,
            projectPath: projectPath,
            title: game.title
        )
    }

    private func managedGameHealth(forLoadError error: Error) -> ManagedGameHealth? {
        if let cocoaError = error as? CocoaError,
           cocoaError.code == .fileReadNoSuchFile
            || cocoaError.code == .fileNoSuchFile {
            return .missing
        }
        if let managedError = error as? ManagedGameStoreError {
            switch managedError {
            case .unsafeStorage:
                return nil
            case .invalidReference:
                return .invalidReference
            default:
                return .changed
            }
        }
        return nil
    }

    private func recordSuccessfulLaunch(for game: GameRecord) {
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[index].lastPlayedAt = Date()
        try? persist()
        pendingAutomaticArtworkGameID = game.artworkPreference == .procedural
            || gameArtwork[game.id] != nil
            ? nil
            : game.id
    }

    private func recordGameReachedVideo(
        _ id: GameRecord.ID,
        at date: Date = Date()
    ) {
        guard activeTranslationRole == nil else { return }
        updateGameCompatibilityEvidence(for: id, failureMessage: nil) { current in
            let updated = (current ?? GameCompatibilityEvidence())
                .recordingReachedVideo(at: date)
            return updated.isEmpty ? nil : updated
        }
    }

    private func needsReachedVideoEvidence(for id: GameRecord.ID) -> Bool {
        guard let game = games.first(where: { $0.id == id }) else { return false }
        return game.compatibilityEvidence?.reachedVideoAt == nil
    }

    private func updateGameCompatibilityEvidence(
        for id: GameRecord.ID,
        failureMessage: String?,
        transform: (GameCompatibilityEvidence?) -> GameCompatibilityEvidence?
    ) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        let previous = games[index].compatibilityEvidence
        let updated = transform(previous)
        guard updated != previous else { return }
        games[index].compatibilityEvidence = updated
        do {
            try persist()
        } catch {
            games[index].compatibilityEvidence = previous
            if let failureMessage {
                presentedError = failureMessage
            } else {
                appDiagnostic(
                    "reached-video evidence was not saved game=\(id) issue=\(error.localizedDescription)"
                )
            }
        }
    }

    private func startPlayerLaunchWatchdog(generation: UUID) {
        Task { [weak self] in
            var activeWait = Duration.zero
            while activeWait < .seconds(10) {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self,
                      self.emulationGeneration == generation,
                      self.isLaunchingGame,
                      self.currentFrame == nil else { return }
                if self.applicationIsActive, !self.isPaused {
                    activeWait += .milliseconds(500)
                }
            }
            guard let self,
                  self.emulationGeneration == generation,
                  self.isLaunchingGame,
                  self.currentFrame == nil else { return }
            self.playerLaunchNeedsAttention = true
            appDiagnostic("player launch is still waiting for its first frame")
        }
    }

    private func producePlayerFrame(
        with runner: EmulationRunner,
        input: EngineInput
    ) async throws -> (video: EngineVideoFrame, audio: EngineAudioBatch) {
        playerFrameProductionIsInFlight = true
        do {
            let output = try await runner.nextFrame(input: input)
            finishPlayerFrameProduction()
            return output
        } catch {
            finishPlayerFrameProduction()
            throw error
        }
    }

    private func finishPlayerFrameProduction() {
        guard playerFrameProductionIsInFlight else { return }
        playerFrameProductionIsInFlight = false
        let waiters = playerFrameProductionWaiters
        playerFrameProductionWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
    }

    private func captureRewindCheckpointIfNeeded(
        _ frame: EngineVideoFrame,
        runner: EmulationRunner,
        sessionGeneration: UUID,
        gameID: GameRecord.ID
    ) async {
        guard frame.number.isMultiple(of: rewindCaptureFrameInterval),
              playerStateOperation == nil,
              !playerStateNeedsNaturalFrame,
              !isRewindPresented,
              !translationRouteIsRecording,
              !translationRouteRecordingIsPreparing,
              !translationReplayIsActive,
              !translationComparisonIsActive,
              !translationComparisonIsTransitioning,
              !isCapturingTranslationEvidence else { return }
        do {
            let state = try await runner.captureState()
            guard isCurrentPlayerSession(
                generation: sessionGeneration,
                gameID: gameID
            ), playerStateOperation == nil,
               !isRewindPresented else { return }
            let checkpoint = try RewindCheckpoint(
                state: state,
                previewFrame: frame
            )
            _ = try rewindBuffer.append(checkpoint)
            rewindCheckpoints = rewindBuffer.checkpoints
            #if SWAN_SONG_AUTOMATION
            if automatedRewindUndoHasCompleted,
               !automatedRewindHistoryHasRebuilt {
                automatedRewindHistoryHasRebuilt = true
                appDiagnostic(
                    "rewind history rebuilt frame=\(frame.number) count=\(rewindCheckpoints.count) paused=\(isPaused) operation_idle=\(playerStateOperation == nil)"
                )
            }
            #endif
        } catch is CancellationError {
            return
        } catch {
            // Rewind is an optional safety net. A failed in-memory checkpoint
            // must never interrupt gameplay or be mistaken for a disk save.
            appDiagnostic(
                "rewind checkpoint skipped frame=\(frame.number) issue=\(error.localizedDescription)"
            )
        }
    }

    private func resetRewindHistory() {
        rewindBuffer.reset()
        rewindCheckpoints = []
        selectedRewindCheckpointID = nil
        isRewindPresented = false
        resumeAfterRewind = false
    }

    private func waitForPlayerFrameProductionToQuiesce() async {
        guard playerFrameProductionIsInFlight else { return }
        await withCheckedContinuation { continuation in
            if playerFrameProductionIsInFlight {
                playerFrameProductionWaiters.append(continuation)
            } else {
                continuation.resume()
            }
        }
    }

    private func presentedPlayerFrame(_ frame: EngineVideoFrame) -> EngineVideoFrame {
        guard let number = nextPresentedFrameNumber else { return frame }
        let (followingNumber, overflow) = number.addingReportingOverflow(1)
        nextPresentedFrameNumber = overflow ? nil : followingNumber
        return EngineVideoFrame(
            pixels: frame.pixels,
            width: frame.width,
            height: frame.height,
            strideBytes: frame.strideBytes,
            isVertical: frame.isVertical,
            number: number
        )
    }

    private func continuePresentedFrameNumbers(afterSettledStateFrame number: UInt64) {
        // The frontend needs one discarded output after unserialization. The
        // first naturally presented output is therefore two emulated frames
        // after the saved preview, regardless of the bridge's process-local
        // frame counter.
        let (next, overflow) = number.addingReportingOverflow(2)
        nextPresentedFrameNumber = overflow ? nil : next
    }

    private func displayFrame(for saved: GameStateRecord) throws -> EngineVideoFrame {
        if let issue = saved.previewIssue {
            throw StatePreviewUnavailableError(detail: issue)
        }
        do {
            return try ScreenshotExporter.frame(
                fromPNG: saved.previewPNG,
                frameNumber: saved.manifest.frameNumber
            )
        } catch {
            throw StatePreviewUnavailableError(detail: error.localizedDescription)
        }
    }

    private func requireCaptureAlignedPlayerFrame(for action: String) -> Bool {
        guard playerStateNeedsNaturalFrame else { return true }
        presentedNotice = "Advance one frame or resume the game before \(action). SwanSong is keeping the restored preview visible until the next exact frame arrives."
        return false
    }

    @discardableResult
    private func beginPlayerStateOperation(
        _ operation: PlayerStateOperation,
        resumesPlayback: Bool
    ) -> UUID {
        let generation = UUID()
        playerStateOperationGeneration = generation
        playerStateOperation = operation
        playerStateOperationMayResumePlayback = resumesPlayback
        return generation
    }

    @discardableResult
    private func finishPlayerStateOperation(_ generation: UUID) -> Bool {
        guard playerStateOperationGeneration == generation else { return false }
        playerStateOperation = nil
        playerStateOperationMayResumePlayback = false
        return true
    }

    private func clearStateLoadUndo() {
        if let stateLoadUndoManager, let stateLoadUndoTarget {
            stateLoadUndoManager.removeAllActions(withTarget: stateLoadUndoTarget)
        }
        stateLoadUndoManager = nil
        stateLoadUndoTarget = nil
        stateLoadUndoPoint = nil
        stateLoadUndoMessage = nil
        stateLoadUndoActionName = "Load State"
    }

    private func registerStateLoadUndoAction(
        using undoManager: UndoManager? = nil,
        actionName: String? = nil
    ) {
        guard stateLoadUndoPoint != nil else { return }
        if let actionName { stateLoadUndoActionName = actionName }
        if let stateLoadUndoManager, let stateLoadUndoTarget {
            stateLoadUndoManager.removeAllActions(withTarget: stateLoadUndoTarget)
        }
        guard let manager = undoManager
                ?? stateLoadUndoManager
                ?? NSApp.keyWindow?.undoManager
                ?? NSApp.mainWindow?.undoManager else {
            stateLoadUndoManager = nil
            stateLoadUndoTarget = nil
            return
        }
        let target = StateLoadUndoActionTarget(model: self)
        manager.registerUndo(withTarget: target) { target in
            target.perform()
        }
        manager.setActionName(stateLoadUndoActionName)
        stateLoadUndoManager = manager
        stateLoadUndoTarget = target
    }

    private func beginTrackedPlayerStateTransaction() -> UUID {
        let transactionID = UUID()
        playerStateTransactionID = transactionID
        return transactionID
    }

    private func trackPlayerStateTransaction(
        _ task: Task<Void, Never>,
        id: UUID
    ) {
        guard playerStateTransactionID == id else {
            task.cancel()
            return
        }
        playerStateTransactionTask = task
    }

    private func finishTrackedPlayerStateTransaction(_ id: UUID) {
        guard playerStateTransactionID == id else { return }
        playerStateTransactionTask = nil
        guard let pendingPlayerRetirement else { return }
        self.pendingPlayerRetirement = nil
        retirePlayerSession(
            preservingPlayerPresentation: pendingPlayerRetirement.preservingPlayerPresentation
        )
    }

    private func makeStateLoadRollbackPoint(
        runner: EmulationRunner,
        sessionGeneration: UUID,
        gameID: GameRecord.ID
    ) async throws -> StateLoadRollbackPoint {
        let state = try await runner.captureState()
        guard isCurrentPlayerSession(
            generation: sessionGeneration,
            gameID: gameID
        ), let frame = currentFrame else {
            throw CancellationError()
        }
        return StateLoadRollbackPoint(
            sessionGeneration: sessionGeneration,
            gameID: gameID,
            state: state,
            frame: frame
        )
    }

    private func restoreStateLoadRollback(
        _ rollback: StateLoadRollbackPoint,
        with runner: EmulationRunner
    ) async throws -> String? {
        try await runner.restoreState(rollback.state)
        // ares does not serialize its frontend raster/audio history. Consume
        // the single unsettled output while the known-good rollback frame
        // remains visible; the following natural frame is exact.
        _ = try await runner.nextFrame(input: [])
        guard isCurrentPlayerSession(
            generation: rollback.sessionGeneration,
            gameID: rollback.gameID
        ) else { throw CancellationError() }
        continuePresentedFrameNumbers(
            afterSettledStateFrame: rollback.frame.number
        )
        currentFrame = rollback.frame
        playerStateNeedsNaturalFrame = true
        resetPlayerVideoActivity()
        _ = observePlayerVideoActivity(rollback.frame)
        return restartAudioAfterStateChange(paused: true)
    }

    private func registerSuccessfulStateLoad(
        rollback: StateLoadRollbackPoint,
        savedAt: Date,
        frame: EngineVideoFrame,
        undoManager: UndoManager?
    ) -> String? {
        resetRewindHistory()
        currentFrame = frame
        playerStateNeedsNaturalFrame = true
        resetPlayerVideoActivity()
        _ = observePlayerVideoActivity(frame)
        stateLoadUndoPoint = rollback
        stateLoadUndoMessage = "Loaded state from \(savedAt.formatted(date: .abbreviated, time: .shortened))."
        registerStateLoadUndoAction(using: undoManager)
        #if SWAN_SONG_AUTOMATION
        captureAutomatedStateLoadPreviewIfRequested(frame)
        #endif
        return restartAudioAfterStateChange(paused: true)
    }

    private func restartAudioAfterStateChange(paused: Bool) -> String? {
        audioOutput.stop()
        do {
            try audioOutput.start()
            audioOutput.setFastForwarding(isFastForwarding)
            audioOutput.setPaused(paused)
            return nil
        } catch {
            return "The game state changed successfully, but audio could not restart: \(error.localizedDescription)"
        }
    }

    private func stopAfterUnrecoverableStateLoad(
        runner: EmulationRunner,
        sessionGeneration: UUID,
        gameID: GameRecord.ID,
        loadError: Error,
        rollbackError: Error
    ) async {
        guard emulationGeneration == sessionGeneration,
              playingGameID == gameID else { return }
        // This runner is intentionally discarded. Mark its generation before
        // cancellation so the emulation loop cannot capture candidate or
        // partially restored cartridge persistence during finalization.
        discardFinalPersistenceGenerations.insert(sessionGeneration)
        pendingPlayerRetirement = nil
        retirePlayerSession(preservingPlayerPresentation: false)
        try? await runner.stop()
        presentedError = "The saved state could not be loaded, and SwanSong could not restore the rollback point. The player stopped without saving the uncertain cartridge state. Load error: \(loadError.localizedDescription) Rollback error: \(rollbackError.localizedDescription)"
    }

    private func isCurrentPlayerSession(
        generation: UUID,
        gameID: GameRecord.ID
    ) -> Bool {
        emulationGeneration == generation
            && playingGameID == gameID
            && activeRunner != nil
    }

    private func playerSessionReplacementIsAvailable() -> Bool {
        guard playerStateTransactionTask == nil else {
            presentedNotice = "SwanSong is finishing a saved-state transaction safely. Wait a moment, then try again."
            return false
        }
        return true
    }

    func playSelectedGame() {
        guard let selectedGameID else { return }
        play(selectedGameID)
    }

    func stopPlaying() {
        if playerStateTransactionTask != nil {
            pendingPlayerRetirement = PendingPlayerRetirement(
                preservingPlayerPresentation: false
            )
            keyboardInput = []
            controllerInput = []
            isPaused = true
            audioOutput.setPaused(true)
            return
        }
        retirePlayerSession(preservingPlayerPresentation: false)
    }

    private func retirePlayerSession(preservingPlayerPresentation: Bool) {
        stopDebugLogRegardless()
        let shouldCancelTranslationSuite = translationSuiteIsActive
            && !translationComparisonIsTransitioning
        cancelTranslationRouteRecording(showNotice: false)
        if let emulationTask, let emulationFinalization {
            let retiringSession = RetiringEmulationSession(
                id: UUID(),
                task: emulationTask,
                finalization: emulationFinalization
            )
            emulationTask.cancel()
            retiringEmulationSession = retiringSession
            observeRetiringEmulationSession(retiringSession)
        } else {
            emulationTask?.cancel()
        }
        emulationTask = nil
        emulationFinalization = nil
        playerStateTransactionID = UUID()
        playerStateTransactionTask = nil
        pendingPlayerRetirement = nil
        emulationGeneration = UUID()
        activeRunner = nil
        activeGameStateSessionIdentity = nil
        clearStateLoadUndo()
        playerFailure = nil
        playerFailureRetryIntent = nil
        isFinalizingFailedSession = false
        if !preservingPlayerPresentation {
            playingGameID = nil
            currentFrame = nil
        }
        isLaunchingGame = false
        playerLaunchStage = nil
        playerLaunchNeedsAttention = false
        playerStateOperationGeneration = UUID()
        playerStateOperation = nil
        playerStateOperationMayResumePlayback = false
        playerStateNeedsNaturalFrame = false
        nextPresentedFrameNumber = nil
        timelineStates = []
        isStateTimelinePresented = false
        resumeAfterTimeline = false
        resetRewindHistory()
        lastAudioFrameCount = 0
        isPaused = false
        inactivityPauseWasApplied = false
        isFastForwarding = false
        audioQueueMilliseconds = 0
        droppedAudioBatches = 0
        recoveredAudioDiscontinuities = 0
        resetPlayerVideoActivity()
        pendingAutomaticArtworkGameID = nil
        keyboardInput = []
        controllerInput = []
        frameAdvanceGate.reset()
        if !preservingPlayerPresentation {
            activeTranslationRole = nil
            activeTranslationROMURL = nil
        }
        translationRouteRecorder = nil
        translationRouteIsRecording = false
        translationRouteRecordingIsPreparing = false
        translationReplayRoute = nil
        translationReplayFrameIndex = 0
        translationReplayProgress = nil
        translationEvidenceRoute = nil
        translationEvidenceRouteFrameNumber = nil
        if isCapturingTranslationEvidence {
            translationToolPhase = nil
        }
        isCapturingTranslationEvidence = false
        translationComparisonPhase = nil
        translationComparisonRoute = nil
        if !preservingPlayerPresentation, let ephemeralTranslationGameID {
            games.removeAll { $0.id == ephemeralTranslationGameID }
            if selectedGameID == ephemeralTranslationGameID {
                selectedGameID = nil
            }
            self.ephemeralTranslationGameID = nil
        }
        audioOutput.stop()
        if shouldCancelTranslationSuite {
            resetTranslationSuiteExecution()
        }
    }

    private func observeRetiringEmulationSession(
        _ session: RetiringEmulationSession
    ) {
        Task { [weak self] in
            await session.task.value
            let failure = await session.finalization.persistenceFailure()
            guard let self,
                  self.retiringEmulationSession?.id == session.id,
                  self.emulationTask == nil else { return }
            self.retiringEmulationSession = nil
            guard let failure else { return }
            self.presentedError = "\(failure.gameTitle) closed, but its latest cartridge save could not be written: \(failure.detail)"
        }
    }

    /// Completes the crash-safe cartridge save before AppKit allows the
    /// process to terminate. Returning false keeps the app open so a timeout
    /// or write failure cannot become silent progress loss.
    func beginTerminationAttempt() {
        terminationIsInProgress = true
        translationVisualDivergenceGeneration = UUID()
        translationVisualDivergenceTask?.cancel()
        keyboardInput = []
        controllerInput = []
    }

    func prepareForTermination() async -> Bool {
        terminationIsInProgress = true
        if let stateTransaction = playerStateTransactionTask {
            let finished = await PlayerSessionRetirement.finishes(
                stateTransaction,
                within: .seconds(5)
            )
            guard finished else {
                terminationIsInProgress = false
                presentedError = "SwanSong is still finishing a saved-state transaction safely. The app stayed open; wait a moment, then quit again."
                appDiagnostic("application termination canceled during state transaction")
                return false
            }
        }
        if emulationTask != nil { stopPlaying() }
        guard let session = retiringEmulationSession else { return true }

        let finished = await PlayerSessionRetirement.finishes(
            session.task,
            within: .seconds(5)
        )
        guard finished else {
            terminationIsInProgress = false
            presentedError = "SwanSong is still closing the active game safely. The app stayed open; wait a moment, then quit again."
            appDiagnostic("application termination canceled after session-finalization timeout")
            return false
        }

        let failure = await session.finalization.persistenceFailure()
        if retiringEmulationSession?.id == session.id {
            retiringEmulationSession = nil
        }
        guard let failure else { return true }
        terminationIsInProgress = false
        presentedError = "SwanSong stayed open because \(failure.gameTitle)’s latest cartridge save could not be written: \(failure.detail)"
        appDiagnostic("application termination canceled after final-save failure")
        return false
    }

    func setDebugToolsEnabled(_ enabled: Bool) {
        guard debugToolsEnabled != enabled else { return }
        debugToolsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.debugToolsDefaultsKey)
        if !enabled {
            debugOverlayIsVisible = false
            debugLastEffectiveInput = []
            stopDebugLogRegardless()
        }
    }

    var localMCPControlEnabled: Bool {
        UserDefaults.standard.bool(forKey: SwanSongLocalMCPAccess.enabledDefaultsKey)
    }

    func setLocalMCPControlEnabled(_ enabled: Bool) {
        guard localMCPControlEnabled != enabled else { return }
        do {
            if enabled {
                _ = try SwanSongLocalMCPAccess.ensureToken()
                UserDefaults.standard.set(
                    true,
                    forKey: SwanSongLocalMCPAccess.enabledDefaultsKey
                )
                presentedNotice = "Local MCP control is ready for trusted tools on this Mac."
            } else {
                UserDefaults.standard.set(
                    false,
                    forKey: SwanSongLocalMCPAccess.enabledDefaultsKey
                )
                try SwanSongLocalMCPAccess.revokeToken()
                presentedNotice = "Local MCP control is off and its access token was revoked."
            }
        } catch {
            UserDefaults.standard.set(
                false,
                forKey: SwanSongLocalMCPAccess.enabledDefaultsKey
            )
            presentedError = "Local MCP control could not be changed: \(error.localizedDescription)"
        }
    }

    func setDebugOverlayVisible(_ visible: Bool) {
        guard debugToolsEnabled else {
            debugOverlayIsVisible = false
            return
        }
        debugOverlayIsVisible = visible
    }

    func updateDebugGameplayFocus(_ hasFocus: Bool) {
        debugGameplayHasFocus = hasFocus
    }

    func startDebugLog() {
        guard debugToolsEnabled else { return }
        guard playerIsInteractive,
              let game = playingGame,
              let identity = activeGameStateSessionIdentity else {
            presentedError = "Start a game and wait for its first frame before recording an input/frame log."
            return
        }
        beginDebugLog(game: game, identity: identity, announce: true)
    }

    private func beginDebugLog(
        game: GameRecord,
        identity: GameStateSessionIdentity,
        announce: Bool
    ) {
        let info = Bundle.main.infoDictionary ?? [:]
        let session = GameDebugSession(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "development",
            appBuild: info["CFBundleVersion"] as? String ?? "development",
            engineBackend: engineBackendName,
            engineBuildID: engineBuildID,
            gameTitle: game.title,
            romSHA256: identity.romSHA256,
            romByteCount: identity.romByteCount,
            romChecksum: identity.romChecksum,
            hardwareModel: identity.hardwareModel.rawValue,
            openIPLIdentifier: WonderSwanOpenIPL.identifier,
            controllerName: connectedControllerName
        )
        debugLogRecorder = GameDebugLogRecorder(session: session)
        debugLogIsRecording = true
        debugLogFrameCount = 0
        debugLogDroppedFrameCount = 0
        debugLastExportURL = nil
        if announce {
            presentedNotice = "Input/frame logging started."
        }
    }

    func stopDebugLog() {
        guard debugToolsEnabled else { return }
        stopDebugLogRegardless()
    }

    func clearDebugLog() {
        guard debugToolsEnabled else { return }
        debugLogRecorder = nil
        debugLogIsRecording = false
        debugLogFrameCount = 0
        debugLogDroppedFrameCount = 0
        debugLastExportURL = nil
    }

    func exportDebugLog() {
        guard debugToolsEnabled else { return }
        guard let recorder = debugLogRecorder,
              recorder.totalFrameCount > 0 else {
            presentedError = "Record at least one game frame before exporting a debug log."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Input/Frame Log"
        panel.prompt = "Export Log"
        panel.nameFieldStringValue = "SwanSong-input-frame-log.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeDebugLog(recorder, to: url, announce: true)
    }

    private func writeDebugLog(
        _ recorder: GameDebugLogRecorder,
        to url: URL,
        announce: Bool
    ) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys,
                .withoutEscapingSlashes,
            ]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(recorder.snapshot())
            try data.write(to: url, options: .atomic)
            debugLastExportURL = url
            if announce {
                presentedNotice = "Exported \(debugLogFrameCount.formatted()) input/frame records."
            }
        } catch {
            presentedError = "The input/frame log could not be exported: \(error.localizedDescription)"
            appDiagnostic("debug log export failed: \(error.localizedDescription)")
        }
    }

    #if SWAN_SONG_AUTOMATION
    private func startAutomatedDebugLogIfRequested() {
        guard automatedDebugLogURL != nil,
              debugLogRecorder == nil,
              let game = playingGame,
              let identity = activeGameStateSessionIdentity else { return }
        beginDebugLog(game: game, identity: identity, announce: false)
    }

    private func exportAutomatedDebugLogIfRequested() {
        guard let url = automatedDebugLogURL,
              let recorder = debugLogRecorder,
              recorder.totalFrameCount > 0 else { return }
        writeDebugLog(recorder, to: url, announce: false)
    }
    #endif

    private func stopDebugLogRegardless() {
        debugLogIsRecording = false
    }

    private func recordDebugFrame(
        input: EngineInput,
        frame: EngineVideoFrame,
        isFrameStep: Bool
    ) {
        guard debugToolsEnabled else { return }
        debugLastEffectiveInput = input
        guard debugLogIsRecording,
              var recorder = debugLogRecorder else { return }
        let focus: GameDebugFocusState
        if !applicationIsActive {
            focus = .applicationInactive
        } else if debugGameplayHasFocus {
            focus = .keyboardActive
        } else {
            focus = .keyboardInactive
        }
        recorder.record(
            frame: frame,
            keyboardInput: keyboardInput,
            controllerInput: gameplayControllerInput,
            effectiveInput: input,
            focus: focus,
            isPaused: isPaused,
            isFastForwarding: isFastForwarding,
            isFrameStep: isFrameStep,
            audioFrameCount: lastAudioFrameCount
        )
        debugLogRecorder = recorder
        debugLogFrameCount = Int(clamping: recorder.totalFrameCount)
        debugLogDroppedFrameCount = recorder.droppedFrameCount
    }

    func setKeyboardButton(_ button: EngineInput, pressed: Bool) {
        guard playerIsInteractive else {
            keyboardInput = []
            return
        }
        if pressed {
            keyboardInput.insert(button)
        } else {
            keyboardInput.remove(button)
        }
    }

    func clearKeyboardInput() {
        keyboardInput = []
    }

    func applyControllerPreset(_ preset: ControllerMappingPreset) {
        guard preset != .custom else { return }
        controllerLearningControl = nil
        applyControllerProfile(.preset(preset))
    }

    func setControllerBinding(
        _ control: WonderSwanControl,
        to element: ControllerElement?
    ) {
        controllerLearningControl = nil
        applyControllerProfile(controllerProfile.updating(control, to: element))
    }

    func beginLearningControllerBinding(_ control: WonderSwanControl) {
        guard connectedControllerName != nil else {
            presentedError = "Connect a controller before learning a physical control. You can still choose a binding manually."
            return
        }
        controllerLearningControl = control
        controllerInput = []
    }

    func cancelLearningControllerBinding() {
        controllerLearningControl = nil
        controllerInput = controllerProfile.input(for: controllerPhysicalElements)
    }

    func handleControllerElements(_ elements: Set<ControllerElement>) {
        let newlyPressed = elements.subtracting(controllerPhysicalElements)
        controllerPhysicalElements = elements
        if let learning = controllerLearningControl {
            if let element = ControllerElement.allCases.first(where: newlyPressed.contains) {
                controllerLearningControl = nil
                applyControllerProfile(
                    controllerProfile.updating(learning, to: element),
                    suppressCurrentInput: true
                )
            } else {
                controllerInput = []
            }
            return
        }
        guard playerIsInteractive else {
            controllerInput = []
            return
        }
        controllerInput = controllerProfile.input(for: elements)
    }

    private func applyControllerProfile(
        _ profile: ControllerProfile,
        suppressCurrentInput: Bool = false
    ) {
        controllerProfile = profile
        controllerInput = suppressCurrentInput
            ? []
            : profile.input(for: controllerPhysicalElements)
        do {
            try controllerProfileStore.save(profile)
        } catch {
            presentedError = "The controller mapping could not be saved: \(error.localizedDescription)"
        }
    }

    func togglePause() {
        guard canTogglePause else { return }
        inactivityPauseWasApplied = false
        if isPaused {
            frameAdvanceGate.reset()
            translationEvidenceRoute = nil
            translationEvidenceRouteFrameNumber = nil
        }
        isPaused.toggle()
        audioOutput.setPaused(isPaused)
    }

    func advanceOneFrame() {
        guard canAdvanceFrame else { return }
        _ = frameAdvanceGate.request()
    }

    func dismissPlayerVideoActivityDiagnostic() {
        playerVideoActivityDiagnostic.dismissWarning()
    }

    func presentPlayerVideoActivityDiagnostic() {
        playerVideoActivityDiagnostic.presentWarning()
    }

    func updateApplicationActivity(isActive: Bool, pauseWhenInactive: Bool) {
        applicationIsActive = isActive
        if isActive {
            controller.resumeGameplayInput()
            refreshManagedGameHealth()
        } else {
            // macOS suppresses controller events for a background app by
            // default. Neutralize both input sources now, then resnapshot
            // connected controllers when SwanSong becomes active again.
            keyboardInput = []
            controllerLearningControl = nil
            controller.suspendGameplayInput()
            controllerPhysicalElements = []
            controllerInput = []
        }
        guard playerIsInteractive else {
            inactivityPauseWasApplied = false
            return
        }

        if !isActive, pauseWhenInactive {
            if isPaused {
                if playerStateOperation != nil,
                   playerStateOperationMayResumePlayback,
                   !isStateTimelinePresented {
                    inactivityPauseWasApplied = true
                }
                return
            }
            inactivityPauseWasApplied = true
            isPaused = true
            audioOutput.setPaused(true)
        } else if inactivityPauseWasApplied {
            inactivityPauseWasApplied = false
            if playerStateOperation == nil, !isStateTimelinePresented {
                isPaused = false
                audioOutput.setPaused(false)
            }
        }
    }

    func toggleFastForward() {
        guard canToggleFastForward else { return }
        isFastForwarding.toggle()
        audioOutput.setFastForwarding(isFastForwarding)
    }

    func resetGame() {
        guard canResetGame,
              let activeRunner,
              let gameID = playingGameID else { return }
        let sessionGeneration = emulationGeneration
        let wasPaused = isPaused
        let operationGeneration = beginPlayerStateOperation(
            .resetting,
            resumesPlayback: !wasPaused
        )
        isPaused = true
        audioOutput.setPaused(true)
        frameAdvanceGate.reset()
        keyboardInput = []
        controllerInput = []
        translationEvidenceRoute = nil
        translationEvidenceRouteFrameNumber = nil
        let transactionID = beginTrackedPlayerStateTransaction()
        let transactionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishTrackedPlayerStateTransaction(transactionID) }
            do {
                await self.waitForPlayerFrameProductionToQuiesce()
                try await activeRunner.reset()
                guard self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: gameID
                ) else { return }
                self.nextPresentedFrameNumber = nil
                let output = try await activeRunner.nextFrame(input: [])
                guard self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: gameID
                ) else { return }
                self.currentFrame = output.video
                self.playerStateNeedsNaturalFrame = false
                self.lastAudioFrameCount = 0
                self.resetRewindHistory()
                self.clearStateLoadUndo()
                self.resetPlayerVideoActivity()
                if self.activeTranslationRole == nil {
                    _ = self.observePlayerVideoActivity(output.video)
                }
                let audioIssue = self.restartAudioAfterStateChange(paused: true)
                guard self.finishPlayerStateOperation(operationGeneration),
                      self.isCurrentPlayerSession(
                        generation: sessionGeneration,
                        gameID: gameID
                      ) else { return }
                let shouldRemainPaused = wasPaused || self.inactivityPauseWasApplied
                self.isPaused = shouldRemainPaused
                self.audioOutput.setPaused(shouldRemainPaused)
                appDiagnostic("game reset frame=\(output.video.number)")
                if let audioIssue { self.presentedError = audioIssue }
            } catch {
                guard self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: gameID
                ) else { return }
                _ = self.finishPlayerStateOperation(operationGeneration)
                // A failed reset can leave the emulator between reset phases.
                // Stop without publishing uncertain cartridge persistence.
                self.discardFinalPersistenceGenerations.insert(sessionGeneration)
                self.presentedError = "The game could not be reset safely, so SwanSong stopped it without saving uncertain cartridge data: \(error.localizedDescription)"
                self.stopPlaying()
            }
        }
        trackPlayerStateTransaction(transactionTask, id: transactionID)
    }

    func restartCurrentSession() {
        guard !terminationIsInProgress else { return }
        guard playerSessionReplacementIsAvailable() else { return }
        guard let game = playingGame else { return }
        guard let intent = currentPlayerLaunchIntent(for: game) else { return }
        stopPlaying()
        resumePlayerIntent(
            intent,
            diagnosticContext: "player restart",
            deferred: false
        )
    }

    func retryPlayerFailure() {
        guard !terminationIsInProgress else { return }
        guard playerSessionReplacementIsAvailable() else { return }
        guard playerFailure != nil,
              let intent = playerFailureRetryIntent else { return }
        stopPlaying()
        resumePlayerIntent(
            intent,
            diagnosticContext: "player failure retry",
            deferred: false
        )
    }

    func captureScreenshot() {
        guard let currentFrame else { return }
        do {
            let png = try ScreenshotExporter.pngData(for: currentFrame)
            let panel = NSSavePanel()
            panel.title = "Save WonderSwan Screenshot"
            panel.prompt = "Save Screenshot"
            panel.allowedContentTypes = [.png]
            panel.canCreateDirectories = true
            let gameName = playingGame?.title ?? "WonderSwan"
            let timestamp = ISO8601DateFormatter()
                .string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            panel.nameFieldStringValue = "\(gameName) \(timestamp).png"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try png.write(to: url, options: [.atomic])
        } catch {
            presentedError = "The screenshot could not be saved: \(error.localizedDescription)"
        }
    }

    func useCurrentFrameAsLibraryArtwork() {
        guard activeTranslationRole == nil,
              let game = playingGame,
              let currentFrame else { return }
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        let previousPreference = games[index].artworkPreference
        games[index].artworkPreference = .automatic
        do {
            try persist()
            try saveGameArtwork(currentFrame, for: games[index], source: .userSelected)
            pendingAutomaticArtworkGameID = nil
            presentedError = nil
            presentedNotice = "Library artwork updated from frame \(currentFrame.number). It is stored only on this Mac."
        } catch {
            games[index].artworkPreference = previousPreference
            try? persist()
            presentedError = "The current frame could not be saved as library artwork: \(error.localizedDescription)"
        }
    }

    func useProceduralArtwork(_ id: GameRecord.ID) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        let previousPreference = games[index].artworkPreference
        games[index].artworkPreference = .procedural
        do {
            try persist()
            try artworkStore.remove(gameID: id)
            gameArtwork.removeValue(forKey: id)
            if pendingAutomaticArtworkGameID == id {
                pendingAutomaticArtworkGameID = nil
            }
            presentedNotice = "Using procedural artwork for \(games[index].title)."
        } catch {
            games[index].artworkPreference = previousPreference
            try? persist()
            presentedError = "The artwork preference could not be changed: \(error.localizedDescription)"
        }
    }

    func captureArtworkNextTimePlayed(_ id: GameRecord.ID) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        let previousPreference = games[index].artworkPreference
        games[index].artworkPreference = .automatic
        do {
            try persist()
            try artworkStore.remove(gameID: id)
            gameArtwork.removeValue(forKey: id)
            presentedNotice = "SwanSong will capture a private gameplay image after \(games[index].title) starts."
        } catch {
            games[index].artworkPreference = previousPreference
            try? persist()
            presentedError = "Automatic artwork could not be enabled: \(error.localizedDescription)"
        }
    }

    private func captureAutomaticArtworkIfNeeded(
        _ frame: EngineVideoFrame,
        isMeaningful: Bool
    ) {
        guard activeTranslationRole == nil,
              isMeaningful,
              frame.number >= 600,
              let gameID = pendingAutomaticArtworkGameID,
              gameID == playingGameID,
              let game = games.first(where: { $0.id == gameID }) else { return }
        pendingAutomaticArtworkGameID = nil
        do {
            try saveGameArtwork(frame, for: game, source: .automatic)
            presentedNotice = "Captured private library artwork for \(game.title). Replace it any time from Player Actions."
        } catch {
            appDiagnostic("automatic library artwork failed: \(error.localizedDescription)")
        }
    }

    private func saveGameArtwork(
        _ frame: EngineVideoFrame,
        for game: GameRecord,
        source: GameArtworkSource
    ) throws {
        let png = try ScreenshotExporter.gameRasterPNGData(for: frame)
        let record = try artworkStore.save(
            png,
            gameID: game.id,
            romChecksum: game.metadata.computedChecksum,
            romFileSize: game.metadata.fileSize,
            frameNumber: frame.number,
            isVertical: frame.isVertical,
            source: source
        )
        gameArtwork[game.id] = record
    }

    func startTranslationRouteRecording() {
        guard
            activeTranslationRole == .original,
            playerIsInteractive,
            !translationReplayIsActive,
            !translationComparisonIsActive,
            !translationRouteRecordingIsPreparing
        else {
            presentedError = "Route tests must be recorded from Original with the live engine ready."
            return
        }

        translationRouteRecordingIsPreparing = true
        isPaused = true
        audioOutput.setPaused(true)
        keyboardInput = []
        controllerInput = []
        playTranslationROM(.original, recordingFromCleanBoot: true)
        if !translationRouteIsRecording {
            translationRouteRecordingIsPreparing = false
            if isPlaying {
                isPaused = false
                audioOutput.setPaused(false)
            }
        }
    }

    @discardableResult
    func finishTranslationRouteRecording(showNotice: Bool = true) -> Bool {
        guard let recorder = translationRouteRecorder, let project = translationProject else {
            translationRouteRecorder = nil
            translationRouteIsRecording = false
            translationRouteRecordingIsPreparing = false
            return false
        }
        do {
            let route = try recorder.finish()
            let url = try translationEvidenceStore.saveRoute(route, project: project)
            translationRouteRecorder = nil
            translationRouteIsRecording = false
            translationRouteRecordingIsPreparing = false
            latestTranslationRoute = route
            latestTranslationRouteURL = url
            translationEvidenceRoute = route
            translationEvidenceRouteFrameNumber = currentFrame?.number
            isPaused = true
            audioOutput.setPaused(true)
            refreshTranslationHistory()
            if let automatedTranslationTestCaseName,
               !automatedTranslationTestCaseName.isEmpty {
                translationTestCaseName = automatedTranslationTestCaseName
                translationTestCaseNote = automatedTranslationTestCaseNote
                saveSelectedTranslationTestCase()
            } else {
                translationTestCaseName = "Frame \(route.targetFrameNumber ?? route.totalFrames) checkpoint"
                translationTestCaseNote = ""
                translationTestCaseNamingRequestID &+= 1
            }
            if automatedTranslationComparisonAfterRecording {
                automatedTranslationComparisonAfterRecording = false
                Task { [weak self] in
                    await Task.yield()
                    guard let self else { return }
                    self.stopPlaying()
                    for _ in 0..<600 {
                        if !self.isPlaying, !self.translationToolIsRunning {
                            appDiagnostic(
                                "automated translation comparison starting after recording"
                            )
                            self.verifyLatestTranslationRoute()
                            return
                        }
                        do {
                            try await Task.sleep(for: .milliseconds(100))
                        } catch {
                            return
                        }
                    }
                    appDiagnostic(
                        "automated translation comparison timed out waiting for project status"
                    )
                }
            }
            if showNotice {
                presentedNotice = "Saved a clean-boot checkpoint at frame \(route.targetFrameNumber ?? route.totalFrames). Name it now, then verify it against both ROMs."
            }
            return true
        } catch TranslationLabError.noRecordedFrames {
            if showNotice {
                presentedError = "No frames were recorded. Start the game before recording a route."
            }
            return false
        } catch {
            isPaused = true
            audioOutput.setPaused(true)
            presentedError = "The input route could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    func cancelTranslationRouteRecording(showNotice: Bool = true) {
        let hadDraft = translationRouteIsRecording || translationRouteRecordingIsPreparing
        translationRouteRecorder = nil
        translationRouteIsRecording = false
        translationRouteRecordingIsPreparing = false
        if hadDraft, showNotice {
            presentedNotice = "Discarded the unfinished route draft. No test case was saved."
        }
    }

    func replayLatestTranslationRoute() {
        guard
            playerIsInteractive,
            let route = latestTranslationRoute,
            let role = activeTranslationRole,
            !translationRouteIsRecording
        else { return }
        beginTranslationRouteReplay(role: role, route: route)
    }

    private func beginTranslationRouteReplay(
        role: TranslationROMRole,
        route: TranslationRoute
    ) {
        guard preflightTranslationROM(role) else { return }
        do {
            try validateTranslationRouteForCurrentProject(route)
            playTranslationROM(role)
            guard activeTranslationRole == role else { return }
            keyboardInput = []
            controllerInput = []
            translationReplayRoute = route
            translationReplayFrameIndex = 0
            translationReplayProgress = 0
            translationEvidenceRoute = nil
            translationEvidenceRouteFrameNumber = nil
            presentedNotice = nil
        } catch {
            presentedError = "The recorded route could not start: \(error.localizedDescription)"
        }
    }

    private func translationGame(
        at url: URL,
        project: TranslationProject
    ) throws -> GameRecord {
        // Translation projects link their ROM in place, but they must pass the
        // same structural and extension-aware inspection as library imports.
        // In particular, `.pc2`/`.pcv2` is what selects Benesse hardware;
        // its footer alone is intentionally indistinguishable from mono WS.
        guard url.pathExtension.lowercased() != "zip" else {
            throw TranslationLabError.invalidProject(
                "translation ROMs must be direct .ws, .wsc, .pc2, or .pcv2 files"
            )
        }
        let image = try LibraryGameImageImporter.image(from: url)
        let declaredHardware = try project.routeHardwareModel
        let inspectedHardware = try TranslationRouteHardwareModel(
            engineHardwareModel: image.hardwareModel
        )
        let hardwareMatches = declaredHardware == inspectedHardware
            || (declaredHardware == .swanCrystal
                && inspectedHardware == .wonderSwanColor)
        guard hardwareMatches else {
            throw TranslationLabError.invalidProject(
                "project platform \(project.platform) does not match \(url.lastPathComponent)"
            )
        }
        return GameRecord(
            title: project.title,
            fileURL: url.standardizedFileURL,
            metadata: image.metadata,
            managedROM: nil,
            sourceFileName: image.sourceFileName,
            preferredHardwareModel: declaredHardware.engineHardwareModel
        )
    }

    private func preflightTranslationROM(_ role: TranslationROMRole) -> Bool {
        guard let project = translationProject else { return false }
        do {
            let url = try project.romURL(for: role)
            _ = try translationGame(at: url, project: project)
            return true
        } catch {
            presentedError = "The \(role.title.lowercased()) test ROM could not be inspected: \(error.localizedDescription)"
            return false
        }
    }

    private func armTranslationRouteRecordingFromCleanBoot() throws {
        guard
            activeTranslationRole == .original,
            let romURL = activeTranslationROMURL,
            let game = playingGame
        else {
            throw TranslationLabError.invalidRoute(
                "a clean-boot route can only be recorded from the project’s Original ROM"
            )
        }
        let binding = try translationRouteBinding(for: game, romURL: romURL)
        translationRouteRecorder = TranslationRouteRecorder(
            role: .original,
            sourceROM: binding.sourceROM,
            start: binding.start
        )
        translationRouteIsRecording = true
        translationRouteRecordingIsPreparing = false
        translationReplayProgress = nil
        translationEvidenceRoute = nil
        translationEvidenceRouteFrameNumber = nil
        presentedNotice = nil
    }

    private func translationRouteBinding(
        for game: GameRecord,
        romURL: URL
    ) throws -> (sourceROM: TranslationArtifactDigest, start: TranslationRouteStartContext) {
        let rom = try Data(contentsOf: romURL, options: [.mappedIfSafe])
        let sourceROM = TranslationArtifactDigest(
            byteCount: rom.count,
            sha256: TranslationEvidenceStore.sha256(rom)
        )
        let hardwareModel = try TranslationRouteHardwareModel(
            engineHardwareModel: game.resolvedHardwareModel
        )
        if let project = translationProject {
            let declaredHardware = try project.routeHardwareModel
            guard declaredHardware == hardwareModel else {
                throw TranslationLabError.invalidProject(
                    "project platform \(project.platform) does not match the selected game hardware"
                )
            }
        }
        let firmware = TranslationRouteFirmware(
            source: .openIPL,
            identifier: WonderSwanOpenIPL.identifier
        )
        return (
            sourceROM,
            TranslationRouteStartContext(
                hardwareModel: hardwareModel,
                firmware: firmware,
                engine: TranslationRouteEngineIdentity(
                    backend: engineBackendName,
                    buildID: engineBuildID
                ),
                rtc: .proof
            )
        )
    }

    private func validateTranslationRouteForCurrentProject(
        _ route: TranslationRoute
    ) throws {
        try route.validateForProof()
        guard let project = translationProject else {
            throw TranslationLabError.invalidProject("no translation project is selected")
        }
        let originalURL = try project.romURL(for: .original)
        let original = try translationGame(at: originalURL, project: project)
        let current = try translationRouteBinding(for: original, romURL: originalURL)
        guard route.sourceROM == current.sourceROM else {
            throw TranslationLabError.invalidRoute(
                "the Original ROM changed after this route was recorded; re-record the test"
            )
        }
        guard let recordedStart = route.start else {
            throw TranslationLabError.invalidRoute("the route start context is missing")
        }
        guard recordedStart.hardwareModel == current.start.hardwareModel else {
            throw TranslationLabError.invalidRoute(
                "the recorded hardware model changed; re-record the test"
            )
        }
        guard recordedStart.firmware.isRuntimeEquivalent(
            to: current.start.firmware
        ) else {
            throw TranslationLabError.invalidRoute(
                "the Open IPL version changed after this route was recorded; re-record the test"
            )
        }
        guard recordedStart.engine == current.start.engine else {
            throw TranslationLabError.invalidRoute(
                "the emulator engine changed after this route was recorded; re-record the test"
            )
        }
        guard recordedStart.rtc == current.start.rtc else {
            throw TranslationLabError.invalidRoute(
                "the deterministic RTC policy changed; re-record the test with fixed UTC \(TranslationRouteRTCContext.proofSeedUTC)"
            )
        }
        guard recordedStart.persistencePolicy == current.start.persistencePolicy,
              recordedStart.kind == current.start.kind else {
            throw TranslationLabError.invalidRoute(
                "the clean-boot test policy changed; re-record the test"
            )
        }
    }

    private func validateTranslationReplayTarget(
        _ role: TranslationROMRole,
        route: TranslationRoute
    ) throws {
        try validateTranslationRouteForCurrentProject(route)
        guard role == .patched else { return }
        guard let project = translationProject else {
            throw TranslationLabError.invalidProject("no translation project is selected")
        }
        guard let recordedStart = route.start else {
            throw TranslationLabError.invalidRoute("the route start context is missing")
        }

        let patchedURL = try project.romURL(for: .patched)
        let patched = try translationGame(at: patchedURL, project: project)
        let patchedBinding = try translationRouteBinding(for: patched, romURL: patchedURL)
        guard patchedBinding.start.hardwareModel == recordedStart.hardwareModel else {
            throw TranslationLabError.invalidRoute(
                "the Patched ROM targets different hardware than the recorded route"
            )
        }
        guard patchedBinding.start.firmware.isRuntimeEquivalent(
            to: recordedStart.firmware
        ) else {
            throw TranslationLabError.invalidRoute(
                "the Patched ROM uses a different startup implementation than the recorded route"
            )
        }
        guard patchedBinding.start.rtc == recordedStart.rtc else {
            throw TranslationLabError.invalidRoute(
                "the Patched replay RTC policy differs from the recorded route"
            )
        }
        // Patched output is expected to contain different ROM bytes. Its digest
        // is deliberately not compared with the Original-bound route digest.
    }

    func captureTranslationEvidence() {
        guard
            playerIsInteractive,
            !isCapturingTranslationEvidence,
            let project = translationProject,
            let role = activeTranslationRole,
            let romURL = activeTranslationROMURL,
            let game = playingGame,
            let frame = currentFrame,
            let runner = activeRunner
        else { return }

        do {
            let framePNG = try ScreenshotExporter.pngData(for: frame)
            let gameFrameSHA256 = try TranslationRouteCheckpoint.fingerprint(frame)
            let route = translationEvidenceRouteFrameNumber == frame.number
                ? translationEvidenceRoute
                : nil
            let wasPaused = isPaused
            isPaused = true
            audioOutput.setPaused(true)
            isCapturingTranslationEvidence = true
            let comparisonRole = translationComparisonPhase == .capturing(role)
                ? role
                : nil
            let sessionGeneration = emulationGeneration

            Task { [weak self] in
                guard let self else { return }
                var comparisonCanAdvance = false
                do {
                    let state = try await runner.captureState()
                    let ram = try await runner.captureMemory(.internalRAM)
                    guard self.isCurrentPlayerSession(
                        generation: sessionGeneration,
                        gameID: game.id
                    ), self.activeTranslationRole == role,
                       self.playerFailure == nil else { return }
                    let artifact = try self.translationEvidenceStore.capture(
                        TranslationEvidenceInput(
                            project: project,
                            role: role,
                            romURL: romURL,
                            romFooterChecksum: game.metadata.computedChecksum,
                            backend: self.engineBackendName,
                            frameNumber: frame.number,
                            framePNG: framePNG,
                            gameFrameSHA256: gameFrameSHA256,
                            state: state,
                            internalRAM: ram,
                            route: route
                        )
                    )
                    self.lastTranslationEvidenceURL = artifact.directoryURL
                    self.selectedTranslationEvidenceID = artifact.directoryURL.path
                    self.refreshTranslationHistory()
                    self.translationToolPhase = "Registering capture with the toolkit…"
                    let intake = try await Task.detached(priority: .userInitiated) {
                        try TranslationToolkitRunner.run(
                            .captureIntake(
                                ramURL: artifact.internalRAMURL,
                                name: artifact.name
                            ),
                            project: project
                        )
                    }.value
                    guard self.isCurrentPlayerSession(
                        generation: sessionGeneration,
                        gameID: game.id
                    ), self.activeTranslationRole == role,
                       self.playerFailure == nil else { return }
                    self.translationCommandOutput = self.formattedTranslationOutput([intake])
                    if intake.succeeded {
                        if comparisonRole == nil {
                            let provenance = route == nil
                                ? "without a bound input route"
                                : "with the exact recorded route"
                            self.presentedNotice = "Captured a native frame, \(ram.count / 1024) KiB RAM dump, and save state \(provenance). The toolkit intake is ready for text-screen analysis."
                        }
                        comparisonCanAdvance = comparisonRole != nil
                    } else {
                        self.presentedError = "The evidence was saved, but toolkit intake failed. Review the Translation Lab output before using this capture."
                        self.cancelTranslationComparison()
                    }
                } catch {
                    guard self.isCurrentPlayerSession(
                        generation: sessionGeneration,
                        gameID: game.id
                    ), self.activeTranslationRole == role,
                       self.playerFailure == nil else { return }
                    self.presentedError = "Translation evidence could not be captured: \(error.localizedDescription)"
                    self.cancelTranslationComparison()
                }
                guard self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: game.id
                ), self.activeTranslationRole == role,
                   self.playerFailure == nil else { return }
                self.translationToolPhase = nil
                self.isCapturingTranslationEvidence = false
                if !wasPaused && self.translationReplayRoute != nil {
                    self.isPaused = false
                    self.audioOutput.setPaused(false)
                } else if !wasPaused && self.translationReplayRoute == nil {
                    self.isPaused = false
                    self.audioOutput.setPaused(false)
                }
                if comparisonCanAdvance, let comparisonRole {
                    self.advanceTranslationComparison(after: comparisonRole)
                }
            }
        } catch {
            presentedError = "Translation evidence could not be prepared: \(error.localizedDescription)"
            cancelTranslationComparison()
        }
    }

    func importPocketSave() {
        guard !hasEmulationSessionPendingFinalization,
              !terminationIsInProgress else {
            presentedError = "Wait for the previous game to finish saving and closing before replacing a cartridge save."
            return
        }
        guard !isPlaying else {
            presentedError = "Return to the library before replacing a cartridge save."
            return
        }
        guard let game = selectedGame, hasCartridgeSave(game) else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Pocket Save for \(game.title)"
        panel.prompt = "Import Save"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let saveType = UTType(filenameExtension: "sav", conformingTo: .data) {
            panel.allowedContentTypes = [saveType]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let codec = try PocketSaveCodec(metadata: game.metadata)
            let imported = try codec.importSave(Data(contentsOf: url))
            try saveStore.replaceCartridgeSave(imported.persistence, gameID: game.id)
            presentedNotice = "Imported for \(game.title). \(imported.report.summary)"
        } catch {
            presentedError = "The Pocket save could not be imported: \(error.localizedDescription)"
        }
    }

    func exportPocketSave() {
        guard retiringEmulationSession == nil,
              !isFinalizingFailedSession,
              !terminationIsInProgress else {
            presentedError = "Wait for the current game to finish saving and closing before exporting its cartridge save."
            return
        }
        guard let game = playingGame ?? selectedGame, hasCartridgeSave(game) else { return }
        let panel = NSSavePanel()
        panel.title = "Export Pocket Save for \(game.title)"
        panel.prompt = "Export Save"
        panel.canCreateDirectories = true
        if let saveType = UTType(filenameExtension: "sav", conformingTo: .data) {
            panel.allowedContentTypes = [saveType]
        }
        panel.nameFieldStringValue = "\(game.title).sav"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let runner = game.id == playingGameID ? activeRunner : nil
        let saveStore = saveStore
        Task { [weak self] in
            guard let self else { return }
            do {
                let persistence: EnginePersistence
                var recoveredPreviousGeneration = false
                if let runner {
                    persistence = try await runner.capturePersistence()
                    try await Task.detached(priority: .userInitiated) {
                        try saveStore.save(persistence, gameID: game.id)
                    }.value
                } else {
                    let loaded = try await Task.detached(priority: .userInitiated) {
                        try saveStore.loadWithStatus(gameID: game.id)
                    }.value
                    persistence = loaded.persistence
                    recoveredPreviousGeneration = loaded.recoveredPreviousGeneration
                }
                let exported = try PocketSaveCodec(metadata: game.metadata)
                    .export(persistence)
                try exported.data.write(to: url, options: [.atomic])
                let recoveryNote = recoveredPreviousGeneration
                    ? " SwanSong recovered the previous complete save generation first."
                    : ""
                self.presentedNotice = "Exported for \(game.title). \(exported.report.summary)\(recoveryNote)"
            } catch {
                self.presentedError = "The Pocket save could not be exported: \(error.localizedDescription)"
            }
        }
    }

    func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    func fitWindowToGame() {
        guard isPlaying else { return }
        fitWindowRequestID &+= 1
    }

    func saveQuickState() {
        guard activeTranslationRole == nil else {
            presentedError = "Translation tests use project-local evidence instead of library quick states."
            return
        }
        guard requireCaptureAlignedPlayerFrame(for: "saving another state") else { return }
        guard
            playerIsInteractive,
            let game = playingGame,
            let runner = activeRunner,
            let stateSessionIdentity = activeGameStateSessionIdentity,
            playerStateOperation == nil,
            !isRewindPresented
        else { return }
        clearStateLoadUndo()
        let sessionGeneration = emulationGeneration
        let wasPaused = isPaused
        let operationGeneration = beginPlayerStateOperation(
            .saving,
            resumesPlayback: !wasPaused
        )
        isPaused = true
        audioOutput.setPaused(true)
        let stateStore = stateStore
        let transactionID = beginTrackedPlayerStateTransaction()
        let transactionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishTrackedPlayerStateTransaction(transactionID) }
            do {
                await self.waitForPlayerFrameProductionToQuiesce()
                let state = try await runner.captureState()
                guard self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: game.id
                ) else { return }
                guard let frame = self.currentFrame else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let preview = try ScreenshotExporter.pngData(for: frame)
                let manifest = try stateStore.saveQuickState(
                    gameID: game.id,
                    sessionIdentity: stateSessionIdentity,
                    frameNumber: frame.number,
                    state: state,
                    previewPNG: preview
                )
                self.quickStateSavedAt = manifest.createdAt
                self.refreshTimeline()
            } catch {
                if self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: game.id
                ) {
                    self.presentedError = "The quick state could not be saved: \(error.localizedDescription)"
                }
            }
            guard self.finishPlayerStateOperation(operationGeneration),
                  self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: game.id
                  ) else { return }
            if !wasPaused, !self.inactivityPauseWasApplied {
                self.isPaused = false
                self.audioOutput.setPaused(false)
            }
        }
        trackPlayerStateTransaction(transactionTask, id: transactionID)
    }

    func loadQuickState() {
        guard requireCaptureAlignedPlayerFrame(for: "loading another state") else { return }
        guard
            playerIsInteractive,
            let game = playingGame,
            let runner = activeRunner,
            let stateSessionIdentity = activeGameStateSessionIdentity,
            playerStateOperation == nil,
            !isRewindPresented
        else { return }
        clearStateLoadUndo()
        let sessionGeneration = emulationGeneration
        let wasPaused = isPaused
        let operationGeneration = beginPlayerStateOperation(
            .loading,
            resumesPlayback: !wasPaused
        )
        isPaused = true
        audioOutput.setPaused(true)
        let stateStore = stateStore
        let undoManager = NSApp.keyWindow?.undoManager ?? NSApp.mainWindow?.undoManager
        let transactionID = beginTrackedPlayerStateTransaction()
        let transactionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishTrackedPlayerStateTransaction(transactionID) }
            var rollback: StateLoadRollbackPoint?
            var rollbackAudioIssue: String?
            do {
                guard let saved = try stateStore.loadQuickState(
                    gameID: game.id,
                    sessionIdentity: stateSessionIdentity
                ) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                guard saved.compatibility.isReady else { throw saved.compatibility }
                let displayFrame = try self.displayFrame(for: saved)
                await self.waitForPlayerFrameProductionToQuiesce()
                do {
                    rollback = try await self.makeStateLoadRollbackPoint(
                        runner: runner,
                        sessionGeneration: sessionGeneration,
                        gameID: game.id
                    )
                } catch {
                    throw PlayerStateRollbackCreationError(underlying: error)
                }
                try await runner.restoreState(saved.state)
                guard self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: game.id
                ) else { return }
                _ = try await runner.nextFrame(input: [])
                guard self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: game.id
                ) else { return }
                guard let rollback else { throw CocoaError(.fileReadUnknown) }
                self.continuePresentedFrameNumbers(
                    afterSettledStateFrame: saved.manifest.frameNumber
                )
                let audioIssue = self.registerSuccessfulStateLoad(
                    rollback: rollback,
                    savedAt: saved.manifest.createdAt,
                    frame: displayFrame,
                    undoManager: undoManager
                )
                if let audioIssue { self.presentedError = audioIssue }
                self.quickStateSavedAt = saved.manifest.createdAt
            } catch {
                if let rollback,
                   self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: game.id
                   ) {
                    do {
                        rollbackAudioIssue = try await self.restoreStateLoadRollback(
                            rollback,
                            with: runner
                        )
                    } catch let rollbackError {
                        await self.stopAfterUnrecoverableStateLoad(
                            runner: runner,
                            sessionGeneration: sessionGeneration,
                            gameID: game.id,
                            loadError: error,
                            rollbackError: rollbackError
                        )
                        return
                    }
                }
                if self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: game.id
                ) {
                    if let rollbackError = error as? PlayerStateRollbackCreationError {
                        self.presentedError = "SwanSong could not create a rollback point, so the quick state was not loaded: \(rollbackError.underlying.localizedDescription)"
                    } else if rollback != nil {
                        let audioSuffix = rollbackAudioIssue.map { " \($0)" } ?? ""
                        self.presentedError = "The quick state could not be loaded. The previous game state was restored: \(error.localizedDescription)\(audioSuffix)"
                    } else {
                        self.presentedError = "The quick state could not be loaded: \(error.localizedDescription)"
                    }
                }
            }
            guard self.finishPlayerStateOperation(operationGeneration),
                  self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: game.id
                  ) else { return }
            let shouldRemainPaused = wasPaused || self.inactivityPauseWasApplied
            self.isPaused = shouldRemainPaused
            self.audioOutput.setPaused(shouldRemainPaused)
        }
        trackPlayerStateTransaction(transactionTask, id: transactionID)
    }

    func showRewind() {
        guard canShowRewind,
              let newest = rewindCheckpoints.last else { return }
        resumeAfterRewind = !isPaused
        isPaused = true
        audioOutput.setPaused(true)
        keyboardInput = []
        controllerInput = []
        let requestedSeconds = min(5, rewindRetainedSeconds)
        selectedRewindCheckpointID = rewindBuffer.checkpoint(
            secondsBack: requestedSeconds,
            fromFrame: newest.frameNumber
        )?.id ?? newest.id
        isRewindPresented = true
    }

    func dismissRewind() {
        guard playerStateOperation == nil else { return }
        let hadPendingPresentation = isRewindPresented
            || selectedRewindCheckpointID != nil
            || resumeAfterRewind
        guard hadPendingPresentation else { return }
        isRewindPresented = false
        selectedRewindCheckpointID = nil
        let shouldResume = resumeAfterRewind && !inactivityPauseWasApplied
        resumeAfterRewind = false
        if shouldResume {
            isPaused = false
            audioOutput.setPaused(false)
        }
    }

    func selectRewindCheckpoint(_ id: RewindCheckpoint.ID) {
        guard isRewindPresented,
              rewindCheckpoints.contains(where: { $0.id == id }) else { return }
        selectedRewindCheckpointID = id
    }

    func rewindFiveSeconds() {
        guard canShowRewind,
              let newest = rewindCheckpoints.last,
              let checkpoint = rewindBuffer.checkpoint(
                secondsBack: 5,
                fromFrame: newest.frameNumber
              ) else { return }
        resumeAfterRewind = !isPaused
        isPaused = true
        audioOutput.setPaused(true)
        keyboardInput = []
        controllerInput = []
        selectedRewindCheckpointID = checkpoint.id
        isRewindPresented = true
        resumeFromSelectedRewindCheckpoint()
    }

    func resumeFromSelectedRewindCheckpoint() {
        guard canResumeSelectedRewindCheckpoint,
              let checkpoint = selectedRewindCheckpoint,
              let runner = activeRunner,
              let gameID = playingGameID else { return }
        clearStateLoadUndo()
        let sessionGeneration = emulationGeneration
        let operationGeneration = beginPlayerStateOperation(
            .rewinding,
            resumesPlayback: resumeAfterRewind
        )
        isPaused = true
        audioOutput.setPaused(true)
        keyboardInput = []
        controllerInput = []
        frameAdvanceGate.reset()
        let undoManager = NSApp.keyWindow?.undoManager ?? NSApp.mainWindow?.undoManager
        let secondsBack = rewindSecondsBack(for: checkpoint)
        let transactionID = beginTrackedPlayerStateTransaction()
        let transactionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishTrackedPlayerStateTransaction(transactionID) }
            var rollback: StateLoadRollbackPoint?
            var rollbackAudioIssue: String?
            var didRewind = false
            do {
                await self.waitForPlayerFrameProductionToQuiesce()
                do {
                    rollback = try await self.makeStateLoadRollbackPoint(
                        runner: runner,
                        sessionGeneration: sessionGeneration,
                        gameID: gameID
                    )
                } catch {
                    throw PlayerStateRollbackCreationError(underlying: error)
                }
                try await runner.restoreState(checkpoint.state)
                guard self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: gameID
                ) else { return }
                // ares omits frontend raster/audio history from serialization.
                // Consume its one unsettled frame while the exact checkpoint
                // preview remains visible, matching normal state restoration.
                _ = try await runner.nextFrame(input: [])
                guard self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: gameID
                ), let rollback else { return }
                self.continuePresentedFrameNumbers(
                    afterSettledStateFrame: checkpoint.frameNumber
                )
                self.currentFrame = checkpoint.previewFrame
                self.playerStateNeedsNaturalFrame = true
                self.resetPlayerVideoActivity()
                if self.activeTranslationRole == nil {
                    _ = self.observePlayerVideoActivity(checkpoint.previewFrame)
                }
                self.stateLoadUndoPoint = rollback
                self.stateLoadUndoMessage = String(
                    format: "Rewound %.1f seconds. Undo is available.",
                    secondsBack
                )
                self.registerStateLoadUndoAction(
                    using: undoManager,
                    actionName: "Rewind"
                )
                _ = self.rewindBuffer.truncate(
                    afterFrame: checkpoint.frameNumber
                )
                self.rewindCheckpoints = self.rewindBuffer.checkpoints
                let audioIssue = self.restartAudioAfterStateChange(paused: true)
                if let audioIssue { self.presentedError = audioIssue }
                didRewind = true
                #if SWAN_SONG_AUTOMATION
                self.automatedRewindHasCompleted = true
                #endif
            } catch {
                if let rollback,
                   self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: gameID
                   ) {
                    do {
                        rollbackAudioIssue = try await self.restoreStateLoadRollback(
                            rollback,
                            with: runner
                        )
                    } catch let rollbackError {
                        await self.stopAfterUnrecoverableStateLoad(
                            runner: runner,
                            sessionGeneration: sessionGeneration,
                            gameID: gameID,
                            loadError: error,
                            rollbackError: rollbackError
                        )
                        return
                    }
                }
                if self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: gameID
                ) {
                    if let rollbackError = error as? PlayerStateRollbackCreationError {
                        self.presentedError = "SwanSong could not create a safety point, so rewind was not attempted: \(rollbackError.underlying.localizedDescription)"
                    } else if rollback != nil {
                        let audioSuffix = rollbackAudioIssue.map { " \($0)" } ?? ""
                        self.presentedError = "Rewind could not be completed. The previous game state was restored: \(error.localizedDescription)\(audioSuffix)"
                    } else {
                        self.presentedError = "Rewind could not be completed: \(error.localizedDescription)"
                    }
                }
            }
            guard self.finishPlayerStateOperation(operationGeneration),
                  self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: gameID
                  ) else { return }
            guard didRewind else { return }
            self.isRewindPresented = false
            self.selectedRewindCheckpointID = nil
            let shouldResume = self.resumeAfterRewind
                && !self.inactivityPauseWasApplied
            self.resumeAfterRewind = false
            self.isPaused = !shouldResume
            self.audioOutput.setPaused(!shouldResume)
            let diagnosticSeconds = String(format: "%.2f", secondsBack)
            appDiagnostic(
                "rewind restored frame=\(checkpoint.frameNumber) seconds=\(diagnosticSeconds) paused=\(self.isPaused) operation_idle=\(self.playerStateOperation == nil) history_count=\(self.rewindCheckpoints.count)"
            )
        }
        trackPlayerStateTransaction(transactionTask, id: transactionID)
    }

    func showStateTimeline() {
        guard requireCaptureAlignedPlayerFrame(for: "opening the save-state timeline") else { return }
        guard playerIsInteractive,
              activeTranslationRole == nil,
              playerStateOperation == nil,
              !isRewindPresented else { return }
        refreshTimeline()
        resumeAfterTimeline = !isPaused
        if resumeAfterTimeline {
            isPaused = true
            audioOutput.setPaused(true)
        }
        isStateTimelinePresented = true
    }

    func dismissStateTimeline() {
        guard playerStateOperation == nil else { return }
        isStateTimelinePresented = false
        if resumeAfterTimeline {
            isPaused = false
            audioOutput.setPaused(false)
        }
        resumeAfterTimeline = false
    }

    func loadTimelineState(_ generation: UUID) {
        guard requireCaptureAlignedPlayerFrame(for: "loading another state") else { return }
        guard let game = playingGame,
              let runner = activeRunner,
              let stateSessionIdentity = activeGameStateSessionIdentity,
              playerStateOperation == nil else { return }
        clearStateLoadUndo()
        let sessionGeneration = emulationGeneration
        let operationGeneration = beginPlayerStateOperation(
            .loading,
            resumesPlayback: false
        )
        let stateStore = stateStore
        let undoManager = NSApp.keyWindow?.undoManager ?? NSApp.mainWindow?.undoManager
        let transactionID = beginTrackedPlayerStateTransaction()
        let transactionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishTrackedPlayerStateTransaction(transactionID) }
            var rollback: StateLoadRollbackPoint?
            var rollbackAudioIssue: String?
            var didLoad = false
            do {
                let saved = try stateStore.loadState(
                    gameID: game.id,
                    generation: generation,
                    sessionIdentity: stateSessionIdentity
                )
                guard saved.compatibility.isReady else { throw saved.compatibility }
                let displayFrame = try self.displayFrame(for: saved)
                await self.waitForPlayerFrameProductionToQuiesce()
                do {
                    rollback = try await self.makeStateLoadRollbackPoint(
                        runner: runner,
                        sessionGeneration: sessionGeneration,
                        gameID: game.id
                    )
                } catch {
                    throw PlayerStateRollbackCreationError(underlying: error)
                }
                try await runner.restoreState(saved.state)
                guard self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: game.id
                ) else { return }
                _ = try await runner.nextFrame(input: [])
                guard self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: game.id
                ) else { return }
                guard let rollback else { throw CocoaError(.fileReadUnknown) }
                self.continuePresentedFrameNumbers(
                    afterSettledStateFrame: saved.manifest.frameNumber
                )
                let audioIssue = self.registerSuccessfulStateLoad(
                    rollback: rollback,
                    savedAt: saved.manifest.createdAt,
                    frame: displayFrame,
                    undoManager: undoManager
                )
                if let audioIssue { self.presentedError = audioIssue }
                didLoad = true
            } catch {
                if let rollback,
                   self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: game.id
                   ) {
                    do {
                        rollbackAudioIssue = try await self.restoreStateLoadRollback(
                            rollback,
                            with: runner
                        )
                    } catch let rollbackError {
                        await self.stopAfterUnrecoverableStateLoad(
                            runner: runner,
                            sessionGeneration: sessionGeneration,
                            gameID: game.id,
                            loadError: error,
                            rollbackError: rollbackError
                        )
                        return
                    }
                }
                if self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: game.id
                ) {
                    if let rollbackError = error as? PlayerStateRollbackCreationError {
                        self.presentedError = "SwanSong could not create a rollback point, so that saved moment was not loaded: \(rollbackError.underlying.localizedDescription)"
                    } else if rollback != nil {
                        let audioSuffix = rollbackAudioIssue.map { " \($0)" } ?? ""
                        self.presentedError = "That saved moment could not be loaded. The previous game state was restored: \(error.localizedDescription)\(audioSuffix)"
                    } else {
                        self.presentedError = "That saved moment could not be loaded: \(error.localizedDescription)"
                    }
                }
            }
            guard self.finishPlayerStateOperation(operationGeneration),
                  self.isCurrentPlayerSession(
                    generation: sessionGeneration,
                    gameID: game.id
                  ) else { return }
            if didLoad {
                let shouldResume = self.resumeAfterTimeline
                    && !self.inactivityPauseWasApplied
                self.isStateTimelinePresented = false
                self.resumeAfterTimeline = false
                self.isPaused = !shouldResume
                self.audioOutput.setPaused(!shouldResume)
            }
        }
        trackPlayerStateTransaction(transactionTask, id: transactionID)
    }

    func dismissStateLoadUndoNotice() {
        stateLoadUndoMessage = nil
    }

    func undoLastStateLoad() {
        let undoManager = stateLoadUndoManager
        let isRewindUndo = stateLoadUndoActionName == "Rewind"
        guard requireCaptureAlignedPlayerFrame(for: "undoing this state load") else {
            registerStateLoadUndoAction(using: undoManager)
            return
        }
        guard canUndoStateLoad,
              let undoPoint = stateLoadUndoPoint,
              let runner = activeRunner else {
            if stateLoadUndoPoint != nil {
                registerStateLoadUndoAction(using: undoManager)
            }
            return
        }
        let wasPausedBeforeUndo = isPaused
        let operationGeneration = beginPlayerStateOperation(
            .undoingLoad,
            resumesPlayback: !wasPausedBeforeUndo
        )
        isPaused = true
        audioOutput.setPaused(true)
        keyboardInput = []
        controllerInput = []
        let transactionID = beginTrackedPlayerStateTransaction()
        let transactionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishTrackedPlayerStateTransaction(transactionID) }
            let currentPoint: StateLoadRollbackPoint
            do {
                await self.waitForPlayerFrameProductionToQuiesce()
                currentPoint = try await self.makeStateLoadRollbackPoint(
                    runner: runner,
                    sessionGeneration: undoPoint.sessionGeneration,
                    gameID: undoPoint.gameID
                )
            } catch {
                guard self.finishPlayerStateOperation(operationGeneration),
                      self.isCurrentPlayerSession(
                        generation: undoPoint.sessionGeneration,
                        gameID: undoPoint.gameID
                      ) else { return }
                self.registerStateLoadUndoAction(using: undoManager)
                let shouldRemainPaused = wasPausedBeforeUndo
                    || self.inactivityPauseWasApplied
                self.isPaused = shouldRemainPaused
                self.audioOutput.setPaused(shouldRemainPaused)
                self.presentedError = "SwanSong could not create a safety point, so Undo Load State was not attempted: \(error.localizedDescription)"
                return
            }

            let undoAudioIssue: String?
            do {
                undoAudioIssue = try await self.restoreStateLoadRollback(
                    undoPoint,
                    with: runner
                )
            } catch let undoError {
                guard self.isCurrentPlayerSession(
                    generation: undoPoint.sessionGeneration,
                    gameID: undoPoint.gameID
                ) else { return }
                let recoveryAudioIssue: String?
                do {
                    recoveryAudioIssue = try await self.restoreStateLoadRollback(
                        currentPoint,
                        with: runner
                    )
                } catch let rollbackError {
                    await self.stopAfterUnrecoverableStateLoad(
                        runner: runner,
                        sessionGeneration: undoPoint.sessionGeneration,
                        gameID: undoPoint.gameID,
                        loadError: undoError,
                        rollbackError: rollbackError
                    )
                    return
                }
                guard self.finishPlayerStateOperation(operationGeneration),
                      self.isCurrentPlayerSession(
                        generation: undoPoint.sessionGeneration,
                        gameID: undoPoint.gameID
                      ) else { return }
                self.registerStateLoadUndoAction(using: undoManager)
                let shouldRemainPaused = wasPausedBeforeUndo
                    || self.inactivityPauseWasApplied
                self.isPaused = shouldRemainPaused
                self.audioOutput.setPaused(shouldRemainPaused)
                let audioSuffix = recoveryAudioIssue.map { " \($0)" } ?? ""
                self.presentedError = "Undo Load State failed, so SwanSong restored the state from before the Undo attempt: \(undoError.localizedDescription)\(audioSuffix)"
                return
            }

            guard self.finishPlayerStateOperation(operationGeneration),
                  self.isCurrentPlayerSession(
                    generation: undoPoint.sessionGeneration,
                    gameID: undoPoint.gameID
                  ) else { return }
            self.resetRewindHistory()
            self.clearStateLoadUndo()
            let shouldRemainPaused = wasPausedBeforeUndo
                || self.inactivityPauseWasApplied
            self.isPaused = shouldRemainPaused
            self.audioOutput.setPaused(shouldRemainPaused)
            self.presentedNotice = "Loaded state undone. Your previous game moment is restored."
            if let undoAudioIssue { self.presentedError = undoAudioIssue }
            #if SWAN_SONG_AUTOMATION
            if isRewindUndo {
                self.captureAutomatedRewindUndoRestorationIfRequested(
                    undoPoint.frame
                )
            }
            #endif
        }
        trackPlayerStateTransaction(transactionTask, id: transactionID)
    }

    func deleteTimelineState(_ generation: UUID) {
        guard let game = playingGame, playerStateOperation == nil else { return }
        do {
            try stateStore.deleteState(gameID: game.id, generation: generation)
            refreshTimeline()
            if let stateSessionIdentity = activeGameStateSessionIdentity {
                let quickState = try stateStore.loadQuickState(
                    gameID: game.id,
                    sessionIdentity: stateSessionIdentity
                )
                quickStateSavedAt = quickState?.compatibility.isReady == true
                    && quickState?.previewIssue == nil
                    ? quickState?.manifest.createdAt
                    : nil
            } else {
                quickStateSavedAt = nil
            }
        } catch {
            presentedError = "That timeline state could not be deleted: \(error.localizedDescription)"
        }
    }

    private func refreshTimeline() {
        guard let game = playingGame,
              let stateSessionIdentity = activeGameStateSessionIdentity else {
            timelineStates = []
            return
        }
        do {
            timelineStates = try stateStore.listStates(
                gameID: game.id,
                sessionIdentity: stateSessionIdentity
            )
        } catch {
            timelineStates = []
            presentedError = "The save-state timeline could not be read: \(error.localizedDescription)"
        }
    }

    private func loadTranslationWorkspace() {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["SWAN_SONG_TRANSLATION_PROJECT"], !path.isEmpty {
            do {
                translationProjects = try TranslationProject.discover(
                    at: URL(fileURLWithPath: path)
                )
                translationProject = translationProjects.first
                section = .translationLab
                refreshTranslationHistory()
            } catch {
                presentedError = "The configured translation workspace could not be opened: \(error.localizedDescription)"
            }
            return
        }

        var document = (try? translationWorkspaceStore.load()) ?? TranslationWorkspaceDocument()
        translationProjects = document.projectPaths.compactMap { path in
            try? TranslationProject(projectDirectory: URL(fileURLWithPath: path, isDirectory: true))
        }
        var seen = Set<String>()
        translationProjects = translationProjects.filter { seen.insert($0.id).inserted }
        translationProjects.sort {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }

        if translationProjects.isEmpty,
           let legacyPath = UserDefaults.standard.string(forKey: translationProjectDefaultsKey),
           let legacy = try? TranslationProject(
               projectDirectory: URL(fileURLWithPath: legacyPath, isDirectory: true)
           ) {
            translationProjects = [legacy]
            document.selectedProjectPath = legacy.rootURL.path
            UserDefaults.standard.removeObject(forKey: translationProjectDefaultsKey)
        }
        translationProject = translationProjects.first(where: {
            $0.rootURL.path == document.selectedProjectPath
        }) ?? translationProjects.first
        refreshTranslationHistory()
        persistTranslationWorkspace()
    }

    private func persistTranslationWorkspace() {
        guard !translationWorkspaceIsEnvironmentConfigured else { return }
        let document = TranslationWorkspaceDocument(
            projectPaths: translationProjects.map { $0.rootURL.path },
            selectedProjectPath: translationProject?.rootURL.path
        )
        do {
            try translationWorkspaceStore.save(document)
        } catch {
            presentedError = "Translation Lab could not save its workspace: \(error.localizedDescription)"
        }
    }

    private func resetTranslationProjectState() {
        resetTranslationTextIntake()
        translationVisualDivergenceGeneration = UUID()
        translationVisualDivergenceTask?.cancel()
        translationVisualDivergenceTask = nil
        translationVisualDivergenceRoute = nil
        translationVisualDivergenceResult = nil
        translationVisualDivergenceProgress = nil
        translationVisualDivergenceIssue = nil
        translationVisualDivergenceIsRunning = false
        isTranslationVisualDivergencePresented = false
        translationReadiness = nil
        translationCommandOutput = ""
        latestTranslationRoute = nil
        latestTranslationRouteURL = nil
        translationRoutes = []
        translationTestCaseName = ""
        translationTestCaseNote = ""
        lastTranslationEvidenceURL = nil
        translationEvidence = []
        selectedTranslationEvidenceID = nil
        translationEvidenceReviewStatus = .unreviewed
        translationEvidenceReviewNote = ""
        translationEvidenceFrameComparison = nil
        translationEvidenceFrameComparisonIssue = nil
        translationPrivateArtifacts = []
        selectedTranslationPrivateArtifactID = nil
        translationPrivateStorageStatus = nil
        translationRAMComparison = nil
        translationRAMInspectionIssue = nil
        translationRAMTextReport = nil
        translationRAMTextInspectionIssue = nil
        translationRAMPointerReport = nil
        translationRAMPointerInspectionIssue = nil
        translationRAMInspectionIsLoading = false
        isTranslationRAMInspectorPresented = false
        lastTranslationDiagnosticURL = nil
        translationBaselines = []
        translationSuiteRuns = []
        resetTranslationSuiteExecution()
        translationReplayProgress = nil
        translationComparisonPhase = nil
        translationComparisonRoute = nil
    }

    private func refreshTranslationHistory() {
        do {
            try refreshTranslationHistory(for: translationProject)
        } catch {
            presentedError = "Translation Lab history could not be read: \(error.localizedDescription)"
        }
    }

    private func refreshTranslationHistory(
        for expectedProject: TranslationProject?
    ) throws {
        let preferredEvidenceID = selectedTranslationEvidenceID
        let preferredPrivateArtifactID = selectedTranslationPrivateArtifactID
        let preferredRoutePath = latestTranslationRouteURL?.standardizedFileURL.path
        translationRoutes = []
        translationEvidence = []
        translationPrivateArtifacts = []
        translationBaselines = []
        translationSuiteRuns = []
        translationEvidenceFrameComparison = nil
        translationEvidenceFrameComparisonIssue = nil
        translationRAMComparison = nil
        translationRAMInspectionIssue = nil
        translationRAMTextReport = nil
        translationRAMTextInspectionIssue = nil
        translationRAMPointerReport = nil
        translationRAMPointerInspectionIssue = nil
        translationRAMInspectionIsLoading = false
        isTranslationRAMInspectorPresented = false
        latestTranslationRoute = nil
        latestTranslationRouteURL = nil
        translationTestCaseName = ""
        translationTestCaseNote = ""
        lastTranslationEvidenceURL = nil
        translationPrivateStorageStatus = nil
        guard let project = expectedProject else { return }
        guard translationPipelineProjectIsCurrent(project) else {
            throw TranslationLabError.invalidProject(
                "the selected project changed before its history could be refreshed"
            )
        }
        translationRoutes = try translationEvidenceStore.listRoutes(project: project)
        let routeSelection = translationRoutes.first {
            $0.fileURL.standardizedFileURL.path == preferredRoutePath
        } ?? translationRoutes.first
        if let routeSelection {
            selectTranslationRoute(routeSelection.id)
        }
        translationEvidence = try translationEvidenceStore.listEvidence(project: project)
        translationPrivateArtifacts = try translationPrivateArtifactStore.list(project: project)
        translationPrivateStorageStatus = TranslationPrivateStorage.status(for: project)
        translationBaselines = try translationEvidenceStore.listBaselines(project: project)
        translationSuiteRuns = try translationEvidenceStore.listSuiteRuns(project: project)
        guard translationPipelineProjectIsCurrent(project) else {
            throw TranslationLabError.invalidProject(
                "the selected project changed while its history was being refreshed"
            )
        }
        lastTranslationEvidenceURL = translationEvidence.first?.artifact.directoryURL
        let selection = translationEvidence.first(where: { $0.id == preferredEvidenceID })
            ?? translationEvidence.first
        if let selection {
            selectTranslationEvidence(selection.id)
        } else {
            selectedTranslationEvidenceID = nil
            translationEvidenceReviewStatus = .unreviewed
            translationEvidenceReviewNote = ""
            translationEvidenceFrameComparison = nil
            translationEvidenceFrameComparisonIssue = nil
        }
        selectedTranslationPrivateArtifactID = translationPrivateArtifacts.first {
            $0.id == preferredPrivateArtifactID
        }?.id ?? translationPrivateArtifacts.first?.id
    }

    private func refreshTranslationEvidenceFrameComparison() {
        translationEvidenceFrameComparison = nil
        translationEvidenceFrameComparisonIssue = nil
        guard
            let selected = selectedTranslationEvidence,
            let pair = pairedTranslationEvidence,
            selected.isIntact,
            pair.isIntact,
            let selectedPNG = selected.framePNG,
            let pairPNG = pair.framePNG
        else { return }
        do {
            translationEvidenceFrameComparison = try ScreenshotExporter
                .compareEvidenceFrames(selectedPNG, pairPNG)
        } catch {
            translationEvidenceFrameComparisonIssue = error.localizedDescription
        }
    }

    private func runGuardedTranslationPack(
        completion: TranslationPipelineCompletion
    ) {
        runTranslationPipeline(
            Self.guardedTranslationPackStages,
            completion: completion,
            requiresSafeStatusPreflight: true
        )
    }

    private func runTranslationPipeline(
        _ stages: [TranslationToolkitStage],
        completion: TranslationPipelineCompletion = .none,
        requiresSafeStatusPreflight: Bool = false
    ) {
        guard let project = translationProject, !translationToolIsRunning else { return }
        if requiresSafeStatusPreflight {
            guard let firstStage = stages.first else {
                presentedError = "Strict Pack was not started because its Status preflight is missing."
                return
            }
            guard case .status = firstStage else {
                presentedError = "Strict Pack was not started because Status is not its first preflight stage."
                return
            }
        }
        translationToolIsRunning = true
        translationCommandOutput = ""
        Task { [weak self] in
            guard let self else { return }
            var results: [TranslationCommandResult] = []
            do {
                for (stageIndex, stage) in stages.enumerated() {
                    guard self.translationPipelineProjectIsCurrent(project) else {
                        self.stopTranslationPipeline(
                            "Translation Lab stopped because the selected project changed before the next toolkit stage.",
                            completion: completion
                        )
                        return
                    }
                    self.translationToolPhase = "\(stage.title)…"
                    let result = try await Task.detached(priority: .userInitiated) {
                        try TranslationToolkitRunner.run(stage, project: project)
                    }.value
                    guard self.translationPipelineProjectIsCurrent(project) else {
                        self.stopTranslationPipeline(
                            "Translation Lab stopped because the selected project changed while a toolkit stage was running.",
                            completion: completion
                        )
                        return
                    }
                    results.append(result)
                    self.translationCommandOutput = self.formattedTranslationOutput(results)
                    var readiness: TranslationReadiness?
                    if case .status = stage {
                        let parsed = TranslationReadiness(output: result.output)
                        readiness = parsed
                        self.translationReadiness = parsed
                    }
                    guard result.succeeded else {
                        self.stopTranslationPipeline(
                            "\(stage.title) stopped the pipeline. The toolkit did not change the source ROM; review the Translation Lab output.",
                            completion: completion
                        )
                        return
                    }
                    if case .status = stage {
                        do {
                            try self.refreshTranslationHistory(for: project)
                            appDiagnostic(
                                "translation history refreshed after status routes=\(self.translationRoutes.count) evidence=\(self.translationEvidence.count) evidence_integrity_issues=\(self.translationEvidence.count(where: { !$0.isIntact })) baselines=\(self.translationBaselines.count) suites=\(self.translationSuiteRuns.count)"
                            )
                        } catch {
                            self.stopTranslationPipeline(
                                "Translation Lab stopped after Status because route and evidence history could not be refreshed: \(error.localizedDescription)",
                                completion: completion
                            )
                            return
                        }
                    }
                    if requiresSafeStatusPreflight, stageIndex == 0 {
                        guard let readiness else {
                            self.stopTranslationPipeline(
                                "Strict Pack was not started because fresh Status could not be parsed.",
                                completion: completion
                            )
                            return
                        }
                        switch readiness.status {
                        case .complete, .pending:
                            break
                        case .blocked, .unknown:
                            self.stopTranslationPipeline(
                                "Strict Pack was not started because fresh Status reported \(readiness.status.rawValue). Resolve the toolkit blockers shown in Translation Lab, then try again.",
                                completion: completion
                            )
                            return
                        }
                    }
                }
                guard self.translationPipelineProjectIsCurrent(project) else {
                    self.stopTranslationPipeline(
                        "Translation Lab stopped because the selected project changed before the requested action could start.",
                        completion: completion
                    )
                    return
                }
                switch completion {
                case .none:
                    break
                case .playPatched:
                    self.playTranslationROM(.patched)
                case let .verifyRoute(route):
                    self.launchTranslationComparison(role: .original, route: route)
                case let .locateVisualDivergence(route):
                    self.launchTranslationVisualDivergence(route)
                }
            } catch {
                self.stopTranslationPipeline(
                    "The translation toolkit could not run: \(error.localizedDescription)",
                    completion: completion
                )
                return
            }
            self.translationToolIsRunning = false
            self.translationToolPhase = nil
        }
    }

    private func translationPipelineProjectIsCurrent(
        _ expected: TranslationProject
    ) -> Bool {
        guard let current = translationProject else { return false }
        return current.id == expected.id
            && current.rootURL.standardizedFileURL.path
                == expected.rootURL.standardizedFileURL.path
    }

    private func stopTranslationPipeline(
        _ message: String,
        completion: TranslationPipelineCompletion
    ) {
        presentedError = message
        if case .verifyRoute = completion {
            cancelTranslationComparison()
        } else if case .locateVisualDivergence = completion {
            finishTranslationVisualDivergenceRun()
        }
        translationToolIsRunning = false
        translationToolPhase = nil
    }

    private func launchTranslationVisualDivergence(_ route: TranslationRoute) {
        guard translationVisualDivergenceIsRunning,
              isTranslationVisualDivergencePresented else { return }
        guard let project = translationProject else {
            finishTranslationVisualDivergenceRun()
            translationVisualDivergenceIssue = "The translation project is no longer linked."
            return
        }
        do {
            try validateTranslationRouteForCurrentProject(route)
            try validateTranslationReplayTarget(.patched, route: route)
            guard let start = route.start else {
                throw TranslationLabError.invalidRoute(
                    "the route start context is missing"
                )
            }
            guard start.firmware.source != .installed else {
                throw TranslationLabError.invalidRoute(
                    "this legacy route predates Open-IPL-only playback; re-record it with the current SwanSong Open IPL"
                )
            }
            let originalURL = try project.romURL(for: .original)
            let patchedURL = try project.romURL(for: .patched)
            let generation = UUID()
            translationVisualDivergenceGeneration = generation
            let task = Task { [weak self] in
                guard let self else { return }
                do {
                    let (originalROM, patchedROM) = try await Task.detached(
                        priority: .userInitiated
                    ) {
                        (
                            try Data(contentsOf: originalURL, options: [.mappedIfSafe]),
                            try Data(contentsOf: patchedURL, options: [.mappedIfSafe])
                        )
                    }.value
                    let result = try await TranslationVisualDivergenceRunner.run(
                        route: route,
                        originalROM: originalROM,
                        patchedROM: patchedROM
                    ) { [weak self] progress in
                        await MainActor.run {
                            guard self?.translationVisualDivergenceGeneration == generation,
                                  self?.translationVisualDivergenceRoute == route else { return }
                            self?.translationVisualDivergenceProgress = progress
                        }
                    }
                    guard self.translationVisualDivergenceGeneration == generation,
                          self.translationVisualDivergenceRoute == route else { return }
                    self.translationVisualDivergenceResult = result
                    self.translationVisualDivergenceIssue = nil
                    switch result {
                    case let .firstDifference(divergence):
                        appDiagnostic(
                            "first visual change complete result=difference frame=\(divergence.frame.frameIndex + 1) kind=\(divergence.kind.rawValue)"
                        )
                    case let .noDifference(noDifference):
                        appDiagnostic(
                            "first visual change complete result=no-difference frames=\(noDifference.framesCompared)"
                        )
                    }
                    self.finishTranslationVisualDivergenceRun()
                } catch is CancellationError {
                    guard self.translationVisualDivergenceGeneration == generation,
                          self.translationVisualDivergenceRoute == route else { return }
                    self.translationVisualDivergenceIssue =
                        "Comparison canceled. No library, save, or state files were changed."
                    appDiagnostic("first visual change canceled")
                    self.finishTranslationVisualDivergenceRun()
                } catch {
                    guard self.translationVisualDivergenceGeneration == generation,
                          self.translationVisualDivergenceRoute == route else { return }
                    self.translationVisualDivergenceIssue = error.localizedDescription
                    appDiagnostic(
                        "first visual change failed reason=\(error.localizedDescription)"
                    )
                    self.finishTranslationVisualDivergenceRun()
                }
            }
            translationVisualDivergenceTask = task
        } catch {
            translationVisualDivergenceIssue = error.localizedDescription
            finishTranslationVisualDivergenceRun()
        }
    }

    func cancelTranslationVisualDivergence() {
        guard translationVisualDivergenceIsRunning else { return }
        translationVisualDivergenceGeneration = UUID()
        translationVisualDivergenceTask?.cancel()
        translationVisualDivergenceIssue =
            "Comparison canceled. No library, save, or state files were changed."
        finishTranslationVisualDivergenceRun()
    }

    func dismissTranslationVisualDivergence() {
        if translationVisualDivergenceIsRunning {
            cancelTranslationVisualDivergence()
        }
        isTranslationVisualDivergencePresented = false
    }

    func createTranslationTestAtFirstVisualChange() {
        guard
            let project = translationProject,
            let route = translationVisualDivergenceRoute,
            case let .firstDifference(divergence)? = translationVisualDivergenceResult
        else { return }
        do {
            let derived = try route.prefix(
                through: divergence.frame.frameIndex,
                originalFrame: divergence.frame.frames.original
            )
            let url = try translationEvidenceStore.saveRoute(derived, project: project)
            latestTranslationRoute = derived
            latestTranslationRouteURL = url
            refreshTranslationHistory()
            translationTestCaseName = "First visual change · frame \(divergence.frame.frameIndex + 1)"
            translationTestCaseNote =
                "Derived from the selected clean-boot route at its first Original/Patched game-raster difference."
            guard saveSelectedTranslationTestCase() else { return }
            presentedNotice =
                "Created a focused immutable test ending at the first visual change, frame \(divergence.frame.frameIndex + 1)."
        } catch {
            presentedError = "The focused first-change test could not be created: \(error.localizedDescription)"
        }
    }

    private func finishTranslationVisualDivergenceRun() {
        translationVisualDivergenceTask = nil
        translationVisualDivergenceIsRunning = false
    }

    private func launchTranslationComparison(
        role: TranslationROMRole,
        route: TranslationRoute
    ) {
        do {
            try validateTranslationReplayTarget(role, route: route)
        } catch {
            presentedError = "A/B verification stopped before replay: \(error.localizedDescription)"
            cancelTranslationComparison()
            return
        }
        translationComparisonPhase = nil
        translationComparisonRoute = nil
        translationComparisonIsTransitioning = true
        defer { translationComparisonIsTransitioning = false }
        playTranslationROM(role)
        guard activeTranslationRole == role else {
            cancelTranslationComparison()
            return
        }

        translationComparisonRoute = route
        translationComparisonPhase = .replaying(role)
        translationReplayRoute = route
        translationReplayFrameIndex = 0
        translationReplayProgress = 0
        translationEvidenceRoute = nil
        translationEvidenceRouteFrameNumber = nil
        isFastForwarding = true
        audioOutput.setFastForwarding(true)
        presentedNotice = nil
    }

    private func advanceTranslationComparison(after role: TranslationROMRole) {
        guard
            translationComparisonPhase == .capturing(role),
            let route = translationComparisonRoute
        else { return }

        switch role {
        case .original:
            launchTranslationComparison(role: .patched, route: route)
        case .patched:
            if translationSuiteIsActive {
                do {
                    try recordCurrentTranslationSuiteCase()
                    guard let index = translationSuiteCurrentCaseIndex else { return }
                    let nextIndex = index + 1
                    if translationSuiteQueue.indices.contains(nextIndex) {
                        translationSuiteCurrentCaseIndex = nextIndex
                        let next = translationSuiteQueue[nextIndex]
                        selectTranslationRoute(next.id)
                        launchTranslationComparison(role: .original, route: next.route)
                    } else {
                        finishTranslationSuite()
                    }
                } catch {
                    presentedError = "The route suite could not record its result: \(error.localizedDescription)"
                    cancelTranslationComparison()
                }
                return
            }
            translationComparisonPhase = nil
            translationComparisonRoute = nil
            stopPlaying()
            section = .translationLab
            presentedNotice = "A/B route verification complete. Original and patched evidence were captured at the same route endpoint and opened as a paired review."
        }
    }

    private func cancelTranslationComparison() {
        translationComparisonPhase = nil
        translationComparisonRoute = nil
        resetTranslationSuiteExecution()
    }

    private func recordCurrentTranslationSuiteCase() throws {
        guard
            let index = translationSuiteCurrentCaseIndex,
            translationSuiteQueue.indices.contains(index),
            let selected = selectedTranslationEvidence,
            let pair = pairedTranslationEvidence,
            let selectedManifest = selected.manifest,
            let pairManifest = pair.manifest,
            let comparison = translationEvidenceFrameComparison
        else {
            throw TranslationLabError.invalidProject(
                "the completed route is missing its verified evidence pair"
            )
        }
        let summary = translationSuiteQueue[index]
        guard
            selected.isIntact,
            pair.isIntact,
            selectedManifest.route == summary.routeDigest,
            pairManifest.route == summary.routeDigest
        else {
            throw TranslationLabError.invalidProject(
                "the completed route evidence does not match the immutable route digest"
            )
        }
        let original = selectedManifest.romRole == .original ? selected : pair
        let patched = selectedManifest.romRole == .patched ? selected : pair
        guard
            original.manifest?.romRole == .original,
            patched.manifest?.romRole == .patched,
            let originalFrameNumber = original.manifest?.frameNumber,
            let patchedFrameNumber = patched.manifest?.frameNumber
        else {
            throw TranslationLabError.invalidProject(
                "the completed route does not contain both ROM lanes"
            )
        }
        var baselineComparison: TranslationSuiteBaselineComparison?
        var baselineIssue: String?
        if let baseline = translationBaseline(for: summary) {
            if baseline.isIntact,
               let baselineEvidence = baseline.evidence,
               let baselinePNG = baselineEvidence.framePNG,
               let patchedPNG = patched.framePNG {
                do {
                    let comparison = try ScreenshotExporter.compareEvidenceFrames(
                        baselinePNG,
                        patchedPNG
                    )
                    baselineComparison = TranslationSuiteBaselineComparison(
                        evidenceName: baselineEvidence.artifact.name,
                        difference: comparison.visualization.difference,
                        changedBounds: comparison.visualization.changedBounds
                    )
                } catch {
                    baselineIssue = "The approved baseline could not be compared: \(error.localizedDescription)"
                }
            } else {
                baselineIssue = baseline.integrityIssue
                    ?? "The approved baseline evidence is not intact."
            }
        } else {
            baselineIssue = "No approved baseline is set for this route."
        }
        translationSuiteCaseResults.append(
            TranslationSuiteCaseResult(
                route: summary.routeDigest,
                name: translationSuiteName(for: summary),
                originalEvidenceName: original.artifact.name,
                patchedEvidenceName: patched.artifact.name,
                originalFrameNumber: originalFrameNumber,
                patchedFrameNumber: patchedFrameNumber,
                difference: comparison.visualization.difference,
                changedBounds: comparison.visualization.changedBounds,
                baselineComparison: baselineComparison,
                baselineIssue: baselineIssue
            )
        )
    }

    private func finishTranslationSuite() {
        guard
            let project = translationProject,
            let startedAt = translationSuiteStartedAt,
            !translationSuiteCaseResults.isEmpty,
            translationSuiteCaseResults.count == translationSuiteTotalCaseCount
        else {
            presentedError = "The route suite ended before every test case produced a verified pair."
            cancelTranslationComparison()
            return
        }
        let run = TranslationSuiteRun(
            projectTitle: project.title,
            startedAt: startedAt,
            cases: translationSuiteCaseResults
        )
        do {
            _ = try translationEvidenceStore.saveSuiteRun(run, project: project)
            translationComparisonPhase = nil
            translationComparisonRoute = nil
            resetTranslationSuiteExecution()
            stopPlaying()
            refreshTranslationHistory()
            section = .translationLab
            presentedNotice = "Verified \(run.cases.count) route test case\(run.cases.count == 1 ? "" : "s") against both ROMs. The immutable suite report is ready for review."
        } catch {
            presentedError = "The route suite evidence was captured, but its report could not be saved: \(error.localizedDescription)"
            translationComparisonPhase = nil
            translationComparisonRoute = nil
            resetTranslationSuiteExecution()
            stopPlaying()
            section = .translationLab
        }
    }

    private func resetTranslationSuiteExecution() {
        translationSuiteQueue = []
        translationSuiteStartedAt = nil
        translationSuiteCurrentCaseIndex = nil
        translationSuiteTotalCaseCount = 0
        translationSuiteCaseResults = []
    }

    private func translationSuiteName(for summary: TranslationRouteSummary) -> String {
        summary.testCase?.name ?? "Untitled route \(summary.routeDigest.sha256.prefix(8))"
    }

    private func formattedTranslationOutput(_ results: [TranslationCommandResult]) -> String {
        results.map { result in
            let outcome = result.succeeded ? "PASS" : "FAILED (\(result.exitCode))"
            return "[\(outcome)] \(result.stageTitle)\n\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        .joined(separator: "\n\n")
    }

    private func translationInputForNextFrame(manualInput: EngineInput) -> EngineInput {
        if let route = translationReplayRoute {
            return route.input(at: translationReplayFrameIndex)
        }
        #if SWAN_SONG_AUTOMATION
        if automatedTranslationPCV2InputProbe,
           allowsAutomatedPCV2InputProbe,
           translationRouteRecorder != nil,
           playingGame?.resolvedHardwareModel == .pocketChallengeV2 {
            // One independent semantic PCV2 control per frame, followed by a
            // release frame. This is deliberately unavailable to normal app
            // sessions; the source-free Translation Lab gate uses it to prove
            // that route recording and replay preserve all nine Benesse keys.
            let sequence: [EngineInput] = [
                .pocketChallengeUp,
                .pocketChallengeRight,
                .pocketChallengeDown,
                .pocketChallengeLeft,
                .pocketChallengePass,
                .pocketChallengeCircle,
                .pocketChallengeClear,
                .pocketChallengeView,
                .pocketChallengeEscape,
                [],
            ]
            let nextFrameIndex = Int(currentFrame?.number ?? 0)
            return sequence.indices.contains(nextFrameIndex)
                ? sequence[nextFrameIndex]
                : []
        }
        #endif
        return manualInput
    }

    private func didProduceTranslationFrame(input: EngineInput, frame: EngineVideoFrame) {
        let frameNumber = frame.number
        if let checkpointFrame = translationEvidenceRouteFrameNumber,
           checkpointFrame != frameNumber {
            translationEvidenceRoute = nil
            translationEvidenceRouteFrameNumber = nil
        }
        if var recorder = translationRouteRecorder {
            do {
                try recorder.record(input: input, frame: frame)
                translationRouteRecorder = recorder
            } catch {
                cancelTranslationRouteRecording(showNotice: false)
                isPaused = true
                audioOutput.setPaused(true)
                presentedError = "Route recording stopped: \(error.localizedDescription)"
                return
            }
        }
        if automatedTranslationRouteEndFrame == frameNumber {
            automatedTranslationRouteEndFrame = nil
            finishTranslationRouteRecording(showNotice: false)
        }
        if automatedTranslationEvidenceFrame == frameNumber {
            automatedTranslationEvidenceFrame = nil
            captureTranslationEvidence()
        }
        guard let route = translationReplayRoute else { return }
        translationReplayFrameIndex += 1
        translationReplayProgress = min(
            Double(translationReplayFrameIndex) / Double(max(route.totalFrames, 1)),
            1
        )
        if translationReplayFrameIndex >= route.totalFrames {
            translationReplayRoute = nil
            if activeTranslationRole == .original,
               let checkpoint = route.checkpoint,
               !checkpoint.matches(frame) {
                let actualCheckpoint = try? TranslationRouteCheckpoint.fingerprint(frame)
                translationReplayProgress = nil
                translationEvidenceRoute = nil
                translationEvidenceRouteFrameNumber = nil
                isPaused = true
                audioOutput.setPaused(true)
                if translationComparisonIsActive {
                    translationComparisonPhase = nil
                    translationComparisonRoute = nil
                    resetTranslationSuiteExecution()
                }
                presentedError = "The Original ROM did not reproduce the recorded checkpoint at frame \(frameNumber) (expected \(checkpoint.sha256.prefix(10))…, got \(actualCheckpoint?.prefix(10) ?? "unavailable")…). The route, Open IPL, or emulator context changed; re-record this test before creating evidence."
                return
            }
            translationEvidenceRoute = route
            translationEvidenceRouteFrameNumber = frameNumber
            isPaused = true
            audioOutput.setPaused(true)
            if case let .replaying(role) = translationComparisonPhase {
                translationComparisonPhase = .capturing(role)
                captureTranslationEvidence()
            } else {
                presentedNotice = "Route replay reached its recorded checkpoint at frame \(frameNumber). Capture evidence now, or run the same route against the other ROM."
            }
        }
    }

    @discardableResult
    func observePlayerVideoActivity(_ frame: EngineVideoFrame) -> Bool {
        let report = frameActivityMonitor.observe(frame)
        playerVideoActivityDiagnostic.observe(report)
        return report.consecutiveUniformFrames == 0
    }

    private func resetPlayerVideoActivity() {
        frameActivityMonitor.reset()
        playerVideoActivityDiagnostic.reset()
    }

    #if SWAN_SONG_AUTOMATION
    private func captureAutomatedFrameIfRequested(_ frame: EngineVideoFrame) {
        guard
            automatedCaptureFrame == frame.number,
            let url = automatedCaptureFrameURL
        else { return }
        automatedCaptureFrame = nil
        automatedCaptureFrameURL = nil
        do {
            try ScreenshotExporter.pngData(for: frame).write(to: url, options: .atomic)
            appDiagnostic("captured frame=\(frame.number) path=\(url.path)")
        } catch {
            appDiagnostic("frame capture failed frame=\(frame.number) reason=\(error.localizedDescription)")
        }
    }

    private func captureAutomatedStateLoadPreviewIfRequested(_ frame: EngineVideoFrame) {
        guard let url = automatedStateLoadPreviewURL else { return }
        automatedStateLoadPreviewURL = nil
        do {
            try ScreenshotExporter.pngData(for: frame).write(to: url, options: .atomic)
            appDiagnostic("captured loaded-state preview frame=\(frame.number) path=\(url.path)")
        } catch {
            appDiagnostic(
                "loaded-state preview capture failed frame=\(frame.number) reason=\(error.localizedDescription)"
            )
        }
    }

    private func captureAutomatedRewindReferenceIfRequested(
        _ frame: EngineVideoFrame
    ) {
        guard automatedRewindReferenceFrame == frame.number else { return }
        let url: URL?
        let phase: String
        if automatedRewindHasCompleted {
            url = automatedRewindAfterURL
            phase = "after"
        } else if !automatedRewindReferenceWasCaptured {
            url = automatedRewindBeforeURL
            phase = "before"
        } else {
            return
        }
        guard let url else { return }
        do {
            try ScreenshotExporter.pngData(for: frame).write(to: url, options: .atomic)
            if automatedRewindHasCompleted {
                appDiagnostic("captured rewind reference after frame=\(frame.number) path=\(url.path)")
            } else {
                automatedRewindReferenceWasCaptured = true
                appDiagnostic("captured rewind reference before frame=\(frame.number) path=\(url.path)")
            }
        } catch {
            appDiagnostic(
                "rewind reference capture failed phase=\(phase) frame=\(frame.number) reason=\(error.localizedDescription)"
            )
        }
    }

    private func triggerAutomatedRewindUndoIfRequested(at frameNumber: UInt64) {
        guard automatedRewindHasCompleted,
              automatedRewindUndoAtFrame == frameNumber else { return }
        automatedRewindUndoAtFrame = nil
        automatedRewindUndoWasRequested = true
        appDiagnostic(
            "rewind undo requested frame=\(frameNumber) ready=\(canUndoStateLoad) paused=\(isPaused) operation_idle=\(playerStateOperation == nil) history_count=\(rewindCheckpoints.count)"
        )
        undoLastStateLoad()
    }

    private func captureAutomatedRewindUndoRestorationIfRequested(
        _ frame: EngineVideoFrame
    ) {
        guard automatedRewindUndoWasRequested,
              !automatedRewindUndoHasCompleted,
              let url = automatedRewindUndoRestoredURL else { return }
        do {
            try ScreenshotExporter.pngData(for: frame).write(to: url, options: .atomic)
            automatedRewindUndoHasCompleted = true
            appDiagnostic(
                "rewind undo restored frame=\(frame.number) paused=\(isPaused) operation_idle=\(playerStateOperation == nil) history_count=\(rewindCheckpoints.count) undo_ready=\(canUndoStateLoad) natural_frame_pending=\(playerStateNeedsNaturalFrame) path=\(url.path)"
            )
        } catch {
            appDiagnostic(
                "rewind undo reference capture failed frame=\(frame.number) reason=\(error.localizedDescription)"
            )
        }
    }
    #endif

    private func persist() throws {
        try store.save(GameLibraryDocument(games: games))
    }

    private func loadCachedHomebrewCatalog() {
        guard homebrewCatalogIsConfigured else { return }
        do {
            guard let bundle = try homebrewCatalogCacheStore.load() else { return }
            let authenticated = try homebrewCatalogSignatureVerifier.verify(
                catalogData: bundle.catalogData,
                signatureData: bundle.signatureData
            )
            let catalog = try Self.decodeHomebrewCatalog(
                bundle.catalogData,
                sourceURL: homebrewCatalogClient.catalogSourceURL
            )
            let currentState = try homebrewCatalogHighWaterStore.load(
                catalogID: catalog.catalogID
            )
            let nextState = try HomebrewCatalogRollbackPolicy.nextState(
                catalog: catalog,
                authenticated: authenticated,
                trustedKeys: homebrewCatalogSignatureVerifier.trustedKeys,
                minimumRevision: homebrewCatalogMinimumRevision,
                currentState: currentState
            )
            // Always commit through the cross-process transaction. A second
            // process may have advanced the state since `currentState` loaded.
            try homebrewCatalogHighWaterStore.advance(to: nextState)
            homebrewCatalog = catalog
            homebrewCatalogLastUpdatedAt = catalog.generatedAt
            selectedHomebrewEntryID = catalog.entries.first?.id
        } catch {
            appDiagnostic(
                "saved homebrew catalog skipped reason=\(error.localizedDescription)"
            )
            if homebrewCatalogConsentGranted {
                homebrewCatalogIssue = "The catalog saved on this Mac could not be verified. Refresh to request a clean copy from GitHub."
            }
        }
    }

    nonisolated private static func decodeHomebrewCatalog(
        _ data: Data,
        sourceURL: URL
    ) throws -> HomebrewCatalog {
        if sourceURL == PublishedHomebrewCatalogDecoder.sourceURL {
            return try PublishedHomebrewCatalogDecoder.decode(
                data,
                sourceURL: sourceURL
            )
        }
        return try HomebrewCatalogValidator.decode(data, sourceURL: sourceURL)
    }

    nonisolated private static func shouldRetryHomebrewCatalogPair(
        _ error: HomebrewCatalogSignatureError
    ) -> Bool {
        switch error {
        case .catalogByteCountMismatch, .catalogDigestMismatch, .noTrustedSignature:
            true
        default:
            false
        }
    }

    private func loadGameArtwork() {
        var loaded: [GameRecord.ID: GameArtworkRecord] = [:]
        for game in games where game.artworkPreference != .procedural {
            do {
                if let artwork = try artworkStore.load(
                    gameID: game.id,
                    romChecksum: game.metadata.computedChecksum,
                    romFileSize: game.metadata.fileSize
                ) {
                    loaded[game.id] = artwork
                }
            } catch {
                appDiagnostic("library artwork skipped for \(game.id): \(error.localizedDescription)")
            }
        }
        gameArtwork = loaded
    }

    private func refreshManagedGameHealth() {
        let allEntries = games.compactMap { game -> (
            GameRecord.ID,
            ManagedGameReference
        )? in
            guard let reference = game.managedROM else { return nil }
            return (game.id, reference)
        }
        let managedIDs = Set(allEntries.map(\.0))
        let entries = allEntries.filter { $0.0 != repairingGameID }
        let scannedIDs = Set(entries.map(\.0))
        managedGameHealth = managedGameHealth.filter { managedIDs.contains($0.key) }
        let generation = UUID()
        managedGameHealthScanGeneration = generation
        checkingManagedGameIDs = scannedIDs
        guard !entries.isEmpty else { return }

        let managedGameStore = managedGameStore
        Task { [weak self] in
            let results = await Task.detached(priority: .utility) {
                var health: [GameRecord.ID: ManagedGameHealth] = [:]
                var auditedReferences: [ManagedGameReference: ManagedGameHealth] = [:]
                for (id, reference) in entries {
                    let value = auditedReferences[reference]
                        ?? managedGameStore.health(of: reference)
                    auditedReferences[reference] = value
                    health[id] = value
                }
                return health
            }.value
            guard let self,
                  self.managedGameHealthScanGeneration == generation else { return }
            for (id, value) in results {
                guard let current = self.games.first(where: { $0.id == id }),
                      current.managedROM == entries.first(where: { $0.0 == id })?.1 else {
                    continue
                }
                self.managedGameHealth[id] = value
            }
            self.checkingManagedGameIDs.subtract(scannedIDs)
        }
    }

    private func invalidateManagedGameHealthScan() {
        managedGameHealthScanGeneration = UUID()
        checkingManagedGameIDs.removeAll()
    }

    private func hasCartridgeSave(_ game: GameRecord) -> Bool {
        game.resolvedHardwareModel != .pocketChallengeV2
            && (game.metadata.saveType != 0 || game.metadata.hasRTC)
    }

    private var gameplayControllerInput: EngineInput {
        guard playingGame?.resolvedHardwareModel == .pocketChallengeV2 else {
            return controllerInput
        }
        let elements = controllerPhysicalElements
        var input: EngineInput = []

        if elements.contains(.dpadUp)
            || elements.contains(.leftStickUp)
            || elements.contains(.rightStickUp) {
            input.insert(.pocketChallengeUp)
        }
        if elements.contains(.dpadRight)
            || elements.contains(.leftStickRight)
            || elements.contains(.rightStickRight) {
            input.insert(.pocketChallengeRight)
        }
        if elements.contains(.dpadDown)
            || elements.contains(.leftStickDown)
            || elements.contains(.rightStickDown) {
            input.insert(.pocketChallengeDown)
        }
        if elements.contains(.dpadLeft)
            || elements.contains(.leftStickLeft)
            || elements.contains(.rightStickLeft) {
            input.insert(.pocketChallengeLeft)
        }
        if elements.contains(.buttonWest) { input.insert(.pocketChallengePass) }
        if elements.contains(.buttonSouth) { input.insert(.pocketChallengeCircle) }
        if elements.contains(.buttonEast) { input.insert(.pocketChallengeClear) }
        if elements.contains(.menu) { input.insert(.pocketChallengeView) }
        if elements.contains(.options) || elements.contains(.buttonNorth) {
            input.insert(.pocketChallengeEscape)
        }
        return input
    }
}
