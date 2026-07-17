import AppKit
import CryptoKit
import SwiftUI
import SwanSongKit
import XCTest
@testable import SwanSongApp

@MainActor
final class UISnapshotRegressionTests: XCTestCase {
    private static let perceptualHashAlgorithm = "dhash-16x16-luma-v1"
    // 24/256 bits (9.375%) tolerates minor font/material rasterization drift
    // while still rejecting meaningful layout, hierarchy, or theme changes.
    private static let maximumPerceptualHammingDistance = 24

    private enum Scheme: String, CaseIterable {
        case light
        case dark

        var colorScheme: ColorScheme {
            self == .light ? .light : .dark
        }
    }

    private struct Scenario {
        let name: String
        let size: CGSize
        let usesPolishOutput: Bool
        let makeView: () -> AnyView
        let prepare: ((NSView, NSWindow) -> Void)?

        init(
            name: String,
            size: CGSize,
            usesPolishOutput: Bool = false,
            prepare: ((NSView, NSWindow) -> Void)? = nil,
            makeView: @escaping () -> AnyView
        ) {
            self.name = name
            self.size = size
            self.usesPolishOutput = usesPolishOutput
            self.makeView = makeView
            self.prepare = prepare
        }
    }

    private struct SnapshotSignature: Codable {
        let name: String
        let scheme: String
        let width: Int
        let height: Int
        let pngByteCount: Int
        let sampledColorCount: Int
        let opaqueSampleFraction: Double
        let centralDominantColorFraction: Double
        let yellowPlaceholderFraction: Double
        let meanLuminance: Double
        let perceptualHash: String
        let sha256: String
    }

    private struct PerceptualBaselineDocument: Codable {
        let algorithm: String
        let bitCount: Int
        let maximumHammingDistance: Int
        let macOSMajorVersion: Int
        let entries: [String: String]
    }

    private struct SnapshotTimelineDocument: Codable {
        let schemaVersion: Int
        let entries: [GameStateManifest]
        let quickGeneration: UUID?
    }

    private struct GameConfidenceFixture {
        let model: AppModel
        let readyUntested: GameRecord
        let reachedVideo: GameRecord
        let colorReady: GameRecord
        let reportedIssues: GameRecord
    }

    private struct PocketChallengeV2UIFixture {
        let model: AppModel
        let game: GameRecord
    }

    private enum SnapshotError: LocalizedError {
        case appKitCacheFailed
        case pngEncodingFailed
        case invalidBaseline(String)

        var errorDescription: String? {
            switch self {
            case .appKitCacheFailed:
                "AppKit could not cache the offscreen view."
            case .pngEncodingFailed:
                "AppKit could not encode the offscreen view as PNG."
            case let .invalidBaseline(issue):
                "The UI perceptual baseline is invalid: \(issue)"
            }
        }
    }

