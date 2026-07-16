import Foundation
import XCTest
@testable import SwanSongKit

final class ControllerInputMappingTests: XCTestCase {
    func testAxisThresholdRejectsDriftAndMapsCardinalAndDiagonalInput() {
        XCTAssertEqual(
            ControllerDirectionState(xAxis: 0.49, yAxis: -0.49),
            .neutral
        )
        XCTAssertEqual(
            ControllerDirectionState(xAxis: 0.75, yAxis: 0.8),
            ControllerDirectionState(up: true, right: true, down: false, left: false)
        )
        XCTAssertEqual(
            ControllerDirectionState(xAxis: -.infinity, yAxis: .nan),
            .neutral
        )
    }

    func testExtendedSnapshotMapsEveryStandardElementByLogicalPosition() {
        let snapshot = StandardControllerSnapshot(
            dpad: .init(up: true, right: false, down: true, left: false),
            leftStick: .init(up: false, right: true, down: false, left: true),
            rightStick: .init(up: true, right: true, down: false, left: false),
            buttons: Set(StandardControllerButton.allTestCases)
        )

        XCTAssertEqual(
            StandardControllerMapper.elements(from: snapshot),
            [
                .dpadUp, .dpadDown,
                .leftStickRight, .leftStickLeft,
                .rightStickUp, .rightStickRight,
                .buttonNorth, .buttonEast, .buttonSouth, .buttonWest,
                .leftShoulder, .rightShoulder,
                .leftTrigger, .rightTrigger,
                .leftStickButton, .rightStickButton,
                .menu, .options,
                .leftBumper, .rightBumper, .share,
                .backLeftPrimary, .backLeftSecondary,
                .backRightPrimary, .backRightSecondary,
                .paddleOne, .paddleTwo, .paddleThree, .paddleFour,
                .touchpadButton,
            ]
        )
    }

    func testMicroSnapshotMapsItsDpadTwoFaceButtonsAndMenu() {
        let snapshot = StandardControllerSnapshot(
            dpad: .init(up: false, right: true, down: true, left: false),
            buttons: [.south, .west, .menu]
        )
        XCTAssertEqual(
            StandardControllerMapper.elements(from: snapshot),
            [.dpadRight, .dpadDown, .buttonSouth, .buttonWest, .menu]
        )
    }

    func testPhysicalExtendedAndBasicAliasesMapByLogicalPosition() {
        let snapshot = StandardControllerPhysicalSnapshot(
            availableDirections: [.directionPad, .leftThumbstick],
            availableButtons: [
                .buttonA, .buttonB, .buttonX, .buttonY,
                .leftShoulder, .rightShoulder, .menu,
            ],
            directions: [
                .directionPad: .init(
                    up: true, right: false, down: false, left: false
                ),
                .leftThumbstick: .init(
                    up: false, right: true, down: false, left: false
                ),
            ],
            pressedButtons: [.buttonA, .buttonY, .rightShoulder, .menu]
        )

        XCTAssertTrue(StandardControllerPhysicalMapper.supportsGameplay(snapshot))
        XCTAssertEqual(
            StandardControllerPhysicalMapper.elements(from: snapshot),
            [
                .dpadUp, .leftStickRight,
                .buttonSouth, .buttonNorth, .rightShoulder, .menu,
            ]
        )
        XCTAssertEqual(
            StandardControllerPhysicalMapper.availableElements(from: snapshot),
            [
                .dpadUp, .dpadRight, .dpadDown, .dpadLeft,
                .leftStickUp, .leftStickRight, .leftStickDown, .leftStickLeft,
                .buttonNorth, .buttonEast, .buttonSouth, .buttonWest,
                .leftShoulder, .rightShoulder, .menu,
            ]
        )
    }

    func testPhysicalMicroAliasesExposeOnlyTwoActionsAndMenu() {
        let snapshot = StandardControllerPhysicalSnapshot(
            availableDirections: [.microDirectionPad],
            availableButtons: [.microButtonA, .microButtonX, .microMenu],
            directions: [
                .microDirectionPad: .init(
                    up: false, right: false, down: true, left: true
                ),
            ],
            pressedButtons: [.microButtonA, .microButtonX, .microMenu]
        )

        XCTAssertTrue(StandardControllerPhysicalMapper.supportsGameplay(snapshot))
        XCTAssertEqual(
            StandardControllerPhysicalMapper.elements(from: snapshot),
            [.dpadDown, .dpadLeft, .buttonSouth, .buttonWest, .menu]
        )
        XCTAssertEqual(
            StandardControllerPhysicalMapper.availableElements(from: snapshot),
            [
                .dpadUp, .dpadRight, .dpadDown, .dpadLeft,
                .buttonSouth, .buttonWest, .menu,
            ]
        )
    }

    func testPhysicalDirectionalAliasesMergePrimaryAndCardinalSurfaces() {
        let snapshot = StandardControllerPhysicalSnapshot(
            availableDirections: [
                .directionalDirectionPad, .directionalCardinalDirectionPad,
            ],
            availableButtons: [
                .directionalTouchSurface, .directionalCenter,
            ],
            directions: [
                .directionalDirectionPad: .init(
                    up: true, right: false, down: false, left: false
                ),
                .directionalCardinalDirectionPad: .init(
                    up: false, right: true, down: false, left: false
                ),
            ],
            pressedButtons: [
                .directionalTouchSurface, .directionalCenter,
            ]
        )

        XCTAssertTrue(StandardControllerPhysicalMapper.supportsGameplay(snapshot))
        XCTAssertEqual(
            StandardControllerPhysicalMapper.elements(from: snapshot),
            [.dpadUp, .dpadRight, .buttonSouth, .buttonWest]
        )
        XCTAssertEqual(
            StandardControllerPhysicalMapper.availableElements(from: snapshot),
            [
                .dpadUp, .dpadRight, .dpadDown, .dpadLeft,
                .buttonSouth, .buttonWest,
            ]
        )
    }

    func testPhysicalProfileRequiresStandardDirectionAndActionAliases() {
        let directionOnly = StandardControllerPhysicalSnapshot(
            availableDirections: [.directionPad],
            availableButtons: [.menu],
            directions: [:],
            pressedButtons: []
        )
        let actionOnly = StandardControllerPhysicalSnapshot(
            availableDirections: [],
            availableButtons: [.buttonA],
            directions: [:],
            pressedButtons: []
        )
        let optionalButtonsOnly = StandardControllerPhysicalSnapshot(
            availableDirections: [.directionPad],
            availableButtons: [
                .leftBumper, .rightBumper, .share,
                .backLeftPrimary, .backRightPrimary,
                .paddleOne, .touchpadButton,
            ],
            directions: [:],
            pressedButtons: []
        )
        XCTAssertFalse(StandardControllerPhysicalMapper.supportsGameplay(directionOnly))
        XCTAssertFalse(StandardControllerPhysicalMapper.supportsGameplay(actionOnly))
        XCTAssertFalse(StandardControllerPhysicalMapper.supportsGameplay(optionalButtonsOnly))
    }

    func testPhysicalOptionalStandardButtonsRemainDistinctAndRemappable() {
        let mappings: [(StandardControllerButtonAlias, ControllerElement)] = [
            (.leftBumper, .leftBumper),
            (.rightBumper, .rightBumper),
            (.share, .share),
            (.backLeftPrimary, .backLeftPrimary),
            (.backLeftSecondary, .backLeftSecondary),
            (.backRightPrimary, .backRightPrimary),
            (.backRightSecondary, .backRightSecondary),
            (.paddleOne, .paddleOne),
            (.paddleTwo, .paddleTwo),
            (.paddleThree, .paddleThree),
            (.paddleFour, .paddleFour),
            (.touchpadButton, .touchpadButton),
        ]
        let aliases = Set(mappings.map(\.0))
        let snapshot = StandardControllerPhysicalSnapshot(
            availableDirections: [.directionPad],
            availableButtons: aliases.union([.buttonA]),
            directions: [.directionPad: .neutral],
            pressedButtons: aliases
        )

        XCTAssertTrue(StandardControllerPhysicalMapper.supportsGameplay(snapshot))
        XCTAssertEqual(
            StandardControllerPhysicalMapper.elements(from: snapshot),
            Set(mappings.map(\.1))
        )
        XCTAssertEqual(
            StandardControllerPhysicalMapper.availableElements(from: snapshot),
            Set(mappings.map(\.1)).union([
                .dpadUp, .dpadRight, .dpadDown, .dpadLeft, .buttonSouth,
            ])
        )
        XCTAssertEqual(Set(mappings.map(\.1)).count, mappings.count)
    }