    func testCoreSurfaceSnapshots() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let translationProjectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SwanSong-UIRegression-TranslationOverview-Snapshots",
                isDirectory: true
            )
        try resetTemporaryDirectory(translationProjectRoot)
        defer { try? FileManager.default.removeItem(at: translationProjectRoot) }
        let preservedWindowPreferences = [
            "showsSidebar",
            "libraryWindowWidth",
            "libraryWindowHeight",
            "librarySortOption",
            "showsLibraryInspector",
            "settingsPane",
        ].map { key in
            (key, UserDefaults.standard.object(forKey: key))
        }
        UserDefaults.standard.set(true, forKey: "showsSidebar")
        UserDefaults.standard.set(GameLibrarySortOrder.title.rawValue, forKey: "librarySortOption")
        defer {
            for (key, value) in preservedWindowPreferences {
                restoreUserDefault(value, forKey: key)
            }
        }
        let scenarios = try makeScenarios(
            root: root,
            translationProjectRoot: translationProjectRoot
        )
        let output = try snapshotOutputDirectory()
        let polishOutput = output
            .deletingLastPathComponent()
            .appendingPathComponent("ui-polish-regression", isDirectory: true)
        try resetTemporaryDirectory(polishOutput)
        var signatures: [SnapshotSignature] = []

        for scenario in scenarios {
            for scheme in Scheme.allCases {
                let rendered = try render(
                    scenario.makeView(),
                    size: scenario.size,
                    scheme: scheme,
                    prepare: scenario.prepare
                )
                let fileName = "\(scenario.name)-\(scheme.rawValue).png"
                try rendered.png.write(
                    to: (scenario.usesPolishOutput ? polishOutput : output)
                        .appendingPathComponent(fileName),
                    options: [.atomic]
                )

                let signature = imageSignature(
                    name: scenario.name,
                    scheme: scheme,
                    bitmap: rendered.bitmap,
                    png: rendered.png
                )
                signatures.append(signature)
                XCTAssertEqual(signature.width, Int(scenario.size.width), fileName)
                XCTAssertEqual(signature.height, Int(scenario.size.height), fileName)
                XCTAssertGreaterThan(signature.pngByteCount, 2_000, fileName)
                XCTAssertGreaterThan(signature.sampledColorCount, 8, fileName)
                let minimumOpaqueFraction = scenario.name.contains("-settings-")
                    ? 0.97
                    : 0.98
                XCTAssertGreaterThan(
                    signature.opaqueSampleFraction,
                    minimumOpaqueFraction,
                    fileName
                )
                XCTAssertLessThan(
                    signature.centralDominantColorFraction,
                    0.96,
                    "\(fileName) has a largely blank central region"
                )
                XCTAssertLessThan(
                    signature.yellowPlaceholderFraction,
                    0.08,
                    "\(fileName) contains an unsupported-control placeholder"
                )
            }
        }

        XCTAssertEqual(signatures.count, 66)
        for scenario in scenarios {
            let pair = signatures.filter { $0.name == scenario.name }
            XCTAssertEqual(pair.count, 2, scenario.name)
            if scenario.name.hasPrefix("player-canvas-") {
                XCTAssertEqual(
                    pair[0].sha256,
                    pair[1].sha256,
                    "The distraction-free player canvas should remain deliberately dark in both system appearances"
                )
            } else {
                XCTAssertNotEqual(
                    pair[0].sha256,
                    pair[1].sha256,
                    "\(scenario.name) ignored Light/Dark"
                )
            }
        }

        try enforcePerceptualBaselines(signatures)

        let manifestURL = output.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(signatures).write(to: manifestURL, options: [.atomic])
        try encoder.encode(signatures.filter { signature in
            scenarios.first { $0.name == signature.name }?.usesPolishOutput == true
        }).write(
            to: polishOutput.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
    }

    func testHomebrewSurfaceSnapshots() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let consentKey = "SwanSong.homebrewCatalogConsent.v1"
        let preservedPreferences = [
            consentKey,
            "showsSidebar",
            "libraryWindowWidth",
            "libraryWindowHeight",
        ].map { key in
            (key, UserDefaults.standard.object(forKey: key))
        }
        defer {
            for (key, value) in preservedPreferences {
                restoreUserDefault(value, forKey: key)
            }
        }
        UserDefaults.standard.set(true, forKey: "showsSidebar")

        let catalog = homebrewCatalogFixture()
        try HomebrewCatalogValidator.validate(
            catalog,
            sourceURL: URL(
                string: "https://raw.githubusercontent.com/RegionallyFamous/swansong-story-forge/main/distribution/catalog-v1.json"
            )!
        )
        let comingSoonModel = makeModel(
            root: root.appendingPathComponent("coming-soon")
        )
        comingSoonModel.section = .homebrew
        let disclosureModel = makeHomebrewModel(
            root: root.appendingPathComponent("disclosure"),
            consentGranted: false,
            catalog: nil
        )
        let compactCatalogModel = makeHomebrewModel(
            root: root.appendingPathComponent("catalog-compact"),
            consentGranted: true,
            catalog: catalog
        )
        let wideCatalogModel = makeHomebrewModel(
            root: root.appendingPathComponent("catalog-wide"),
            consentGranted: true,
            catalog: catalog,
            selectedEntryID: "signal-before-dawn"
        )

        let compactSize = CGSize(width: 760, height: 560)
        let wideSize = CGSize(width: 1_180, height: 720)
        let scenarios = [
            Scenario(name: "homebrew-coming-soon-compact", size: compactSize) {
                AnyView(
                    RootView(
                        model: comingSoonModel,
                        usesDeterministicSidebarForOffscreenSnapshots: true
                    )
                )
            },
            Scenario(name: "homebrew-coming-soon-wide", size: wideSize) {
                AnyView(
                    RootView(
                        model: comingSoonModel,
                        usesDeterministicSidebarForOffscreenSnapshots: true
                    )
                )
            },
            Scenario(name: "homebrew-disclosure-compact", size: compactSize) {
                AnyView(
                    RootView(
                        model: disclosureModel,
                        usesDeterministicSidebarForOffscreenSnapshots: true
                    )
                )
            },
            Scenario(name: "homebrew-disclosure-wide", size: wideSize) {
                AnyView(
                    RootView(
                        model: disclosureModel,
                        usesDeterministicSidebarForOffscreenSnapshots: true
                    )
                )
            },
            Scenario(name: "homebrew-catalog-compact", size: compactSize) {
                AnyView(
                    RootView(
                        model: compactCatalogModel,
                        usesDeterministicSidebarForOffscreenSnapshots: true
                    )
                )
            },
            Scenario(name: "homebrew-catalog-wide", size: wideSize) {
                AnyView(
                    RootView(
                        model: wideCatalogModel,
                        usesDeterministicSidebarForOffscreenSnapshots: true
                    )
                )
            },
        ]
        let output = try snapshotOutputDirectory()
            .appendingPathComponent("homebrew", isDirectory: true)
        try FileManager.default.createDirectory(
            at: output,
            withIntermediateDirectories: true
        )
        var signatures = [SnapshotSignature]()

        for scenario in scenarios {
            for scheme in Scheme.allCases {
                let rendered = try render(
                    scenario.makeView(),
                    size: scenario.size,
                    scheme: scheme
                )
                let fileName = "\(scenario.name)-\(scheme.rawValue).png"
                try rendered.png.write(
                    to: output.appendingPathComponent(fileName),
                    options: [.atomic]
                )
                let signature = imageSignature(
                    name: scenario.name,
                    scheme: scheme,
                    bitmap: rendered.bitmap,
                    png: rendered.png
                )
                signatures.append(signature)
                XCTAssertEqual(signature.width, Int(scenario.size.width), fileName)
                XCTAssertEqual(signature.height, Int(scenario.size.height), fileName)
                XCTAssertGreaterThan(signature.pngByteCount, 2_000, fileName)
                XCTAssertGreaterThan(signature.sampledColorCount, 8, fileName)
                XCTAssertGreaterThan(signature.opaqueSampleFraction, 0.98, fileName)
                XCTAssertLessThan(
                    signature.centralDominantColorFraction,
                    0.96,
                    "\(fileName) has a largely blank central region"
                )
                XCTAssertLessThan(
                    signature.yellowPlaceholderFraction,
                    0.08,
                    "\(fileName) contains an unsupported-control placeholder"
                )
            }
        }

        XCTAssertEqual(signatures.count, scenarios.count * Scheme.allCases.count)
        for scenario in scenarios {
            let pair = signatures.filter { $0.name == scenario.name }
            XCTAssertEqual(pair.count, 2, scenario.name)
            XCTAssertNotEqual(
                pair[0].sha256,
                pair[1].sha256,
                "\(scenario.name) ignored Light/Dark"
            )
        }
        XCTAssertFalse(comingSoonModel.homebrewCatalogIsConfigured)
        XCTAssertNil(comingSoonModel.homebrewCatalog)
        XCTAssertFalse(disclosureModel.homebrewCatalogIsLoading)
        XCTAssertNil(disclosureModel.homebrewCatalog)
        XCTAssertFalse(compactCatalogModel.homebrewCatalogIsLoading)
        XCTAssertEqual(compactCatalogModel.homebrewCatalog, catalog)
        XCTAssertFalse(wideCatalogModel.homebrewCatalogIsLoading)
        XCTAssertEqual(wideCatalogModel.homebrewCatalog, catalog)
    }

    func testLegalSupportOverviewRendersAtMinimumWindowSize() throws {
        let preferenceKey = "legalSupportSelectedSection"
        let preservedSelection = UserDefaults.standard.object(forKey: preferenceKey)
        UserDefaults.standard.set(LegalSupportSection.overview.rawValue, forKey: preferenceKey)
        defer { restoreUserDefault(preservedSelection, forKey: preferenceKey) }

        let size = CGSize(width: 820, height: 640)
        let rendered = try render(
            AnyView(LegalSupportView()),
            size: size,
            scheme: .light
        )
        let signature = imageSignature(
            name: "legal-support-overview",
            scheme: .light,
            bitmap: rendered.bitmap,
            png: rendered.png
        )

        XCTAssertEqual(signature.width, Int(size.width))
        XCTAssertEqual(signature.height, Int(size.height))
        XCTAssertGreaterThan(signature.pngByteCount, 2_000)
        XCTAssertGreaterThan(signature.sampledColorCount, 8)
        XCTAssertGreaterThan(signature.opaqueSampleFraction, 0.98)
        XCTAssertLessThan(signature.centralDominantColorFraction, 0.96)
        XCTAssertLessThan(signature.yellowPlaceholderFraction, 0.08)
    }

    func testBundledSupportMarkdownRendersAsStructuredDocument() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("SUPPORT.md"),
            encoding: .utf8
        )
        let size = CGSize(width: 720, height: 1_000)
        let rendered = try render(
            AnyView(
                ScrollView {
                    BundledMarkdownDocument(source: source)
                        .padding(32)
                }
                .background(Color(nsColor: .textBackgroundColor))
            ),
            size: size,
            scheme: .dark
        )
        let signature = imageSignature(
            name: "legal-support-formatted",
            scheme: .dark,
            bitmap: rendered.bitmap,
            png: rendered.png
        )

        XCTAssertEqual(signature.width, Int(size.width))
        XCTAssertEqual(signature.height, Int(size.height))
        XCTAssertGreaterThan(signature.pngByteCount, 8_000)
        XCTAssertGreaterThan(signature.sampledColorCount, 8)
        XCTAssertGreaterThan(signature.opaqueSampleFraction, 0.98)
        XCTAssertLessThan(signature.centralDominantColorFraction, 0.96)
        XCTAssertLessThan(signature.yellowPlaceholderFraction, 0.08)

        let output = try snapshotOutputDirectory()
            .appendingPathComponent("legal-support-formatted-dark.png")
        try rendered.png.write(to: output, options: .atomic)
    }

    func testCoreSurfaceAccessibilityContracts() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(
            TranslationTextIntakeView.accessibilityIdentifier,
            "translation-text-intake-sheet"
        )
        XCTAssertEqual(
            TranslationTextIntakeView.sourceProgressAccessibilityIdentifier,
            "translation-text-source-progress"
        )
        XCTAssertEqual(
            TranslationTextIntakeView.targetSectionAccessibilityIdentifier,
            "translation-text-target-section"
        )
        XCTAssertEqual(
            TranslationTextIntakeView.targetProgressAccessibilityIdentifier,
            "translation-text-target-progress"
        )
        XCTAssertEqual(
            TranslationTextIntakeView.targetRowAccessibilityIdentifier("line-0001"),
            "translation-text-target-row-line-0001"
        )
        XCTAssertEqual(
            TranslationTextIntakeView.targetFieldAccessibilityIdentifier("line-0001"),
            "translation-text-target-field-line-0001"
        )
        XCTAssertEqual(
            TranslationTextIntakeView.targetReviewAccessibilityIdentifier("line-0001"),
            "translation-text-target-review-line-0001"
        )
        XCTAssertEqual(
            TranslationTextIntakeView.targetClearAccessibilityIdentifier("line-0001"),
            "translation-text-target-clear-line-0001"
        )
        XCTAssertEqual(
            TranslationTextIntakeView.saveAccessibilityIdentifier,
            "translation-text-save-intake"
        )
        XCTAssertEqual(PlayerVideoActivityRecoveryCard.accessibilityIdentifier, "player-video-warning")
        XCTAssertEqual(
            PlayerVideoActivityRecoveryCard.dismissAccessibilityLabel,
            "Dismiss picture activity notice"
        )

        let stateStore = GameStateStore(
            rootURL: root.appendingPathComponent("contract-states")
        )
        let states = try timelineFixture(in: stateStore)
        let unavailable = try XCTUnwrap(states.first { $0.previewIssue != nil })
        let timelineCard = StateTimelineCard(
            state: unavailable,
            isQuickState: unavailable.isQuickState,
            isBusy: false,
            onLoad: {},
            onDelete: {}
        )
        XCTAssertTrue(
            timelineCard.accessibilityContractLabel.contains("Saved state from")
                && timelineCard.accessibilityContractLabel.contains("Preview Missing/Damaged")
        )
        XCTAssertEqual(StateTimelineView.accessibilityIdentifier, "state-timeline")

        let (comparison, _, pointerReport) = try ramFixture()
        let pointerLead = try XCTUnwrap(
            pointerReport.leadsWithReferences.first { $0.targetOffset == 0x0200 }
        )
        XCTAssertEqual(pointerLead.stableReferenceOffsets, [0x1000])
        XCTAssertEqual(
            Array(comparison.original[0x1000...0x1001]),
            [0x00, 0x02],
            "The pointer fixture must store target 0x0200 in little-endian order"
        )
        XCTAssertEqual(
            Int(comparison.original[0x1000]) | (Int(comparison.original[0x1001]) << 8),
            pointerLead.targetOffset
        )
        let pointerLeadLabel = CheckpointRAMInspectorView.pointerLeadAccessibilityLabel(
            targetAddress: address(pointerLead.targetOffset),
            change: pointerLead.textChangeKind.rawValue,
            originalCount: pointerLead.originalReferenceOffsets.count,
            patchedCount: pointerLead.patchedReferenceOffsets.count
        )
        XCTAssertTrue(pointerLeadLabel.contains("Near-pointer lead"))
        XCTAssertEqual(
            CheckpointRAMInspectorView.pointerLeadAccessibilityIdentifier(
                targetOffset: pointerLead.targetOffset
            ),
            "pointer-lead-512"
        )
        let sourceOffset = try XCTUnwrap(
            pointerLead.originalReferenceOffsets.first
                ?? pointerLead.patchedReferenceOffsets.first
        )
        let pointerAddressLabel = CheckpointRAMInspectorView.pointerAddressAccessibilityLabel(
            title: "Original",
            sourceAddress: address(sourceOffset),
            status: "Stable",
            targetAddress: address(pointerLead.targetOffset)
        )
        XCTAssertTrue(pointerAddressLabel.contains("Show in Bytes"))
        XCTAssertEqual(
            CheckpointRAMInspectorView.pointerReportAccessibilityIdentifier,
            "checkpoint-ram-pointer-leads"
        )
        XCTAssertEqual(
            CheckpointRAMInspectorView.textBufferReportAccessibilityIdentifier,
            "ram-text-buffer-report"
        )
        XCTAssertTrue(
            CheckpointRAMInspectorView.privateTextAccessibilityMessage.contains(
                "Decoded locally"
            )
        )

        let interactionMinimums = [
            PlayerVideoActivityRecoveryCard.minimumInteractiveDimension,
            StateTimelineView.minimumInteractiveDimension,
            StateTimelineCard.minimumInteractiveDimension,
            RewindTimeRibbonContent.minimumInteractiveDimension,
            TranslationVisualDivergenceView.minimumInteractiveDimension,
            CheckpointRAMInspectorView.minimumInteractiveDimension,
        ]
        XCTAssertTrue(interactionMinimums.allSatisfy { $0 >= 28 })
        XCTAssertEqual(
            RewindTimeRibbonContent.accessibilityIdentifier,
            "rewind-time-ribbon"
        )
        XCTAssertEqual(
            TranslationVisualDivergenceView.accessibilityIdentifier,
            "translation-first-visual-change"
        )
        XCTAssertEqual(PocketCoreSetupAccessibility.page, "pocket-core-setup")
        XCTAssertEqual(
            PocketCoreSetupAccessibility.checkRelease,
            "pocket-core-check-release"
        )
        XCTAssertEqual(
            PocketCoreSetupAccessibility.chooseCard,
            "pocket-core-choose-card"
        )
        XCTAssertEqual(
            PocketCoreSetupAccessibility.prepareCard,
            "pocket-core-prepare-card"
        )
        XCTAssertGreaterThanOrEqual(
            PocketCoreSetupAccessibility.minimumInteractiveDimension,
            28
        )
        XCTAssertEqual(GameConfidenceAccessibility.panel, "game-confidence-panel")
        XCTAssertEqual(
            GameConfidenceAccessibility.launchReadiness,
            "game-confidence-launch-readiness"
        )
        XCTAssertEqual(
            GameConfidenceAccessibility.compatibilityEvidence,
            "game-confidence-evidence"
        )
        XCTAssertEqual(
            GameConfidenceAccessibility.romIntegrity,
            "game-confidence-rom-integrity"
        )
        XCTAssertEqual(
            GameConfidenceAccessibility.verdictControls,
            "game-confidence-verdict-controls"
        )
        XCTAssertEqual(
            GameConfidenceAccessibility.verdictWorks,
            "game-confidence-verdict-works"
        )
        XCTAssertEqual(
            GameConfidenceAccessibility.verdictIssues,
            "game-confidence-verdict-issues"
        )
        XCTAssertEqual(
            GameConfidenceAccessibility.verdictClear,
            "game-confidence-verdict-clear"
        )
        XCTAssertEqual(GameConfidenceAccessibility.note, "game-confidence-note")
        XCTAssertEqual(GameConfidenceAccessibility.saveNote, "game-confidence-save-note")
        XCTAssertEqual(
            GameInspectorAccessibility.systemIdentity,
            "game-inspector-system-identity"
        )
        XCTAssertEqual(
            GameInspectorAccessibility.runtimeStatus,
            "game-inspector-runtime-status"
        )
        XCTAssertEqual(
            GameInspectorAccessibility.confidenceExplanations,
            "game-inspector-confidence-explanations"
        )
        XCTAssertEqual(
            GameInspectorAccessibility.gameDetails,
            "game-inspector-game-details"
        )
        XCTAssertEqual(
            GameInspectorAccessibility.pocketSave,
            "game-inspector-pocket-save"
        )
        XCTAssertEqual(
            GameInspectorAccessibility.pocketChallengeProgramFlash,
            "pocket-challenge-v2-program-flash"
        )
        XCTAssertEqual(
            SettingsSurfaceAccessibility.controllerMapping,
            "controller-mapping-settings"
        )
        XCTAssertEqual(
            SettingsSurfaceAccessibility.controllerLiveInput,
            "controller-live-input-disclosure"
        )
        XCTAssertEqual(
            SettingsSurfaceAccessibility.controllerCapabilityWarning,
            "controller-capability-warning"
        )
        XCTAssertGreaterThanOrEqual(
            SettingsSurfaceAccessibility.minimumInteractiveDimension,
            28
        )
        let stableCardID = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
        XCTAssertEqual(
            GameConfidenceAccessibility.card(stableCardID),
            "game-confidence-card-10000000-0000-0000-0000-000000000004"
        )
        XCTAssertEqual(
            GameConfidenceAccessibility.cardPrimaryAction(stableCardID),
            "game-card-primary-action-10000000-0000-0000-0000-000000000004"
        )
    }

    func testNativeUIControlAndReadinessContracts() {
        XCTAssertEqual(
            LCDMotionLevel.allCases.map(\.title),
            ["Off", "Natural", "Strong"]
        )
        XCTAssertEqual(
            LCDMotionLevel.allCases.map(\.responseScale),
            [0, 1, 1.5]
        )
        XCTAssertEqual(LCDMotionLevel.nearest(to: 0.2), .off)
        XCTAssertEqual(LCDMotionLevel.nearest(to: 0.8), .natural)
        XCTAssertEqual(LCDMotionLevel.nearest(to: 1.9), .strong)

        let wonderSwanHint = PlayerControlCopy.firstRunHint(for: .wonderSwan)
        let pocketChallengeHint = PlayerControlCopy.firstRunHint(
            for: .pocketChallengeV2
        )
        XCTAssertTrue(wonderSwanHint.contains("X pad"))
        XCTAssertFalse(pocketChallengeHint.contains("X pad"))
        XCTAssertTrue(pocketChallengeHint.contains("Pass/Circle/Clear"))
        XCTAssertTrue(pocketChallengeHint.contains("Escape"))
        XCTAssertEqual(SettingsView.migratedTab(0), 0)
        XCTAssertEqual(SettingsView.migratedTab(1), 1)
        XCTAssertEqual(SettingsView.migratedTab(2), 0)
        XCTAssertEqual(SettingsView.migratedTab(3), 3)
        XCTAssertEqual(SettingsView.migratedTab(-1), 0)
        XCTAssertTrue(AppModel.Section.allCases.contains(.pocketCore))
        XCTAssertEqual(AppModel.Section.pocketCore.rawValue, "Analogue Pocket")
        XCTAssertEqual(AppModel.Section.pocketCore.symbol, "sdcard")
    }

    func testPocketChallengeV2LibraryContracts() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try pocketChallengeV2UIFixture(
            root: root.appendingPathComponent("pocket-challenge-v2-contract")
        )

        XCTAssertEqual(fixture.game.resolvedHardwareModel, .pocketChallengeV2)
        XCTAssertEqual(fixture.game.systemTitle, "Pocket Challenge V2")
        XCTAssertEqual(fixture.game.sourceFileName, "Kana Quest Coach.pc2")
        XCTAssertEqual(
            fixture.model.gameConfidence(for: fixture.game),
            GameConfidence(
                launchReadiness: .ready,
                compatibility: .untested,
                romIntegrity: .unmanaged
            )
        )
    }

    func testGameConfidenceLibraryAndInspectorGeometry() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let preservedWindowPreferences = [
            "showsSidebar",
            "libraryWindowWidth",
            "libraryWindowHeight",
            "librarySortOption",
            "showsLibraryInspector",
        ].map { key in
            (key, UserDefaults.standard.object(forKey: key))
        }
        defer {
            for (key, value) in preservedWindowPreferences {
                restoreUserDefault(value, forKey: key)
            }
        }
        UserDefaults.standard.set(true, forKey: "showsSidebar")
        UserDefaults.standard.set(GameLibrarySortOrder.title.rawValue, forKey: "librarySortOption")

        let fixture = try gameConfidenceFixture(
            root: root.appendingPathComponent("game-confidence-geometry")
        )
        XCTAssertEqual(fixture.model.games.count, 4)
        XCTAssertEqual(
            fixture.model.gameConfidence(for: fixture.readyUntested),
            GameConfidence(
                launchReadiness: .ready,
                compatibility: .untested,
                romIntegrity: .unmanaged
            )
        )
        XCTAssertEqual(
            fixture.model.gameConfidence(for: fixture.reachedVideo),
            GameConfidence(
                launchReadiness: .ready,
                compatibility: .reachedVideo,
                romIntegrity: .unmanaged
            )
        )
        XCTAssertEqual(
            fixture.model.gameConfidence(for: fixture.colorReady),
            GameConfidence(
                launchReadiness: .ready,
                compatibility: .untested,
                romIntegrity: .unmanaged
            )
        )
        XCTAssertEqual(
            fixture.model.gameConfidence(for: fixture.reportedIssues),
            GameConfidence(
                launchReadiness: .ready,
                compatibility: .reportedIssues,
                romIntegrity: .unmanaged
            )
        )

        UserDefaults.standard.set(false, forKey: "showsLibraryInspector")
        let compactSize = CGSize(width: 820, height: 560)
        let compactHost = NSHostingView(
            rootView: RootView(
                model: fixture.model,
                usesDeterministicSidebarForOffscreenSnapshots: true
            )
            .environment(\.colorScheme, Scheme.light.colorScheme)
            .frame(width: compactSize.width, height: compactSize.height)
        )
        compactHost.frame = CGRect(origin: .zero, size: compactSize)
        let compactWindow = offscreenWindow(size: compactSize, scheme: .light)
        compactWindow.contentView = compactHost
        compactWindow.orderFront(nil)
        settle(window: compactWindow, host: compactHost)
        let compactInspectorScrolls = viewDescendants(of: compactHost, type: NSScrollView.self)
            .map { $0.convert($0.bounds, to: compactHost).standardized }
            .filter { frame in
                frame.intersects(compactHost.bounds)
                    && frame.midX > compactSize.width * 0.7
                    && (250...340).contains(frame.width)
                    && frame.height > 200
            }
        XCTAssertTrue(
            compactInspectorScrolls.isEmpty,
            "The compact library must keep the selected game's confidence inspector hidden"
        )
        compactWindow.orderOut(nil)
        compactWindow.contentView = nil
        compactWindow.close()

        UserDefaults.standard.set(true, forKey: "showsLibraryInspector")
        let wideGeometryProbe = GameConfidenceGeometryProbe()
        let wideSize = CGSize(width: 1_040, height: 680)
        let wideHost = NSHostingView(
            rootView: RootView(
                model: fixture.model,
                gameConfidenceGeometryProbe: wideGeometryProbe,
                usesDeterministicSidebarForOffscreenSnapshots: true
            )
            .environment(\.colorScheme, Scheme.light.colorScheme)
            .frame(width: wideSize.width, height: wideSize.height)
        )
        wideHost.frame = CGRect(origin: .zero, size: wideSize)
        let wideWindow = offscreenWindow(size: wideSize, scheme: .light)
        wideWindow.contentView = wideHost
        wideWindow.orderFront(nil)
        settle(window: wideWindow, host: wideHost)
        defer {
            wideWindow.orderOut(nil)
            wideWindow.contentView = nil
            wideWindow.close()
        }

        let expectedActions = [
            GameConfidenceAccessibility.verdictWorks: "Works",
            GameConfidenceAccessibility.verdictIssues: "Issues",
            GameConfidenceAccessibility.verdictClear: "Clear verdict",
            GameConfidenceAccessibility.saveNote: "Save Note",
        ]
        let inspectorScrollCandidates = viewDescendants(of: wideHost, type: NSScrollView.self)
            .map { scrollView in
                (
                    scrollView,
                    scrollView.convert(scrollView.bounds, to: wideHost).standardized
                )
            }
            .filter { _, frame in
                frame.midX > wideSize.width * 0.75 && frame.width > 200 && frame.height > 200
            }
        let inspectorScroll = try XCTUnwrap(
            inspectorScrollCandidates.max {
                $0.1.width * $0.1.height < $1.1.width * $1.1.height
            }?.0,
            "The wide Game Confidence inspector lost its scrollable container"
        )
        let scrollRange = verticalScrollRange(inspectorScroll)
        var reachableActions = Set<String>()
        let initialOrigin = inspectorScroll.contentView.bounds.origin
        for step in 0...20 {
            let progress = CGFloat(step) / 20
            inspectorScroll.contentView.scroll(
                to: CGPoint(x: initialOrigin.x, y: scrollRange * progress)
            )
            inspectorScroll.reflectScrolledClipView(inspectorScroll.contentView)
            settle(window: wideWindow, host: wideHost)
            let viewport = wideGeometryProbe.viewportFrame.insetBy(dx: -1, dy: -1)
            for (identifier, frame) in wideGeometryProbe.actionFrames {
                guard expectedActions[identifier] != nil else { continue }
                let actionFrame = frame.standardized
                XCTAssertGreaterThanOrEqual(
                    actionFrame.width,
                    28 - 0.01,
                    "\(expectedActions[identifier] ?? identifier) is narrower than 28 points"
                )
                XCTAssertGreaterThanOrEqual(
                    actionFrame.height,
                    28 - 0.01,
                    "\(expectedActions[identifier] ?? identifier) is shorter than 28 points"
                )
                if viewport.contains(actionFrame) {
                    reachableActions.insert(identifier)
                }
            }
        }
        inspectorScroll.contentView.scroll(to: initialOrigin)
        inspectorScroll.reflectScrolledClipView(inspectorScroll.contentView)
        settle(window: wideWindow, host: wideHost)
        XCTAssertEqual(
            Set(wideGeometryProbe.actionFrames.keys),
            Set(expectedActions.keys),
            "The wide Game Confidence inspector must expose every stable action AX identifier"
        )
        XCTAssertEqual(
            reachableActions,
            Set(expectedActions.keys),
            "Every Game Confidence verdict/note action must scroll fully into the wide inspector viewport"
        )
    }

    func testCompactTranslationOverviewWorkflowIsReachable() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let translationProjectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SwanSong-UIRegression-TranslationOverview-Geometry",
                isDirectory: true
            )
        try resetTemporaryDirectory(translationProjectRoot)
        defer { try? FileManager.default.removeItem(at: translationProjectRoot) }
        let preservedWindowPreferences = [
            "showsSidebar",
            "libraryWindowWidth",
            "libraryWindowHeight",
        ].map { key in
            (key, UserDefaults.standard.object(forKey: key))
        }
        UserDefaults.standard.set(true, forKey: "showsSidebar")
        defer {
            for (key, value) in preservedWindowPreferences {
                restoreUserDefault(value, forKey: key)
            }
        }

        let model = try translationOverviewModel(
            dataRoot: root.appendingPathComponent("translation-overview-model"),
            projectRoot: translationProjectRoot
        )
        let compactSize = CGSize(width: 820, height: 560)

        XCTAssertEqual(
            TranslationLabOverviewAccessibility.page,
            "translation-overview-page"
        )
        XCTAssertEqual(
            TranslationLabOverviewAccessibility.workflow,
            "translation-lab-overview-workflow"
        )
        XCTAssertEqual(
            TranslationLabOverviewAccessibility.workflowLabel,
            "Deterministic route testing workflow"
        )
        XCTAssertEqual(
            TranslationLabOverviewAccessibility.readinessMetrics,
            "translation-lab-overview-readiness-metrics"
        )
        XCTAssertEqual(
            TranslationLabOverviewAccessibility.currentAction,
            "translation-lab-overview-current-action"
        )
        XCTAssertEqual(
            TranslationLabOverviewAccessibility.currentActionLabel,
            "Current route testing action"
        )
        XCTAssertEqual(
            TranslationLabOverviewAccessibility.recordTest,
            "translation-lab-overview-record-test"
        )
        XCTAssertEqual(
            TranslationLabOverviewAccessibility.findFirstChange,
            "translation-lab-overview-find-first-change"
        )
        XCTAssertEqual(
            TranslationLabOverviewAccessibility.verifyRoute,
            "translation-lab-overview-verify-route"
        )
        XCTAssertEqual(
            TranslationLabOverviewAccessibility.refreshReadiness,
            "translation-lab-overview-refresh-readiness"
        )
        for number in 1...4 {
            XCTAssertEqual(
                TranslationLabOverviewAccessibility.workflowStep("\(number)"),
                "translation-lab-overview-workflow-step-\(number)"
            )
        }

        try expectCompactTranslationOverviewGeometry(
            model: model,
            size: compactSize,
            actionExpectations: [
                TranslationLabOverviewAccessibility.recordTest: "Record New Test…",
            ]
        )

        model.latestTranslationRoute = try translationOverviewRoute()
        try expectCompactTranslationOverviewGeometry(
            model: model,
            size: compactSize,
            actionExpectations: [
                TranslationLabOverviewAccessibility.findFirstChange: "Find First Change",
                TranslationLabOverviewAccessibility.verifyRoute: "Verify Original vs Patched",
            ]
        )
    }

    func testPlayerCanvasPreservesAllFourFrameCorners() throws {
        let frame = try playerRegressionFrame(
            width: 224,
            height: 157,
            isVertical: false,
            number: 450
        )
        let size = CGSize(width: 456, height: 322)
        let rendered = try render(
            AnyView(playerCanvasSurface(frame: frame, scale: 2)),
            size: size,
            scheme: .dark
        )
        // NSBitmapImageRep coordinates are backing pixels while `size` and the
        // SwiftUI padding above are points. Sample the same six-point inset on
        // both 1x and Retina hosts instead of accidentally reading the chrome.
        let backingScaleX = CGFloat(rendered.bitmap.pixelsWide) / size.width
        let backingScaleY = CGFloat(rendered.bitmap.pixelsHigh) / size.height
        let insetX = max(1, Int((6 * backingScaleX).rounded()))
        let insetY = max(1, Int((6 * backingScaleY).rounded()))
        let samples = [
            (insetX, insetY),
            (rendered.bitmap.pixelsWide - insetX - 1, insetY),
            (insetX, rendered.bitmap.pixelsHigh - insetY - 1),
            (
                rendered.bitmap.pixelsWide - insetX - 1,
                rendered.bitmap.pixelsHigh - insetY - 1
            ),
        ].compactMap { x, y in
            rendered.bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
        }
        XCTAssertEqual(samples.count, 4)
        XCTAssertTrue(
            samples.allSatisfy { color in
                max(
                    color.redComponent,
                    max(color.greenComponent, color.blueComponent)
                ) > 0.72
            },
            "The canvas rounded, clipped, dimmed, or drew chrome over an active framebuffer corner"
        )
        let buckets = Set(samples.map { color in
            "\(Int((color.redComponent * 7).rounded()))-\(Int((color.greenComponent * 7).rounded()))-\(Int((color.blueComponent * 7).rounded()))"
        })
        XCTAssertGreaterThanOrEqual(
            buckets.count,
            3,
            "Distinct framebuffer corner markers were lost or replaced by canvas chrome"
        )
    }

    func testDismissedVideoActivityRemainsDegradedAndRearms() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root.appendingPathComponent("video-activity"))
        let initialThreshold = FrameActivityMonitor().attentionThreshold
        var frameNumber: UInt64 = 0

        for _ in 0..<initialThreshold {
            frameNumber += 1
            _ = model.observePlayerVideoActivity(flatPlayerFrame(number: frameNumber))
        }
        XCTAssertTrue(model.playerVideoActivityIsDegraded)
        XCTAssertTrue(model.playerVideoActivityNeedsAttention)
        XCTAssertEqual(model.playerVideoActivityIssue, .flatColor)

        model.dismissPlayerVideoActivityDiagnostic()
        XCTAssertTrue(
            model.playerVideoActivityIsDegraded,
            "Dismissing the card must not report a persistently flat picture as healthy Playing"
        )
        XCTAssertFalse(model.playerVideoActivityNeedsAttention)
        XCTAssertEqual(model.playerVideoActivityIssue, .flatColor)

        let rearmThreshold = PlayerVideoActivityDiagnosticState
            .defaultWarningRearmFrameThreshold
        for _ in 1..<rearmThreshold {
            frameNumber += 1
            _ = model.observePlayerVideoActivity(flatPlayerFrame(number: frameNumber))
            XCTAssertTrue(
                model.playerVideoActivityIsDegraded,
                "Continued flat frames returned the player to healthy Playing"
            )
            XCTAssertFalse(
                model.playerVideoActivityNeedsAttention,
                "The warning reappeared before its dismissal backoff elapsed"
            )
        }

        frameNumber += 1
        _ = model.observePlayerVideoActivity(flatPlayerFrame(number: frameNumber))
        XCTAssertTrue(model.playerVideoActivityIsDegraded)
        XCTAssertTrue(
            model.playerVideoActivityNeedsAttention,
            "Persistent flat video did not re-arm its recovery card"
        )

        frameNumber += 1
        _ = model.observePlayerVideoActivity(
            try playerRegressionFrame(
                width: 224,
                height: 157,
                isVertical: false,
                number: frameNumber
            )
        )
        XCTAssertFalse(
            model.playerVideoActivityIsDegraded,
            "Meaningful picture motion did not clear the latched activity issue"
        )
        XCTAssertFalse(model.playerVideoActivityNeedsAttention)
        XCTAssertNil(model.playerVideoActivityIssue)
    }

    func testCompactRewindTimeRibbonFitsWithoutVerticalOverflow() throws {
        let checkpoints = try rewindFixture()
        let selected = try XCTUnwrap(
            checkpoints.first { $0.frameNumber == 75 }
        )
        let size = CGSize(width: 760, height: 500)
        let geometryProbe = RewindTimeRibbonGeometryProbe()
        let content = AnyView(
            RewindTimeRibbonContent(
                checkpoints: checkpoints,
                selectedID: .constant(selected.id),
                isBusy: false,
                canResume: true,
                onCancel: {},
                onResume: {},
                geometryProbe: geometryProbe
            )
            .environment(\.colorScheme, Scheme.light.colorScheme)
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        )
        let host = NSHostingView(rootView: content)
        host.frame = CGRect(origin: .zero, size: size)
        let window = offscreenWindow(size: size, scheme: .light)
        window.contentView = host
        window.orderFront(nil)
        settle(window: window, host: host)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }

        XCTAssertFalse(
            geometryProbe.usesVerticalFallback,
            "760×500 should use the fitted compact ribbon, not its smaller-window scroll fallback"
        )
        XCTAssertEqual(geometryProbe.viewportFrame.size, size)

        let identifiers = [
            "rewind-preview",
            "rewind-resume",
            "rewind-checkpoint-\(selected.id)",
            "rewind-footer",
        ]
        for identifier in identifiers {
            let frame = try XCTUnwrap(
                geometryProbe.elementFrames[identifier],
                "Missing geometry for \(identifier)"
            )
            XCTAssertGreaterThan(frame.height, 0, "\(identifier) has no visible height")
            XCTAssertGreaterThanOrEqual(
                frame.minY,
                geometryProbe.viewportFrame.minY - 0.5,
                "\(identifier) extends above the compact ribbon viewport"
            )
            XCTAssertLessThanOrEqual(
                frame.maxY,
                geometryProbe.viewportFrame.maxY + 0.5,
                "\(identifier) extends below the compact ribbon viewport"
            )
        }

        let verticalOverflow = viewDescendants(of: host, type: NSScrollView.self)
            .map(verticalScrollRange)
            .max() ?? 0
        XCTAssertLessThanOrEqual(
            verticalOverflow,
            0.5,
            "The compact Time Ribbon still has a vertical scroll range"
        )
    }

    func testCompactTimelineActionsAreVerticallyReachable() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let stateStore = GameStateStore(rootURL: root.appendingPathComponent("States"))
        let model = makeModel(root: root, stateStore: stateStore)
        model.timelineStates = try timelineFixture(in: stateStore)
        let firstState = try XCTUnwrap(model.timelineStates.first)
        let loadIdentifier = "state-load-\(firstState.id.uuidString.lowercased())"
        let deleteIdentifier = "state-delete-\(firstState.id.uuidString.lowercased())"
        let size = CGSize(width: 760, height: 430)
        let geometryProbe = StateTimelineGeometryProbe()
        let content = AnyView(
            StateTimelineView(model: model, geometryProbe: geometryProbe)
                .environment(\.colorScheme, Scheme.light.colorScheme)
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
        )
        let host = NSHostingView(rootView: content)
        host.frame = CGRect(origin: .zero, size: size)
        let window = offscreenWindow(size: size, scheme: .light)
        window.contentView = host
        window.orderFront(nil)
        settle(window: window, host: host)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }

        let initialLoadFrame = try XCTUnwrap(geometryProbe.actionFrames[loadIdentifier])
        let initialDeleteFrame = try XCTUnwrap(geometryProbe.actionFrames[deleteIdentifier])
        try expectUsableActionFrame(initialLoadFrame, label: loadIdentifier)
        try expectUsableActionFrame(initialDeleteFrame, label: deleteIdentifier)

        let timelineScroll = try XCTUnwrap(
            viewDescendants(of: host, type: NSScrollView.self).max { lhs, rhs in
                verticalScrollRange(lhs) < verticalScrollRange(rhs)
            }
        )
        XCTAssertTrue(timelineScroll.hasVerticalScroller)
        XCTAssertGreaterThan(
            verticalScrollRange(timelineScroll),
            0,
            "the compact timeline has no vertical path to its clipped card actions"
        )
        XCTAssertFalse(
            geometryProbe.viewportFrame.contains(initialLoadFrame),
            "the compact fixture no longer exercises the overflowing action row"
        )

        timelineScroll.contentView.scroll(
            to: CGPoint(
                x: timelineScroll.contentView.bounds.minX,
                y: verticalScrollRange(timelineScroll)
            )
        )
        timelineScroll.reflectScrolledClipView(timelineScroll.contentView)
        settle(window: window, host: host)

        let scrolledLoadFrame = try XCTUnwrap(geometryProbe.actionFrames[loadIdentifier])
        let scrolledDeleteFrame = try XCTUnwrap(geometryProbe.actionFrames[deleteIdentifier])
        XCTAssertTrue(
            geometryProbe.viewportFrame.contains(scrolledLoadFrame),
            "Load State cannot be scrolled fully into the compact timeline viewport"
        )
        XCTAssertTrue(
            geometryProbe.viewportFrame.contains(scrolledDeleteFrame),
            "Delete State cannot be scrolled fully into the compact timeline viewport"
        )
    }

    func testPerceptualHashDistanceMath() throws {
        let clear = String(repeating: "00", count: 32)
        let oneBit = "80" + String(repeating: "00", count: 31)
        let filled = String(repeating: "ff", count: 32)
        XCTAssertEqual(try hammingDistance(clear, clear), 0)
        XCTAssertEqual(try hammingDistance(clear, oneBit), 1)
        XCTAssertEqual(try hammingDistance(clear, filled), 256)
        XCTAssertLessThan(Self.maximumPerceptualHammingDistance, 256 / 10)
    }

    private func makeScenarios(
        root: URL,
        translationProjectRoot: URL
    ) throws -> [Scenario] {
        let stateRoot = root.appendingPathComponent("timeline")
        let stateStore = GameStateStore(rootURL: stateRoot.appendingPathComponent("States"))
        let timelineModel = makeModel(root: stateRoot, stateStore: stateStore)
        timelineModel.timelineStates = try timelineFixture(in: stateStore)

        let (comparison, report, pointerReport) = try ramFixture()
        let rewindCheckpoints = try rewindFixture()
        let firstChangeModel = makeModel(root: root.appendingPathComponent("first-change"))
        firstChangeModel.translationVisualDivergenceResult = try firstVisualChangeFixture()
        let firstChangeProgressModel = makeModel(
            root: root.appendingPathComponent("first-change-progress")
        )
        firstChangeProgressModel.translationVisualDivergenceIsRunning = true
        firstChangeProgressModel.translationVisualDivergenceProgress = .init(
            phase: .patched,
            framesProcessed: 2_640,
            totalFrames: 4_923,
            firstDifferenceFrameIndex: 2_511
        )
        let noChangeModel = makeModel(root: root.appendingPathComponent("no-change"))
        noChangeModel.translationVisualDivergenceResult = try noVisualChangeFixture()
        let horizontalPlayerFrame = try playerRegressionFrame(
            width: 224,
            height: 157,
            isVertical: false,
            number: 4_923
        )
        let verticalPlayerFrame = try playerRegressionFrame(
            width: 157,
            height: 224,
            isVertical: true,
            number: 4_923
        )
        let translationOverviewModel = try translationOverviewModel(
            dataRoot: root.appendingPathComponent("translation-overview"),
            projectRoot: translationProjectRoot
        )
        let translationTextIntakeModel = try translationTextIntakeModel(
            dataRoot: root.appendingPathComponent("translation-text-intake"),
            projectRoot: root.appendingPathComponent(
                "translation-text-intake-project",
                isDirectory: true
            )
        )
        let translationTextDraftingModel = try translationTextDraftingModel(
            dataRoot: root.appendingPathComponent("translation-text-drafting"),
            projectRoot: root.appendingPathComponent(
                "translation-text-drafting-project",
                isDirectory: true
            )
        )
        let confidenceFixture = try gameConfidenceFixture(
            root: root.appendingPathComponent("game-confidence")
        )
        let pocketChallengeFixture = try pocketChallengeV2UIFixture(
            root: root.appendingPathComponent("pocket-challenge-v2")
        )

        return [
            Scenario(name: "player-recovery-compact", size: CGSize(width: 560, height: 220)) {
                AnyView(self.playerRecoverySurface)
            },
            Scenario(name: "player-recovery-wide", size: CGSize(width: 980, height: 170)) {
                AnyView(self.playerRecoverySurface)
            },
            Scenario(name: "state-timeline-compact", size: CGSize(width: 760, height: 430)) {
                AnyView(StateTimelineView(model: timelineModel))
            },
            Scenario(name: "state-timeline-wide", size: CGSize(width: 1_040, height: 520)) {
                AnyView(StateTimelineView(model: timelineModel))
            },
            Scenario(name: "ram-text-buffers-compact", size: CGSize(width: 980, height: 680)) {
                AnyView(self.ramInspector(
                    comparison: comparison,
                    report: report,
                    pointerReport: pointerReport,
                    mode: .textBuffers
                ))
            },
            Scenario(name: "ram-text-buffers-wide", size: CGSize(width: 1_180, height: 760)) {
                AnyView(self.ramInspector(
                    comparison: comparison,
                    report: report,
                    pointerReport: pointerReport,
                    mode: .textBuffers
                ))
            },
            Scenario(name: "ram-pointer-leads-compact", size: CGSize(width: 980, height: 680)) {
                AnyView(self.ramInspector(
                    comparison: comparison,
                    report: report,
                    pointerReport: pointerReport,
                    mode: .pointerLeads
                ))
            },
            Scenario(name: "ram-pointer-leads-wide", size: CGSize(width: 1_180, height: 760)) {
                AnyView(self.ramInspector(
                    comparison: comparison,
                    report: report,
                    pointerReport: pointerReport,
                    mode: .pointerLeads
                ))
            },
            Scenario(name: "rewind-time-ribbon-compact", size: CGSize(width: 760, height: 500)) {
                AnyView(self.rewindRibbonSurface(checkpoints: rewindCheckpoints))
            },
            Scenario(name: "rewind-time-ribbon-wide", size: CGSize(width: 1_040, height: 620)) {
                AnyView(self.rewindRibbonSurface(checkpoints: rewindCheckpoints))
            },
            Scenario(name: "first-visual-change-compact", size: CGSize(width: 760, height: 560)) {
                AnyView(TranslationVisualDivergenceView(model: firstChangeModel))
            },
            Scenario(name: "first-visual-change-wide", size: CGSize(width: 1_040, height: 700)) {
                AnyView(TranslationVisualDivergenceView(model: firstChangeModel))
            },
            Scenario(name: "first-visual-change-progress-compact", size: CGSize(width: 760, height: 560)) {
                AnyView(TranslationVisualDivergenceView(model: firstChangeProgressModel))
            },
            Scenario(name: "first-visual-change-progress-wide", size: CGSize(width: 1_040, height: 700)) {
                AnyView(TranslationVisualDivergenceView(model: firstChangeProgressModel))
            },
            Scenario(name: "first-visual-change-none-compact", size: CGSize(width: 760, height: 560)) {
                AnyView(TranslationVisualDivergenceView(model: noChangeModel))
            },
            Scenario(name: "first-visual-change-none-wide", size: CGSize(width: 1_040, height: 700)) {
                AnyView(TranslationVisualDivergenceView(model: noChangeModel))
            },
            Scenario(name: "translation-overview-compact", size: CGSize(width: 820, height: 560)) {
                AnyView(
                    RootView(
                        model: translationOverviewModel,
                        usesDeterministicSidebarForOffscreenSnapshots: true
                    )
                )
            },
            Scenario(name: "translation-overview-wide", size: CGSize(width: 1_040, height: 680)) {
                AnyView(
                    RootView(
                        model: translationOverviewModel,
                        usesDeterministicSidebarForOffscreenSnapshots: true
                    )
                )
            },
            Scenario(
                name: "translation-text-intake",
                size: CGSize(width: 980, height: 720),
                usesPolishOutput: true
            ) {
                AnyView(TranslationTextIntakeView(model: translationTextIntakeModel))
            },
            Scenario(
                name: "translation-text-drafting-wide",
                size: CGSize(width: 980, height: 720),
                usesPolishOutput: true
            ) {
                AnyView(TranslationTextIntakeView(model: translationTextDraftingModel))
            },
            Scenario(
                name: "translation-text-drafting-compact",
                size: CGSize(width: 680, height: 760),
                usesPolishOutput: true
            ) {
                AnyView(TranslationTextIntakeView(model: translationTextDraftingModel))
            },
            Scenario(name: "game-confidence-compact", size: CGSize(width: 820, height: 560)) {
                UserDefaults.standard.set(false, forKey: "showsLibraryInspector")
                return AnyView(
                    RootView(
                        model: confidenceFixture.model,
                        usesDeterministicSidebarForOffscreenSnapshots: true
                    )
                )
            },
            Scenario(name: "game-confidence-wide", size: CGSize(width: 1_040, height: 680)) {
                UserDefaults.standard.set(true, forKey: "showsLibraryInspector")
                return AnyView(
                    RootView(
                        model: confidenceFixture.model,
                        usesDeterministicSidebarForOffscreenSnapshots: true
                    )
                )
            },
            Scenario(name: "pocket-challenge-v2-compact", size: CGSize(width: 820, height: 560)) {
                UserDefaults.standard.set(false, forKey: "showsLibraryInspector")
                return AnyView(
                    RootView(
                        model: pocketChallengeFixture.model,
                        usesDeterministicSidebarForOffscreenSnapshots: true
                    )
                )
            },
            Scenario(
                name: "pocket-challenge-v2-wide",
                size: CGSize(width: 1_040, height: 680),
                prepare: { host, _ in
                    self.scrollLibraryInspectorToBottom(in: host)
                }
            ) {
                UserDefaults.standard.set(true, forKey: "showsLibraryInspector")
                return AnyView(
                    RootView(
                        model: pocketChallengeFixture.model,
                        usesDeterministicSidebarForOffscreenSnapshots: true
                    )
                )
            },
            Scenario(name: "pocket-core-setup-compact", size: CGSize(width: 820, height: 560)) {
                AnyView(PocketCoreSetupView())
            },
            Scenario(name: "pocket-core-setup-wide", size: CGSize(width: 1_040, height: 680)) {
                AnyView(PocketCoreSetupView())
            },
            Scenario(
                name: "selected-game-inspector-compact",
                size: CGSize(width: 340, height: 620),
                usesPolishOutput: true
            ) {
                AnyView(
                    self.selectedGameInspectorSurface(
                        model: confidenceFixture.model,
                        game: confidenceFixture.reportedIssues
                    )
                )
            },
            Scenario(
                name: "selected-game-inspector-wide",
                size: CGSize(width: 420, height: 720),
                usesPolishOutput: true
            ) {
                AnyView(
                    self.selectedGameInspectorSurface(
                        model: confidenceFixture.model,
                        game: confidenceFixture.reportedIssues
                    )
                )
            },
            Scenario(
                name: "controller-mapping-settings-compact",
                size: CGSize(width: 640, height: 620),
                usesPolishOutput: true
            ) {
                UserDefaults.standard.set(1, forKey: "settingsPane")
                return AnyView(self.settingsSurface(model: confidenceFixture.model))
            },
            Scenario(
                name: "controller-mapping-settings-wide",
                size: CGSize(width: 980, height: 720),
                usesPolishOutput: true
            ) {
                UserDefaults.standard.set(1, forKey: "settingsPane")
                return AnyView(self.settingsSurface(model: confidenceFixture.model))
            },
            Scenario(name: "player-canvas-horizontal", size: CGSize(width: 760, height: 430)) {
                AnyView(self.playerCanvasSurface(frame: horizontalPlayerFrame, scale: 2))
            },
            Scenario(name: "player-canvas-vertical", size: CGSize(width: 520, height: 680)) {
                AnyView(self.playerCanvasSurface(frame: verticalPlayerFrame, scale: 2))
            },
        ]
    }

    private var playerRecoverySurface: some View {
        ZStack {
            SwanTheme.playerBackground
            PlayerVideoActivityRecoveryCard(
                headline: "Picture is not changing",
                detail: "Frames are arriving, but most of the picture is not changing. The game may simply be waiting for input. Try the controls first, then restart if it remains unchanged.",
                restartIsDisabled: false,
                onTryControls: {},
                onRestart: {},
                onDismiss: {}
            )
            .padding(20)
        }
    }

    private func selectedGameInspectorSurface(
        model: AppModel,
        game: GameRecord
    ) -> some View {
        GameInspector(
            game: game,
            artwork: model.gameArtwork[game.id],
            confidence: model.gameConfidence(for: game),
            canPlay: model.canPlayGame(game),
            managedHealth: model.managedGameHealth[game.id],
            isCheckingManagedCopy: model.checkingManagedGameIDs.contains(game.id),
            isRepairingManagedCopy: model.repairingGameID == game.id,
            canImportSave: model.canImportPocketSave,
            canExportSave: model.canExportPocketSave,
            onPlay: {},
            onRepair: {},
            onReAdd: {},
            onImportSave: {},
            onExportSave: {},
            onSetCompatibilityVerdict: { _ in },
            onSaveCompatibilityNote: { _ in },
            geometryProbe: nil
        )
        .background(SwanTheme.libraryBackground)
    }

    private func settingsSurface(model: AppModel) -> some View {
        SettingsView(model: model)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    private func rewindRibbonSurface(
        checkpoints: [RewindCheckpoint]
    ) -> some View {
        RewindTimeRibbonContent(
            checkpoints: checkpoints,
            selectedID: .constant(checkpoints.first { $0.frameNumber == 75 }?.id),
            isBusy: false,
            canResume: true,
            onCancel: {},
            onResume: {}
        )
    }

    @ViewBuilder
    private func playerCanvasSurface(
        frame: EngineVideoFrame,
        scale: CGFloat
    ) -> some View {
        ZStack {
            SwanTheme.playerBackground
            if let data = try? EngineFramePNGCodec.encode(frame),
               let image = NSImage(data: data) {
                PlayerCanvasFrame(
                    chromeColor: SwanTheme.cyan.opacity(0.46),
                    chromeLineWidth: 1.5
                ) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .frame(
                            width: CGFloat(frame.width) * scale,
                            height: CGFloat(frame.height) * scale
                        )
                }
            }
        }
    }

    private func rewindFixture() throws -> [RewindCheckpoint] {
        try stride(from: UInt64(0), through: 450, by: 75).map { frameNumber in
            try RewindCheckpoint(
                state: Data(
                    repeating: UInt8(truncatingIfNeeded: frameNumber / 75),
                    count: 2_048 + Int(frameNumber)
                ),
                previewFrame: playerRegressionFrame(
                    width: 224,
                    height: 157,
                    isVertical: false,
                    number: frameNumber
                )
            )
        }
    }

    private func firstVisualChangeFixture() throws -> TranslationVisualDivergenceResult {
        let original = try playerRegressionFrame(
            width: 224,
            height: 157,
            isVertical: false,
            number: 2_512
        )
        let patched = changedFrame(original, region: CGRect(x: 62, y: 48, width: 74, height: 28))
        let previousOriginal = try playerRegressionFrame(
            width: 224,
            height: 157,
            isVertical: false,
            number: 2_511
        )
        let currentPair = TranslationVisualComparedFrame(
            frameIndex: 2_511,
            inputMask: EngineInput.a.rawValue,
            frames: .init(original: original, patched: patched)
        )
        let previousPair = TranslationVisualComparedFrame(
            frameIndex: 2_510,
            inputMask: 0,
            frames: .init(original: previousOriginal, patched: previousOriginal)
        )
        let originalRaster = try TranslationRouteCheckpoint.canonicalGameRaster(original)
        let patchedRaster = try TranslationRouteCheckpoint.canonicalGameRaster(patched)
        let visualization = try FrameDifferential.visualizeRGB888(
            expected: originalRaster.rgb888(),
            actual: patchedRaster.rgb888(),
            width: originalRaster.descriptor.width,
            height: originalRaster.descriptor.height
        )
        return .firstDifference(
            TranslationVisualDivergence(
                kind: .pixels,
                frame: currentPair,
                previousIdenticalFrame: previousPair,
                originalRaster: originalRaster.descriptor,
                patchedRaster: patchedRaster.descriptor,
                visualization: visualization
            )
        )
    }

    private func noVisualChangeFixture() throws -> TranslationVisualDivergenceResult {
        let frame = try playerRegressionFrame(
            width: 224,
            height: 157,
            isVertical: false,
            number: 4_923
        )
        return .noDifference(
            TranslationVisualNoDifference(
                framesCompared: 4_923,
                lastIdenticalFrame: TranslationVisualComparedFrame(
                    frameIndex: 4_922,
                    inputMask: 0,
                    frames: .init(original: frame, patched: frame)
                )
            )
        )
    }

    private func changedFrame(_ frame: EngineVideoFrame, region: CGRect) -> EngineVideoFrame {
        var pixels = frame.pixels
        let minimumX = max(0, Int(region.minX))
        let maximumX = min(frame.width, Int(region.maxX))
        let minimumY = max(0, Int(region.minY))
        let maximumY = min(frame.height, Int(region.maxY))
        pixels.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for y in minimumY..<maximumY {
                for x in minimumX..<maximumX {
                    let offset = y * frame.strideBytes + x * 4
                    bytes[offset] = 236
                    bytes[offset + 1] = UInt8(48 + (x + y) % 44)
                    bytes[offset + 2] = 250
                    bytes[offset + 3] = 255
                }
            }
        }
        return EngineVideoFrame(
            pixels: pixels,
            width: frame.width,
            height: frame.height,
            strideBytes: frame.strideBytes,
            isVertical: frame.isVertical,
            number: frame.number
        )
    }

    private func playerRegressionFrame(
        width: Int,
        height: Int,
        isVertical: Bool,
        number: UInt64
    ) throws -> EngineVideoFrame {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let phase = Int(number % 251)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8((x * 2 + y + phase) % 176 + 24)
                pixels[offset + 1] = UInt8((y * 3 + phase / 2) % 164 + 28)
                pixels[offset + 2] = UInt8((x + y * 2 + phase) % 150 + 34)
                pixels[offset + 3] = 255
            }
        }

        func markCorner(
            xRange: Range<Int>,
            yRange: Range<Int>,
            red: UInt8,
            green: UInt8,
            blue: UInt8
        ) {
            for y in yRange {
                for x in xRange {
                    let offset = (y * width + x) * 4
                    pixels[offset] = blue
                    pixels[offset + 1] = green
                    pixels[offset + 2] = red
                    pixels[offset + 3] = 255
                }
            }
        }
        let marker = 10
        markCorner(
            xRange: 0..<marker,
            yRange: 0..<marker,
            red: 255,
            green: 36,
            blue: 50
        )
        markCorner(
            xRange: (width - marker)..<width,
            yRange: 0..<marker,
            red: 40,
            green: 242,
            blue: 92
        )
        markCorner(
            xRange: 0..<marker,
            yRange: (height - marker)..<height,
            red: 48,
            green: 102,
            blue: 255
        )
        markCorner(
            xRange: (width - marker)..<width,
            yRange: (height - marker)..<height,
            red: 255,
            green: 238,
            blue: 96
        )

        return EngineVideoFrame(
            pixels: Data(pixels),
            width: width,
            height: height,
            strideBytes: width * 4,
            isVertical: isVertical,
            number: number
        )
    }

    private func flatPlayerFrame(number: UInt64) -> EngineVideoFrame {
        let width = 224
        let height = 157
        var pixels = [UInt8](repeating: 0x20, count: width * height * 4)
        for alpha in stride(from: 3, to: pixels.count, by: 4) {
            pixels[alpha] = 255
        }
        return EngineVideoFrame(
            pixels: Data(pixels),
            width: width,
            height: height,
            strideBytes: width * 4,
            isVertical: false,
            number: number
        )
    }

    private func ramInspector(
        comparison: TranslationRAMComparison,
        report: TranslationRAMTextReport,
        pointerReport: TranslationRAMPointerReport,
        mode: TranslationRAMInspectorMode
    ) -> some View {
        CheckpointRAMInspectorView(
            comparison: comparison,
            issue: nil,
            textReport: report,
            textIssue: nil,
            pointerReport: pointerReport,
            pointerIssue: nil,
            isLoading: false,
            initialMode: mode
        )
    }

    private func makeModel(
        root: URL,
        stateStore: GameStateStore? = nil
    ) -> AppModel {
        AppModel(
            store: GameLibraryStore(fileURL: root.appendingPathComponent("Library.json")),
            saveStore: GameSaveStore(rootURL: root.appendingPathComponent("Saves")),
            stateStore: stateStore ?? GameStateStore(rootURL: root.appendingPathComponent("States")),
            managedGameStore: ManagedGameStore(rootURL: root.appendingPathComponent("Games")),
            artworkStore: GameArtworkStore(rootURL: root.appendingPathComponent("Artwork")),
            controllerProfileStore: ControllerProfileStore(
                fileURL: root.appendingPathComponent("ControllerProfile.json")
            ),
            translationWorkspaceStore: TranslationWorkspaceStore(
                fileURL: root.appendingPathComponent("TranslationWorkspace.json")
            )
        )
    }

    private func makeHomebrewModel(
        root: URL,
        consentGranted: Bool,
        catalog: HomebrewCatalog?,
        selectedEntryID: String? = nil
    ) -> AppModel {
        UserDefaults.standard.set(
            consentGranted,
            forKey: "SwanSong.homebrewCatalogConsent.v1"
        )
        let model = AppModel(
            store: GameLibraryStore(fileURL: root.appendingPathComponent("Library.json")),
            saveStore: GameSaveStore(rootURL: root.appendingPathComponent("Saves")),
            stateStore: GameStateStore(rootURL: root.appendingPathComponent("States")),
            managedGameStore: ManagedGameStore(rootURL: root.appendingPathComponent("Games")),
            homebrewCatalogURL: URL(string: "https://127.0.0.1:9/catalog-v1.json")!,
            homebrewCatalogCacheStore: HomebrewCatalogCacheStore(
                directoryURL: root.appendingPathComponent("HomebrewCache", isDirectory: true)
            ),
            homebrewCatalogSignatureVerifier: Self.snapshotCatalogVerifier,
            artworkStore: GameArtworkStore(rootURL: root.appendingPathComponent("Artwork")),
            controllerProfileStore: ControllerProfileStore(
                fileURL: root.appendingPathComponent("ControllerProfile.json")
            ),
            translationWorkspaceStore: TranslationWorkspaceStore(
                fileURL: root.appendingPathComponent("TranslationWorkspace.json")
            )
        )
        model.section = .homebrew
        model.homebrewCatalogConsentGranted = consentGranted
        model.homebrewCatalog = catalog
        model.homebrewCatalogLastUpdatedAt = catalog.map { _ in
            Date(timeIntervalSince1970: 1_750_000_600)
        }
        model.selectedHomebrewEntryID = selectedEntryID
        model.loadHomebrewCatalogIfNeeded()
        return model
    }

    private static let snapshotCatalogVerifier: HomebrewCatalogSignatureVerifier = {
        let privateKey = try! Curve25519.Signing.PrivateKey(
            rawRepresentation: Data(repeating: 0x5a, count: 32)
        )
        return HomebrewCatalogSignatureVerifier(
            trustedKeys: [
                HomebrewCatalogTrustedKey(
                    keyID: "snapshot-key",
                    rawPublicKey: privateKey.publicKey.rawRepresentation
                ),
            ]
        )
    }()

    private func homebrewCatalogFixture() -> HomebrewCatalog {
        let commit = String(repeating: "a", count: 40)
        let releasedAt = Date(timeIntervalSince1970: 1_749_900_000)

        func entry(
            id: String,
            title: String,
            summary: String,
            description: String,
            version: String,
            digestCharacter: Character
        ) -> HomebrewCatalogEntry {
            let tag = "\(id)-v\(version)"
            return HomebrewCatalogEntry(
                id: id,
                title: title,
                developer: "Regionally Famous",
                summary: summary,
                description: description,
                sourceURL: URL(
                    string: "https://github.com/RegionallyFamous/swansong-story-forge/tree/\(commit)/games/\(id)"
                )!,
                provenanceURL: URL(
                    string: "https://github.com/RegionallyFamous/swansong-story-forge/blob/\(commit)/games/\(id)/reports/release-report.json"
                )!,
                licenseName: "MIT License",
                licenseURL: URL(
                    string: "https://github.com/RegionallyFamous/swansong-story-forge/blob/\(commit)/LICENSE"
                )!,
                releases: [
                    HomebrewCatalogRelease(
                        version: version,
                        saveCompatibilityID: "\(id)-save-v1",
                        releasedAt: releasedAt,
                        releaseURL: URL(
                            string: "https://github.com/RegionallyFamous/swansong-story-forge/releases/tag/\(tag)"
                        )!,
                        asset: HomebrewCatalogAsset(
                            url: URL(
                                string: "https://github.com/RegionallyFamous/swansong-story-forge/releases/download/\(tag)/\(id).wsc"
                            )!,
                            byteCount: 128 * 1_024,
                            sha256: String(repeating: digestCharacter, count: 64),
                            fileExtension: "wsc",
                            hardwareModel: .wonderSwanColor
                        )
                    ),
                ]
            )
        }

        return HomebrewCatalog(
            catalogID: HomebrewCatalogValidator.firstPartyCatalogID,
            revision: 7,
            generatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            repositoryURL: HomebrewCatalogValidator.firstPartyRepositoryURL,
            entries: [
                entry(
                    id: "signal-before-dawn",
                    title: "Signal Before Dawn",
                    summary: "A short color adventure built for SwanSong.",
                    description: "Tune a pocket receiver, follow the lights across the harbor, and find the source of a signal that arrives just before sunrise.",
                    version: "1.0.0",
                    digestCharacter: "a"
                ),
                entry(
                    id: "backlight-bazaar",
                    title: "Backlight Bazaar",
                    summary: "A bright arcade score chase for WonderSwan Color.",
                    description: "Trade sparks, chain quick deliveries, and keep a tiny night market glowing until the last train leaves.",
                    version: "1.1.0",
                    digestCharacter: "b"
                ),
            ]
        )
    }

    private func gameConfidenceFixture(root: URL) throws -> GameConfidenceFixture {
        let readyUntested = GameRecord(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            title: "Aurora Circuit",
            fileURL: root.appendingPathComponent("aurora-circuit.ws"),
            metadata: try gameConfidenceMetadata(isColor: false, checksum: 0x1001),
            addedAt: Date(timeIntervalSince1970: 1_735_776_001),
            sourceFileName: "Aurora Circuit.ws"
        )
        let reachedVideo = GameRecord(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            title: "Blue Comet",
            fileURL: root.appendingPathComponent("blue-comet.ws"),
            metadata: try gameConfidenceMetadata(isColor: false, checksum: 0x2002),
            addedAt: Date(timeIntervalSince1970: 1_735_776_002),
            sourceFileName: "Blue Comet.ws",
            compatibilityEvidence: GameCompatibilityEvidence(
                reachedVideoAt: Date(timeIntervalSince1970: 1_735_862_400)
            )
        )
        let colorReady = GameRecord(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            title: "Color Signal",
            fileURL: root.appendingPathComponent("color-signal.wsc"),
            metadata: try gameConfidenceMetadata(isColor: true, checksum: 0x3003),
            addedAt: Date(timeIntervalSince1970: 1_735_776_003),
            sourceFileName: "Color Signal.wsc"
        )
        let reportedIssues = GameRecord(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
            title: "Pocket Relay",
            fileURL: root.appendingPathComponent("pocket-relay.ws"),
            metadata: try gameConfidenceMetadata(isColor: false, checksum: 0x4004),
            addedAt: Date(timeIntervalSince1970: 1_735_776_004),
            sourceFileName: "Pocket Relay.ws",
            compatibilityEvidence: GameCompatibilityEvidence(
                reachedVideoAt: Date(timeIntervalSince1970: 1_735_948_800),
                verdict: .issues,
                note: "Audio crackles after resuming from a saved moment.",
                updatedAt: Date(timeIntervalSince1970: 1_735_948_860)
            )
        )
        let games = [readyUntested, reachedVideo, colorReady, reportedIssues]
        let store = GameLibraryStore(fileURL: root.appendingPathComponent("Library.json"))
        try store.save(GameLibraryDocument(games: games))

        let model = AppModel(
            store: store,
            saveStore: GameSaveStore(rootURL: root.appendingPathComponent("Saves")),
            stateStore: GameStateStore(rootURL: root.appendingPathComponent("States")),
            managedGameStore: ManagedGameStore(rootURL: root.appendingPathComponent("Games")),
            artworkStore: GameArtworkStore(rootURL: root.appendingPathComponent("Artwork")),
            controllerProfileStore: ControllerProfileStore(
                fileURL: root.appendingPathComponent("ControllerProfile.json")
            ),
            translationWorkspaceStore: TranslationWorkspaceStore(
                fileURL: root.appendingPathComponent("TranslationWorkspace.json")
            ),
            engineCanExecuteOverride: true
        )
        model.section = .library
        model.selectedGameID = reportedIssues.id
        return GameConfidenceFixture(
            model: model,
            readyUntested: readyUntested,
            reachedVideo: reachedVideo,
            colorReady: colorReady,
            reportedIssues: reportedIssues
        )
    }

    private func pocketChallengeV2UIFixture(root: URL) throws -> PocketChallengeV2UIFixture {
        let game = GameRecord(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            title: "Kana Quest Coach",
            fileURL: root.appendingPathComponent("kana-quest-coach.pc2"),
            metadata: try gameConfidenceMetadata(
                isColor: false,
                checksum: 0x2C20,
                saveType: 0
            ),
            addedAt: Date(timeIntervalSince1970: 1_736_035_200),
            sourceFileName: "Kana Quest Coach.pc2",
            preferredHardwareModel: .pocketChallengeV2
        )
        let companion = GameRecord(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            title: "Aurora Circuit",
            fileURL: root.appendingPathComponent("aurora-circuit.ws"),
            metadata: try gameConfidenceMetadata(isColor: false, checksum: 0x2C21),
            isFavorite: true,
            addedAt: Date(timeIntervalSince1970: 1_736_035_201),
            sourceFileName: "Aurora Circuit.ws"
        )
        let store = GameLibraryStore(fileURL: root.appendingPathComponent("Library.json"))
        try store.save(GameLibraryDocument(games: [game, companion]))

        let model = AppModel(
            store: store,
            saveStore: GameSaveStore(rootURL: root.appendingPathComponent("Saves")),
            stateStore: GameStateStore(rootURL: root.appendingPathComponent("States")),
            managedGameStore: ManagedGameStore(rootURL: root.appendingPathComponent("Games")),
            artworkStore: GameArtworkStore(rootURL: root.appendingPathComponent("Artwork")),
            controllerProfileStore: ControllerProfileStore(
                fileURL: root.appendingPathComponent("ControllerProfile.json")
            ),
            translationWorkspaceStore: TranslationWorkspaceStore(
                fileURL: root.appendingPathComponent("TranslationWorkspace.json")
            ),
            engineCanExecuteOverride: true
        )
        model.section = .library
        model.selectedGameID = game.id
        return PocketChallengeV2UIFixture(model: model, game: game)
    }

    private func gameConfidenceMetadata(
        isColor: Bool,
        checksum: UInt16,
        saveType: UInt8 = 1
    ) throws -> ROMMetadata {
        let object: [String: Any] = [
            "fileSize": 128 * 1_024,
            "mappedSize": 128 * 1_024,
            "storedChecksum": Int(checksum),
            "computedChecksum": Int(checksum),
            "isColor": isColor,
            "saveType": Int(saveType),
            "mapper": 0,
            "romSizeCode": 1,
            "checksumIsValid": true,
            "footerIsValid": true,
            "usesCompactLayout": false,
            "hasRTC": false,
        ]
        return try JSONDecoder().decode(
            ROMMetadata.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
    }

    private func translationOverviewModel(
        dataRoot: URL,
        projectRoot: URL
    ) throws -> AppModel {
        let fileManager = FileManager.default
        let toolkitBin = projectRoot.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(
            at: toolkitBin,
            withIntermediateDirectories: true
        )
        try Data("// Synthetic UI regression toolkit marker.\n".utf8).write(
            to: toolkitBin.appendingPathComponent("wstrans.mjs"),
            options: [.atomic]
        )
        let projectConfiguration = #"""
        {
          "game": {
            "title": "Synthetic Translation Workspace",
            "platform": "WonderSwan Color",
            "sourceLanguage": "ja",
            "targetLanguage": "en"
          },
          "rom": {
            "original": "rom/original.ws",
            "patched": "build/patched.ws"
          }
        }
        """#
        try Data(projectConfiguration.utf8).write(
            to: projectRoot.appendingPathComponent("project.json"),
            options: [.atomic]
        )

        let project = try TranslationProject(projectDirectory: projectRoot)
        let model = makeModel(root: dataRoot)
        model.translationProjects = [project]
        model.translationProject = project
        model.section = .translationLab
        model.translationReadiness = TranslationReadiness(
            output: #"""
            Readiness: PENDING - synthetic workspace is ready for a deterministic route
            Strings: 558 extracted, 421 translated; table entries: 92; extractors: 3 fixed, 1 pointer
            COMPLETE Table: Character table is ready.
            COMPLETE Extraction: Fixed and pointer text sources are mapped.
            PENDING Localization: Review the remaining untranslated strings.
              Next: Continue the synthetic localization pass.
            COMPLETE Runtime QA: Public fixture checkpoints are configured.
            Next actions:
            - MEDIUM: Record a clean-boot route for the next screen.
              Use Record New Test in Translation Lab.
            """#
        )
        return model
    }

    private func translationOverviewRoute() throws -> TranslationRoute {
        let totalFrames: UInt64 = 30
        let frame = try playerRegressionFrame(
            width: 224,
            height: 157,
            isVertical: false,
            number: totalFrames
        )
        return try TranslationRoute(
            createdAt: Date(timeIntervalSince1970: 1_735_776_000),
            recordedFrom: .original,
            sourceROM: TranslationArtifactDigest(
                byteCount: 128 * 1_024,
                sha256: String(repeating: "a", count: 64)
            ),
            start: TranslationRouteStartContext(
                hardwareModel: .wonderSwan,
                firmware: TranslationRouteFirmware(
                    source: .openIPL,
                    identifier: WonderSwanOpenIPL.identifier
                ),
                engine: TranslationRouteEngineIdentity(
                    backend: "ares",
                    buildID: "ares-ui-regression"
                )
            ),
            totalFrames: totalFrames,
            events: [TranslationRouteEvent(frameIndex: 0, inputMask: 0)],
            checkpoint: try TranslationRouteCheckpoint(
                frameIndex: totalFrames - 1,
                frame: frame
            )
        )
    }

    private func translationTextIntakeModel(
        dataRoot: URL,
        projectRoot: URL
    ) throws -> AppModel {
        let model = try translationOverviewModel(
            dataRoot: dataRoot,
            projectRoot: projectRoot
        )
        let project = try XCTUnwrap(model.translationProject)
        let originalROM = project.rootURL
            .appendingPathComponent("rom", isDirectory: true)
            .appendingPathComponent("original.ws")
        let patchedROM = project.rootURL
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("patched.ws")
        try FileManager.default.createDirectory(
            at: originalROM.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: patchedROM.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let rom = Data(repeating: 0x5a, count: 128 * 1_024)
        try rom.write(to: originalROM, options: [.atomic])
        try rom.write(to: patchedROM, options: [.atomic])

        let store = TranslationEvidenceStore()
        _ = try store.capture(
            TranslationEvidenceInput(
                project: project,
                role: .original,
                romURL: originalROM,
                romFooterChecksum: 0,
                backend: "snapshot-fixture",
                frameNumber: 4_923,
                framePNG: try previewPNG(),
                state: Data(repeating: 0x21, count: 2_048),
                internalRAM: Data(repeating: 0x00, count: 64 * 1_024),
                route: nil
            )
        )
        model.translationEvidence = try store.listEvidence(project: project)
        model.selectedTranslationEvidenceID = try XCTUnwrap(model.translationEvidence.first?.id)
        model.beginTranslationTextIntake()
        model.useDialogueBandForTranslationTextIntake()
        model.translationTextIntakeManualDraft = "PRESS START"
        model.addManualTranslationTextIntakeLine()
        model.translationTextIntakeManualDraft = "はじめから"
        model.addManualTranslationTextIntakeLine()
        if let first = model.translationTextIntakeLines.first {
            model.confirmTranslationTextIntakeLine(first.id)
        }
        return model
    }

    private func translationTextDraftingModel(
        dataRoot: URL,
        projectRoot: URL
    ) throws -> AppModel {
        let model = try translationTextIntakeModel(
            dataRoot: dataRoot,
            projectRoot: projectRoot
        )
        model.confirmAllTranslationTextIntakeLines()
        model.saveTranslationTextIntake()

        let lines = model.translationDraftLines
        if let first = lines.first {
            model.updateTranslationDraftTarget(id: first.id, text: "Press Start")
            model.reviewTranslationDraftLine(first.id)
        }
        if lines.count > 1 {
            model.updateTranslationDraftTarget(id: lines[1].id, text: "New Game")
        }
        return model
    }

    private func timelineFixture(in store: GameStateStore) throws -> [GameStateSummary] {
        let gameID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let createdAt = Date(timeIntervalSince1970: 1_735_776_000)
        let expected = GameStateSessionIdentity(
            romChecksum: 0x1234,
            romSHA256: String(repeating: "1", count: 64),
            romByteCount: 128 * 1_024,
            firmwareSHA256: String(repeating: "2", count: 64),
            firmwareByteCount: 8 * 1_024,
            hardwareModel: .wonderSwanColor,
            isColor: true,
            backend: "snapshot-fixture",
            engineBuildID: "snapshot-engine-v1"
        )
        let mismatched = GameStateSessionIdentity(
            romChecksum: expected.romChecksum,
            romSHA256: expected.romSHA256,
            romByteCount: expected.romByteCount,
            firmwareSHA256: String(repeating: "3", count: 64),
            firmwareByteCount: expected.firmwareByteCount,
            hardwareModel: expected.hardwareModel,
            isColor: expected.isColor,
            backend: expected.backend,
            engineBuildID: expected.engineBuildID
        )
        let preview = try previewPNG()
        let mismatchedState = Data(repeating: 0x11, count: 1_024)
        let healthyState = Data(repeating: 0x22, count: 2_048)
        let damagedState = Data(repeating: 0x33, count: 4_096)
        let mismatchedManifest = GameStateManifest(
            generation: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            createdAt: createdAt,
            sessionIdentity: mismatched,
            frameNumber: 1_240,
            state: mismatchedState,
            previewPNG: preview
        )
        let healthyManifest = GameStateManifest(
            generation: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            createdAt: createdAt,
            sessionIdentity: expected,
            frameNumber: 2_480,
            state: healthyState,
            previewPNG: preview
        )
        let damagedManifest = GameStateManifest(
            generation: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            createdAt: createdAt,
            sessionIdentity: expected,
            frameNumber: 3_720,
            state: damagedState,
            previewPNG: preview
        )
        let directory = store.rootURL.appendingPathComponent(
            gameID.uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let fixtures: [(GameStateManifest, Data, Data)] = [
            (damagedManifest, damagedState, Data([0x00, 0x01, 0x02])),
            (healthyManifest, healthyState, preview),
            (mismatchedManifest, mismatchedState, preview),
        ]
        for (manifest, state, previewData) in fixtures {
            let base = manifest.generation.uuidString
            try state.write(
                to: directory.appendingPathComponent("\(base).state"),
                options: [.atomic]
            )
            try previewData.write(
                to: directory.appendingPathComponent("\(base).png"),
                options: [.atomic]
            )
        }
        let document = SnapshotTimelineDocument(
            schemaVersion: 2,
            entries: fixtures.map(\.0),
            quickGeneration: damagedManifest.generation
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(
            to: directory.appendingPathComponent("Timeline.json"),
            options: [.atomic]
        )
        return try store.listStates(gameID: gameID, sessionIdentity: expected)
    }

    private func previewPNG() throws -> Data {
        let width = 224
        let height = 144
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8((x * 3) % 255)
                pixels[offset + 1] = UInt8((y * 4) % 255)
                pixels[offset + 2] = UInt8((x + y) % 255)
                pixels[offset + 3] = 255
            }
        }
        return try EngineFramePNGCodec.encode(
            EngineVideoFrame(
                pixels: Data(pixels),
                width: width,
                height: height,
                strideBytes: width * 4,
                isVertical: false,
                number: 1
            )
        )
    }

    private func ramFixture() throws -> (
        TranslationRAMComparison,
        TranslationRAMTextReport,
        TranslationRAMPointerReport
    ) {
        var original = Data(repeating: 0, count: 16 * 1_024)
        var patched = original
        write("PRESS START", at: 0x0200, into: &original)
        write("PRESS BEGIN", at: 0x0200, into: &patched)
        write("ITEM POTION", at: 0x0400, into: &original)
        write("ITEM ELIXIR", at: 0x0400, into: &patched)
        write("OLD DEBUG MENU", at: 0x0600, into: &original)
        write("NEW QUEST LOG", at: 0x0800, into: &patched)

        // WonderSwan V30MZ pointers are little-endian. Exercise stable,
        // removed, and added references into the changed text buffers.
        writePointer(to: 0x0200, at: 0x1000, into: &original)
        writePointer(to: 0x0200, at: 0x1000, into: &patched)
        writePointer(to: 0x0400, at: 0x1010, into: &original)
        writePointer(to: 0x0400, at: 0x1020, into: &patched)
        writePointer(to: 0x0600, at: 0x1030, into: &original)
        writePointer(to: 0x0800, at: 0x1040, into: &patched)
        let comparison = try TranslationRAMComparison(
            originalEvidenceName: "Original checkpoint",
            patchedEvidenceName: "Patched checkpoint",
            route: TranslationArtifactDigest(
                byteCount: 128,
                sha256: String(repeating: "a", count: 64)
            ),
            originalFrameNumber: 4_923,
            patchedFrameNumber: 4_923,
            original: original,
            patched: patched
        )
        let textReport = try TranslationRAMTextScanner.report(for: comparison)
        let pointerReport = try TranslationRAMPointerScanner.report(
            for: comparison,
            textReport: textReport
        )
        return (comparison, textReport, pointerReport)
    }

    private func write(_ string: String, at offset: Int, into data: inout Data) {
        let bytes = Array(string.utf8) + [0]
        data.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }

    private func writePointer(to target: Int, at offset: Int, into data: inout Data) {
        data[offset] = UInt8(truncatingIfNeeded: target)
        data[offset + 1] = UInt8(truncatingIfNeeded: target >> 8)
    }

    private func address(_ offset: Int) -> String {
        String(format: "0x%04X", offset)
    }

    private func render(
        _ view: AnyView,
        size: CGSize,
        scheme: Scheme,
        prepare: ((NSView, NSWindow) -> Void)? = nil
    ) throws -> (png: Data, bitmap: NSBitmapImageRep) {
        _ = NSApplication.shared
        let content = AnyView(
            view
                .environment(\.colorScheme, scheme.colorScheme)
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
        )
        let host = NSHostingView(rootView: content)
        host.frame = CGRect(origin: .zero, size: size)
        let window = offscreenWindow(size: size, scheme: scheme)
        window.contentView = host
        window.orderFront(nil)
        settle(window: window, host: host)
        prepare?(host, window)
        settle(window: window, host: host)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw SnapshotError.appKitCacheFailed
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        bitmap.size = size
        guard let png = bitmap.representation(
            using: NSBitmapImageRep.FileType.png,
            properties: [:]
        ) else {
            throw SnapshotError.pngEncodingFailed
        }
        return (png, bitmap)
    }

    private func scrollLibraryInspectorToBottom(in root: NSView) {
        let candidates = viewDescendants(of: root, type: NSScrollView.self)
            .map { scrollView in
                (scrollView, scrollView.convert(scrollView.bounds, to: root).standardized)
            }
            .filter { _, frame in
                frame.midX > root.bounds.width * 0.72
                    && frame.width > 200
                    && frame.height > 200
            }
        guard let scrollView = candidates.max(by: {
            $0.1.width * $0.1.height < $1.1.width * $1.1.height
        })?.0 else { return }
        let origin = scrollView.contentView.bounds.origin
        scrollView.contentView.scroll(
            to: CGPoint(x: origin.x, y: verticalScrollRange(scrollView))
        )
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func imageSignature(
        name: String,
        scheme: Scheme,
        bitmap: NSBitmapImageRep,
        png: Data
    ) -> SnapshotSignature {
        var colors = Set<UInt16>()
        var opaque = 0
        var total = 0
        var yellow = 0
        var centralTotal = 0
        var centralHistogram: [UInt16: Int] = [:]
        var luminance = 0.0
        let step = max(4, min(bitmap.pixelsWide, bitmap.pixelsHigh) / 80)
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: step) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: step) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                let red = max(0, min(31, Int((color.redComponent * 31).rounded())))
                let green = max(0, min(31, Int((color.greenComponent * 31).rounded())))
                let blue = max(0, min(31, Int((color.blueComponent * 31).rounded())))
                let bucket = UInt16((red << 10) | (green << 5) | blue)
                colors.insert(bucket)
                opaque += color.alphaComponent > 0.98 ? 1 : 0
                if color.redComponent > 0.72,
                   color.greenComponent > 0.55,
                   color.blueComponent < 0.28 {
                    yellow += 1
                }
                if x >= bitmap.pixelsWide / 5,
                   x <= bitmap.pixelsWide * 4 / 5,
                   y >= bitmap.pixelsHigh / 5,
                   y <= bitmap.pixelsHigh * 4 / 5 {
                    centralHistogram[bucket, default: 0] += 1
                    centralTotal += 1
                }
                luminance += 0.2126 * color.redComponent
                    + 0.7152 * color.greenComponent
                    + 0.0722 * color.blueComponent
                total += 1
            }
        }
        return SnapshotSignature(
            name: name,
            scheme: scheme.rawValue,
            width: Int(bitmap.size.width.rounded()),
            height: Int(bitmap.size.height.rounded()),
            pngByteCount: png.count,
            sampledColorCount: colors.count,
            opaqueSampleFraction: total == 0 ? 0 : Double(opaque) / Double(total),
            centralDominantColorFraction: centralTotal == 0
                ? 1
                : Double(centralHistogram.values.max() ?? centralTotal) / Double(centralTotal),
            yellowPlaceholderFraction: total == 0 ? 1 : Double(yellow) / Double(total),
            meanLuminance: total == 0 ? 0 : luminance / Double(total),
            perceptualHash: perceptualHash(bitmap),
            sha256: SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func enforcePerceptualBaselines(
        _ signatures: [SnapshotSignature]
    ) throws {
        let currentEntries = Dictionary(uniqueKeysWithValues: signatures.map {
            ("\($0.name)-\($0.scheme)", $0.perceptualHash)
        })
        let current = PerceptualBaselineDocument(
            algorithm: Self.perceptualHashAlgorithm,
            bitCount: 256,
            maximumHammingDistance: Self.maximumPerceptualHammingDistance,
            macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            entries: currentEntries
        )
        if ProcessInfo.processInfo.environment["SWAN_SONG_UPDATE_UI_BASELINES"] == "1" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(current).write(
                to: perceptualBaselineURL,
                options: [.atomic]
            )
            return
        }

        guard FileManager.default.fileExists(atPath: perceptualBaselineURL.path) else {
            throw SnapshotError.invalidBaseline(
                "missing \(perceptualBaselineURL.path). Review the PNGs, then run Scripts/check-ui-snapshots.sh --update-baselines."
            )
        }
        let baseline = try JSONDecoder().decode(
            PerceptualBaselineDocument.self,
            from: Data(contentsOf: perceptualBaselineURL)
        )
        guard baseline.algorithm == Self.perceptualHashAlgorithm else {
            throw SnapshotError.invalidBaseline(
                "algorithm \(baseline.algorithm) does not match \(Self.perceptualHashAlgorithm)"
            )
        }
        guard baseline.bitCount == 256 else {
            throw SnapshotError.invalidBaseline("expected 256-bit hashes")
        }
        guard baseline.maximumHammingDistance == Self.maximumPerceptualHammingDistance else {
            throw SnapshotError.invalidBaseline(
                "maximum Hamming distance must remain \(Self.maximumPerceptualHammingDistance)"
            )
        }
        guard Set(baseline.entries.keys) == Set(currentEntries.keys) else {
            let missing = Set(currentEntries.keys).subtracting(baseline.entries.keys).sorted()
            let stale = Set(baseline.entries.keys).subtracting(currentEntries.keys).sorted()
            throw SnapshotError.invalidBaseline(
                "scenario set differs; missing \(missing), stale \(stale)"
            )
        }

        let currentMajorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        guard baseline.macOSMajorVersion == currentMajorVersion else {
            guard ProcessInfo.processInfo.environment[
                "SWAN_SONG_ALLOW_UI_BASELINE_PLATFORM_MISMATCH"
            ] == "1" else {
                throw SnapshotError.invalidBaseline(
                    "perceptual baselines were reviewed on macOS \(baseline.macOSMajorVersion), but this host runs macOS \(currentMajorVersion). Pixel hashes are OS-specific; run the structural snapshot checks in CI with SWAN_SONG_ALLOW_UI_BASELINE_PLATFORM_MISMATCH=1 or review and refresh baselines on this OS."
                )
            }
            print(
                "SKIP perceptual hash comparison: reviewed on macOS \(baseline.macOSMajorVersion), structural rendering checks passed on macOS \(currentMajorVersion)"
            )
            return
        }

        for key in currentEntries.keys.sorted() {
            let expected = try XCTUnwrap(baseline.entries[key])
            let actual = try XCTUnwrap(currentEntries[key])
            let distance = try hammingDistance(expected, actual)
            XCTAssertLessThanOrEqual(
                distance,
                baseline.maximumHammingDistance,
                "\(key) perceptual distance \(distance)/\(baseline.bitCount) exceeds \(baseline.maximumHammingDistance). Review .build/ui-regression, then explicitly refresh with Scripts/check-ui-snapshots.sh --update-baselines."
            )
        }
    }

    private func perceptualHash(_ bitmap: NSBitmapImageRep) -> String {
        let columns = 17
        let rows = 16
        let samplesPerAxis = 4
        var luminances = [UInt8]()
        luminances.reserveCapacity(columns * rows)

        for row in 0..<rows {
            for column in 0..<columns {
                var sum = 0.0
                var sampleCount = 0
                for sampleY in 0..<samplesPerAxis {
                    for sampleX in 0..<samplesPerAxis {
                        let x = min(
                            bitmap.pixelsWide - 1,
                            ((column * samplesPerAxis + sampleX) * bitmap.pixelsWide)
                                / (columns * samplesPerAxis)
                        )
                        let y = min(
                            bitmap.pixelsHigh - 1,
                            ((row * samplesPerAxis + sampleY) * bitmap.pixelsHigh)
                                / (rows * samplesPerAxis)
                        )
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                            continue
                        }
                        sum += 0.2126 * color.redComponent
                            + 0.7152 * color.greenComponent
                            + 0.0722 * color.blueComponent
                        sampleCount += 1
                    }
                }
                let average = sampleCount == 0 ? 0 : sum / Double(sampleCount)
                luminances.append(UInt8(max(0, min(255, Int((average * 255).rounded())))))
            }
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        for row in 0..<rows {
            for column in 0..<(columns - 1) {
                let bitIndex = row * (columns - 1) + column
                let left = luminances[row * columns + column]
                let right = luminances[row * columns + column + 1]
                if left > right {
                    bytes[bitIndex / 8] |= UInt8(1 << (7 - bitIndex % 8))
                }
            }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func hammingDistance(_ lhs: String, _ rhs: String) throws -> Int {
        guard let left = hexadecimalBytes(lhs), let right = hexadecimalBytes(rhs),
              left.count == 32, right.count == 32 else {
            throw SnapshotError.invalidBaseline("hashes must be 64 lowercase hexadecimal characters")
        }
        return zip(left, right).reduce(0) { distance, pair in
            distance + (pair.0 ^ pair.1).nonzeroBitCount
        }
    }

    private func hexadecimalBytes(_ value: String) -> [UInt8]? {
        let characters = Array(value.utf8)
        guard characters.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(characters.count / 2)
        for index in stride(from: 0, to: characters.count, by: 2) {
            guard let high = hexadecimalNibble(characters[index]),
                  let low = hexadecimalNibble(characters[index + 1]) else {
                return nil
            }
            bytes.append((high << 4) | low)
        }
        return bytes
    }

    private func hexadecimalNibble(_ value: UInt8) -> UInt8? {
        switch value {
        case 48...57: value - 48
        case 97...102: value - 87
        default: nil
        }
    }

    private func offscreenWindow(
        size: CGSize,
        scheme: Scheme
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -50_000, y: -50_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.backgroundColor = .windowBackgroundColor
        window.appearance = NSAppearance(
            named: scheme == .dark ? .darkAqua : .aqua
        )
        return window
    }

    private func settle(window: NSWindow, host: NSView) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
    }

    private func viewDescendants<ViewType: NSView>(
        of root: NSView,
        type: ViewType.Type
    ) -> [ViewType] {
        var result = [ViewType]()
        func visit(_ view: NSView) {
            if let match = view as? ViewType { result.append(match) }
            for subview in view.subviews {
                visit(subview)
            }
        }
        visit(root)
        return result
    }

    private func ancestor<ViewType: NSView>(
        of view: NSView,
        type: ViewType.Type
    ) -> ViewType? {
        var candidate = view.superview
        while let current = candidate {
            if let match = current as? ViewType { return match }
            candidate = current.superview
        }
        return nil
    }

    private func verticalScrollRange(_ scrollView: NSScrollView) -> CGFloat {
        guard let document = scrollView.documentView else { return 0 }
        return max(0, document.bounds.height - scrollView.contentView.bounds.height)
    }

    private func expectCompactTranslationOverviewGeometry(
        model: AppModel,
        size: CGSize,
        actionExpectations: [String: String]
    ) throws {
        _ = NSApplication.shared
        let geometryProbe = TranslationLabOverviewGeometryProbe()
        let content = AnyView(
            RootView(
                model: model,
                translationLabOverviewGeometryProbe: geometryProbe
            )
                .environment(\.colorScheme, Scheme.light.colorScheme)
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
        )
        let host = NSHostingView(rootView: content)
        host.frame = CGRect(origin: .zero, size: size)
        let window = offscreenWindow(size: size, scheme: .light)
        window.contentView = host
        window.orderFront(nil)
        settle(window: window, host: host)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }

        let scrollView = try XCTUnwrap(
            viewDescendants(of: host, type: NSScrollView.self)
                .filter { verticalScrollRange($0) > 0.5 }
                .max { lhs, rhs in
                    lhs.contentView.bounds.width < rhs.contentView.bounds.width
                },
            "The compact Translation Lab overview lost its vertical scroll path"
        )
        let scrollRange = verticalScrollRange(scrollView)
        XCTAssertGreaterThan(
            scrollRange,
            0.5,
            "The compact Translation Lab fixture no longer exercises vertical reachability"
        )

        var visibleWorkflowFrame: CGRect?
        var visibleActionFrames: [String: CGRect] = [:]
        let originalOrigin = scrollView.contentView.bounds.origin
        let scanSteps = 20
        for step in 0...scanSteps {
            let progress = CGFloat(step) / CGFloat(scanSteps)
            scrollView.contentView.scroll(
                to: CGPoint(
                    x: originalOrigin.x,
                    y: scrollRange * progress
                )
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
            settle(window: window, host: host)

            let viewport = geometryProbe.viewportFrame.insetBy(dx: -1, dy: -1)
            if let frame = geometryProbe.elementFrames[
                TranslationLabOverviewAccessibility.workflow
            ]?.standardized,
               !frame.isEmpty,
               viewport.contains(frame) {
                visibleWorkflowFrame = frame
            }
            for identifier in actionExpectations.keys {
                if let frame = geometryProbe.elementFrames[identifier]?.standardized,
                   !frame.isEmpty,
                   viewport.contains(frame) {
                    visibleActionFrames[identifier] = frame
                }
            }
        }

        scrollView.contentView.scroll(to: originalOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        settle(window: window, host: host)

        XCTAssertNotNil(
            visibleWorkflowFrame,
            "Deterministic Route Testing cannot be scrolled fully into the compact overview viewport"
        )
        XCTAssertFalse(
            geometryProbe.viewportFrame.isEmpty,
            "The Translation Lab overview viewport probe did not report layout"
        )
        for (identifier, title) in actionExpectations.sorted(by: { $0.key < $1.key }) {
            let frame = try XCTUnwrap(
                visibleActionFrames[identifier],
                "\(title) cannot be scrolled fully into the compact overview viewport"
            )
            XCTAssertGreaterThanOrEqual(
                frame.width,
                28,
                "\(title) is narrower than the 28-point macOS action minimum"
            )
            XCTAssertGreaterThanOrEqual(
                frame.height,
                28,
                "\(title) is shorter than the 28-point macOS action minimum"
            )
        }
    }

    private func resetTemporaryDirectory(_ url: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func restoreUserDefault(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func expectUsableActionFrame(_ frame: CGRect, label: String) throws {
        XCTAssertFalse(frame.isEmpty, "\(label) has an empty accessibility frame")
        XCTAssertGreaterThanOrEqual(frame.width, StateTimelineCard.minimumInteractiveDimension)
        XCTAssertGreaterThanOrEqual(frame.height, StateTimelineCard.minimumInteractiveDimension)
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-UIRegression-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func snapshotOutputDirectory() throws -> URL {
        let environment = ProcessInfo.processInfo.environment["SWAN_SONG_UI_SNAPSHOT_DIR"]
        let output: URL
        if let environment, !environment.isEmpty {
            output = URL(fileURLWithPath: environment, isDirectory: true)
        } else {
            output = packageRoot
                .appendingPathComponent(".build", isDirectory: true)
                .appendingPathComponent("ui-regression", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        return output
    }

    private var perceptualBaselineURL: URL {
        packageRoot
            .appendingPathComponent("Tests", isDirectory: true)
            .appendingPathComponent("SwanSongAppSnapshotTests", isDirectory: true)
            .appendingPathComponent("ui-perceptual-baselines.json")
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