    func testPhysicalArcadeGridMapsThreeByFourWithoutCollapsingButtons() {
        let mappings: [(StandardControllerButtonAlias, ControllerElement)] = [
            (.arcadeRow0Column0, .buttonWest),
            (.arcadeRow0Column1, .buttonNorth),
            (.arcadeRow0Column2, .rightShoulder),
            (.arcadeRow0Column3, .leftShoulder),
            (.arcadeRow1Column0, .buttonSouth),
            (.arcadeRow1Column1, .buttonEast),
            (.arcadeRow1Column2, .rightTrigger),
            (.arcadeRow1Column3, .leftTrigger),
            (.arcadeRow2Column0, .options),
            (.arcadeRow2Column1, .menu),
            (.arcadeRow2Column2, .leftStickButton),
            (.arcadeRow2Column3, .rightStickButton),
        ]
        let aliases = Set(mappings.map(\.0))
        let expectedElements = Set(mappings.map(\.1))
        let allPressed = StandardControllerPhysicalSnapshot(
            availableDirections: [.directionPad],
            availableButtons: aliases,
            directions: [.directionPad: .neutral],
            pressedButtons: aliases
        )

        XCTAssertTrue(StandardControllerPhysicalMapper.supportsGameplay(allPressed))
        let expectedAvailable = expectedElements.union([
            .dpadUp, .dpadRight, .dpadDown, .dpadLeft,
        ])
        XCTAssertEqual(
            StandardControllerPhysicalMapper.availableElements(from: allPressed),
            expectedAvailable
        )
        XCTAssertEqual(
            StandardControllerPhysicalMapper.elements(from: allPressed),
            expectedElements
        )
        XCTAssertEqual(expectedElements.count, 12)

        for (alias, element) in mappings {
            let onePressed = StandardControllerPhysicalSnapshot(
                availableDirections: [.directionPad],
                availableButtons: aliases,
                directions: [.directionPad: .neutral],
                pressedButtons: [alias]
            )
            XCTAssertEqual(
                StandardControllerPhysicalMapper.elements(from: onePressed),
                [element],
                "Arcade alias \(alias) did not keep its unique logical element."
            )
        }
    }

    func testDisconnectRemovesOnlyDepartingControllersContribution() {
        var reducer = ControllerInputReducer<String>()
        XCTAssertTrue(reducer.update([.dpadUp, .buttonSouth], for: "one"))
        XCTAssertTrue(reducer.update([.dpadUp, .buttonEast], for: "two"))
        XCTAssertEqual(reducer.connectedCount, 2)
        XCTAssertEqual(reducer.pressedElements, [.dpadUp, .buttonSouth, .buttonEast])

        XCTAssertTrue(reducer.disconnect("one"))
        XCTAssertEqual(reducer.connectedCount, 1)
        XCTAssertEqual(reducer.pressedElements, [.dpadUp, .buttonEast])
        XCTAssertFalse(reducer.disconnect("missing"))
        XCTAssertEqual(reducer.pressedElements, [.dpadUp, .buttonEast])
    }

    func testNeutralSecondControllerDoesNotChangeAggregatedInput() {
        var reducer = ControllerInputReducer<Int>()
        XCTAssertTrue(reducer.update([.leftStickLeft], for: 1))
        XCTAssertFalse(reducer.update([], for: 2))
        XCTAssertFalse(reducer.disconnect(2))
        XCTAssertEqual(reducer.pressedElements, [.leftStickLeft])
    }

    func testCooperativeMergeKeepsOppositeHeldInputsExplicitUntilRelease() {
        var reducer = ControllerInputReducer<String>()
        XCTAssertTrue(
            reducer.update([.dpadLeft, .buttonSouth], for: "left controller")
        )
        XCTAssertTrue(
            reducer.update([.dpadRight, .buttonSouth], for: "right controller")
        )
        XCTAssertEqual(
            reducer.pressedElements,
            [.dpadLeft, .dpadRight, .buttonSouth]
        )

        XCTAssertTrue(reducer.disconnect("left controller"))
        XCTAssertEqual(reducer.pressedElements, [.dpadRight, .buttonSouth])
        XCTAssertTrue(reducer.update([], for: "right controller"))
        XCTAssertTrue(reducer.pressedElements.isEmpty)
    }

    func testNeutralizeClearsHeldInputWithoutForgettingConnectedControllers() {
        var reducer = ControllerInputReducer<String>()
        XCTAssertTrue(reducer.update([.dpadUp, .buttonSouth], for: "one"))
        XCTAssertTrue(reducer.update([.buttonEast], for: "two"))

        XCTAssertTrue(reducer.neutralize())
        XCTAssertEqual(reducer.connectedCount, 2)
        XCTAssertTrue(reducer.pressedElements.isEmpty)
        XCTAssertFalse(reducer.neutralize())

        XCTAssertTrue(reducer.update([.dpadLeft], for: "one"))
        XCTAssertEqual(reducer.pressedElements, [.dpadLeft])
    }

    func testCapabilityReducerUnionsHotpluggedProfilesAndRemovesOnlyDeparture() {
        var reducer = ControllerCapabilityReducer<String>()
        let micro: Set<ControllerElement> = [
            .dpadUp, .dpadRight, .dpadDown, .dpadLeft,
            .buttonSouth, .buttonWest, .menu,
        ]
        let addedByExtended: Set<ControllerElement> = [
            .rightStickUp, .rightStickRight, .rightStickDown, .rightStickLeft,
            .buttonEast, .leftShoulder,
        ]

        XCTAssertTrue(reducer.update(micro, for: "micro"))
        XCTAssertFalse(reducer.update(micro, for: "second micro"))
        XCTAssertEqual(reducer.connectedCount, 2)
        XCTAssertEqual(reducer.availableElements, micro)

        XCTAssertTrue(reducer.update(addedByExtended, for: "extended"))
        XCTAssertEqual(reducer.availableElements, micro.union(addedByExtended))
        XCTAssertTrue(reducer.disconnect("extended"))
        XCTAssertEqual(reducer.availableElements, micro)
        XCTAssertFalse(reducer.disconnect("missing"))
    }

    func testLimitedProfileReportsEverySavedBindingItCannotEmit() {
        let available: Set<ControllerElement> = [
            .dpadUp, .dpadRight, .dpadDown, .dpadLeft,
            .buttonSouth, .buttonWest, .menu,
        ]

        XCTAssertEqual(
            ControllerProfile.default
                .unavailableBindings(for: available)
                .map(\.control),
            [.y1, .y2, .y3, .y4, .a, .volume]
        )

        let remapped = ControllerProfile.default
            .updating(.a, to: .buttonWest)
            .updating(.volume, to: nil)
        XCTAssertEqual(
            remapped.unavailableBindings(for: available).map(\.control),
            [.y1, .y2, .y3, .y4]
        )
    }

    func testProfileStoreReadsLegacyProfileAndRoundTripsOptionalBindings() throws {
        let legacyData = Data(
            #"{"schemaVersion":1,"preset":"custom","bindings":[{"control":"a","element":"buttonSouth"}]}"#.utf8
        )
        let legacy = try JSONDecoder().decode(ControllerProfile.self, from: legacyData)
        XCTAssertEqual(legacy.schemaVersion, 1)
        XCTAssertEqual(legacy.element(for: .a), .buttonSouth)

        let optionalElements: [ControllerElement] = [
            .leftBumper, .rightBumper, .share,
            .backLeftPrimary, .backLeftSecondary,
            .backRightPrimary, .backRightSecondary,
            .paddleOne, .paddleTwo, .paddleThree, .paddleFour,
            .touchpadButton,
        ]
        XCTAssertEqual(optionalElements.count, WonderSwanControl.allCases.count)
        let profile = ControllerProfile(
            preset: .custom,
            bindings: zip(WonderSwanControl.allCases, optionalElements).map {
                ControllerBinding(control: $0.0, element: $0.1)
            }
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwanSongControllerProfileTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ControllerProfileStore(
            fileURL: directory.appendingPathComponent("ControllerProfile.json")
        )

        try store.save(profile)
        XCTAssertEqual(try store.load(), profile)
    }

    func testEveryControllerElementHasDistinctStableDisplayCopy() {
        XCTAssertEqual(Set(ControllerElement.allCases.map(\.rawValue)).count,
                       ControllerElement.allCases.count)
        XCTAssertEqual(Set(ControllerElement.allCases.map(\.shortTitle)).count,
                       ControllerElement.allCases.count)
        XCTAssertTrue(ControllerElement.allCases.allSatisfy { !$0.title.isEmpty })
        XCTAssertTrue(ControllerElement.allCases.allSatisfy { !$0.shortTitle.isEmpty })
    }
}

private extension StandardControllerButton {
    static let allTestCases: [Self] = [
        .north, .east, .south, .west,
        .leftShoulder, .rightShoulder,
        .leftTrigger, .rightTrigger,
        .leftStick, .rightStick,
        .menu, .options,
        .leftBumper, .rightBumper, .share,
        .backLeftPrimary, .backLeftSecondary,
        .backRightPrimary, .backRightSecondary,
        .paddleOne, .paddleTwo, .paddleThree, .paddleFour,
        .touchpadButton,
    ]
}
