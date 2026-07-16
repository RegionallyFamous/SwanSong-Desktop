import Foundation

public enum WonderSwanControl: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case x1, x2, x3, x4
    case y1, y2, y3, y4
    case a, b, start, volume

    public var id: Self { self }

    public var title: String {
        switch self {
        case .x1: "X1"
        case .x2: "X2"
        case .x3: "X3"
        case .x4: "X4"
        case .y1: "Y1"
        case .y2: "Y2"
        case .y3: "Y3"
        case .y4: "Y4"
        case .a: "A"
        case .b: "B"
        case .start: "Start"
        case .volume: "Volume"
        }
    }

    public var engineInput: EngineInput {
        switch self {
        case .x1: .x1
        case .x2: .x2
        case .x3: .x3
        case .x4: .x4
        case .y1: .y1
        case .y2: .y2
        case .y3: .y3
        case .y4: .y4
        case .a: .a
        case .b: .b
        case .start: .start
        case .volume: .volume
        }
    }
}

public enum ControllerElement: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case dpadUp, dpadRight, dpadDown, dpadLeft
    case leftStickUp, leftStickRight, leftStickDown, leftStickLeft
    case rightStickUp, rightStickRight, rightStickDown, rightStickLeft
    case buttonNorth, buttonEast, buttonSouth, buttonWest
    case leftShoulder, rightShoulder
    case leftTrigger, rightTrigger
    case leftStickButton, rightStickButton
    case menu, options
    case leftBumper, rightBumper
    case share
    case backLeftPrimary, backLeftSecondary
    case backRightPrimary, backRightSecondary
    case paddleOne, paddleTwo, paddleThree, paddleFour
    case touchpadButton

    public var id: Self { self }

    public var title: String {
        switch self {
        case .dpadUp: "D-pad Up"
        case .dpadRight: "D-pad Right"
        case .dpadDown: "D-pad Down"
        case .dpadLeft: "D-pad Left"
        case .leftStickUp: "Left Stick Up"
        case .leftStickRight: "Left Stick Right"
        case .leftStickDown: "Left Stick Down"
        case .leftStickLeft: "Left Stick Left"
        case .rightStickUp: "Right Stick Up"
        case .rightStickRight: "Right Stick Right"
        case .rightStickDown: "Right Stick Down"
        case .rightStickLeft: "Right Stick Left"
        case .buttonNorth: "North Face Button"
        case .buttonEast: "East Face Button"
        case .buttonSouth: "South Face Button"
        case .buttonWest: "West Face Button"
        case .leftShoulder: "Left Shoulder"
        case .rightShoulder: "Right Shoulder"
        case .leftTrigger: "Left Trigger"
        case .rightTrigger: "Right Trigger"
        case .leftStickButton: "Left Stick Click"
        case .rightStickButton: "Right Stick Click"
        case .menu: "Menu Button"
        case .options: "Options Button"
        case .leftBumper: "Left Bumper"
        case .rightBumper: "Right Bumper"
        case .share: "Share Button"
        case .backLeftPrimary: "Left Back Button 1"
        case .backLeftSecondary: "Left Back Button 2"
        case .backRightPrimary: "Right Back Button 1"
        case .backRightSecondary: "Right Back Button 2"
        case .paddleOne: "Paddle 1"
        case .paddleTwo: "Paddle 2"
        case .paddleThree: "Paddle 3"
        case .paddleFour: "Paddle 4"
        case .touchpadButton: "Touchpad Click"
        }
    }

    public var shortTitle: String {
        switch self {
        case .dpadUp: "D↑"
        case .dpadRight: "D→"
        case .dpadDown: "D↓"
        case .dpadLeft: "D←"
        case .leftStickUp: "L↑"
        case .leftStickRight: "L→"
        case .leftStickDown: "L↓"
        case .leftStickLeft: "L←"
        case .rightStickUp: "R↑"
        case .rightStickRight: "R→"
        case .rightStickDown: "R↓"
        case .rightStickLeft: "R←"
        case .buttonNorth: "Face N"
        case .buttonEast: "Face E"
        case .buttonSouth: "Face S"
        case .buttonWest: "Face W"
        case .leftShoulder: "L1"
        case .rightShoulder: "R1"
        case .leftTrigger: "L2"
        case .rightTrigger: "R2"
        case .leftStickButton: "L3"
        case .rightStickButton: "R3"
        case .menu: "Menu"
        case .options: "Options"
        case .leftBumper: "LB"
        case .rightBumper: "RB"
        case .share: "Share"
        case .backLeftPrimary: "Back L1"
        case .backLeftSecondary: "Back L2"
        case .backRightPrimary: "Back R1"
        case .backRightSecondary: "Back R2"
        case .paddleOne: "P1"
        case .paddleTwo: "P2"
        case .paddleThree: "P3"
        case .paddleFour: "P4"
        case .touchpadButton: "Touchpad"
        }
    }
}

/// A device-independent directional snapshot used by the GameController
/// adapter. Keeping analog thresholding here makes the mapping deterministic
/// and testable without requiring physical controller hardware.
public struct ControllerDirectionState: Equatable, Sendable {
    public let up: Bool
    public let right: Bool
    public let down: Bool
    public let left: Bool

    public init(up: Bool, right: Bool, down: Bool, left: Bool) {
        self.up = up
        self.right = right
        self.down = down
        self.left = left
    }

    public init(
        xAxis: Float,
        yAxis: Float,
        activationThreshold: Float = 0.5
    ) {
        let threshold = activationThreshold.isFinite
            ? min(max(abs(activationThreshold), 0.05), 1)
            : 0.5
        let x = xAxis.isFinite ? xAxis : 0
        let y = yAxis.isFinite ? yAxis : 0
        up = y >= threshold
        right = x >= threshold
        down = y <= -threshold
        left = x <= -threshold
    }

    public static let neutral = ControllerDirectionState(
        up: false,
        right: false,
        down: false,
        left: false
    )
}

/// Buttons common to Apple's standard game-controller profiles. The names
/// describe logical position, not any vendor's labeling.
public enum StandardControllerButton: Hashable, Sendable {
    case north, east, south, west
    case leftShoulder, rightShoulder
    case leftTrigger, rightTrigger
    case leftStick, rightStick
    case menu, options
    case leftBumper, rightBumper
    case share
    case backLeftPrimary, backLeftSecondary
    case backRightPrimary, backRightSecondary
    case paddleOne, paddleTwo, paddleThree, paddleFour
    case touchpadButton
}

/// Stable aliases from Apple's generic, micro, and directional controller
/// profiles. The app adapter translates framework string constants into these
/// values; the pure mapper remains testable without controller hardware.
public enum StandardControllerDirectionAlias: Hashable, Sendable {
    case directionPad
    case leftThumbstick
    case rightThumbstick
    case microDirectionPad
    case directionalDirectionPad
    case directionalCardinalDirectionPad
}

public enum StandardControllerButtonAlias: Hashable, Sendable {
    case buttonA, buttonB, buttonX, buttonY
    case leftShoulder, rightShoulder
    case leftTrigger, rightTrigger
    case leftThumbstick, rightThumbstick
    case menu, options
    case leftBumper, rightBumper
    case share
    case backLeftPrimary, backLeftSecondary
    case backRightPrimary, backRightSecondary
    case paddleOne, paddleTwo, paddleThree, paddleFour
    case touchpadButton
    case microButtonA, microButtonX, microMenu
    case directionalTouchSurface, directionalCenter
    case arcadeRow0Column0, arcadeRow0Column1
    case arcadeRow0Column2, arcadeRow0Column3
    case arcadeRow1Column0, arcadeRow1Column1
    case arcadeRow1Column2, arcadeRow1Column3
    case arcadeRow2Column0, arcadeRow2Column1
    case arcadeRow2Column2, arcadeRow2Column3
}

public struct StandardControllerPhysicalSnapshot: Equatable, Sendable {
    public let availableDirections: Set<StandardControllerDirectionAlias>
    public let availableButtons: Set<StandardControllerButtonAlias>
    public let directions: [StandardControllerDirectionAlias: ControllerDirectionState]
    public let pressedButtons: Set<StandardControllerButtonAlias>

    public init(
        availableDirections: Set<StandardControllerDirectionAlias>,
        availableButtons: Set<StandardControllerButtonAlias>,
        directions: [StandardControllerDirectionAlias: ControllerDirectionState],
        pressedButtons: Set<StandardControllerButtonAlias>
    ) {
        self.availableDirections = availableDirections
        self.availableButtons = availableButtons
        self.directions = directions
        self.pressedButtons = pressedButtons
    }
}

public enum StandardControllerPhysicalMapper {
    /// A controller is useful for WonderSwan play when it exposes at least one
    /// standardized directional surface and one standardized action button.
    /// Vendor-only elements remain ignored instead of being guessed by name.
    public static func supportsGameplay(
        _ snapshot: StandardControllerPhysicalSnapshot
    ) -> Bool {
        !snapshot.availableDirections.isDisjoint(
            with: StandardControllerDirectionAlias.gameplayAliases
        ) && !snapshot.availableButtons.isDisjoint(
            with: StandardControllerButtonAlias.actionAliases
        )
    }

    public static func elements(
        from snapshot: StandardControllerPhysicalSnapshot
    ) -> Set<ControllerElement> {
        let logical = StandardControllerSnapshot(
            dpad: mergedDirection(
                snapshot,
                aliases: [.directionPad, .microDirectionPad,
                          .directionalDirectionPad,
                          .directionalCardinalDirectionPad]
            ),
            leftStick: mergedDirection(snapshot, aliases: [.leftThumbstick]),
            rightStick: mergedDirection(snapshot, aliases: [.rightThumbstick]),
            buttons: Set(snapshot.pressedButtons.compactMap(logicalButton))
        )
        return StandardControllerMapper.elements(from: logical)
    }

    /// Every logical control surface that the connected controller reports
    /// through Apple's standardized physical-input aliases. This is separate
    /// from `elements(from:)`, which contains only controls currently held.
    /// Keeping availability explicit lets the app warn about a saved binding
    /// that a Micro or Directional profile cannot physically produce.
    public static func availableElements(
        from snapshot: StandardControllerPhysicalSnapshot
    ) -> Set<ControllerElement> {
        var result = Set<ControllerElement>()
        for alias in snapshot.availableDirections {
            result.formUnion(directionElements(for: alias))
        }
        for alias in snapshot.availableButtons {
            guard let button = logicalButton(alias) else { continue }
            result.insert(StandardControllerMapper.element(for: button))
        }
        return result
    }

    private static func mergedDirection(
        _ snapshot: StandardControllerPhysicalSnapshot,
        aliases: Set<StandardControllerDirectionAlias>
    ) -> ControllerDirectionState {
        let states = aliases.compactMap { snapshot.directions[$0] }
        return ControllerDirectionState(
            up: states.contains(where: \.up),
            right: states.contains(where: \.right),
            down: states.contains(where: \.down),
            left: states.contains(where: \.left)
        )
    }

    private static func logicalButton(
        _ alias: StandardControllerButtonAlias
    ) -> StandardControllerButton? {
        switch alias {
        case .buttonY: .north
        case .buttonB: .east
        case .buttonA, .microButtonA, .directionalTouchSurface: .south
        case .buttonX, .microButtonX, .directionalCenter: .west
        case .leftShoulder: .leftShoulder
        case .rightShoulder: .rightShoulder
        case .leftTrigger: .leftTrigger
        case .rightTrigger: .rightTrigger
        case .leftThumbstick: .leftStick
        case .rightThumbstick: .rightStick
        case .menu, .microMenu: .menu
        case .options: .options
        case .leftBumper: .leftBumper
        case .rightBumper: .rightBumper
        case .share: .share
        case .backLeftPrimary: .backLeftPrimary
        case .backLeftSecondary: .backLeftSecondary
        case .backRightPrimary: .backRightPrimary
        case .backRightSecondary: .backRightSecondary
        case .paddleOne: .paddleOne
        case .paddleTwo: .paddleTwo
        case .paddleThree: .paddleThree
        case .paddleFour: .paddleFour
        case .touchpadButton: .touchpadButton
        case .arcadeRow0Column0: .west
        case .arcadeRow0Column1: .north
        case .arcadeRow0Column2: .rightShoulder
        case .arcadeRow0Column3: .leftShoulder
        case .arcadeRow1Column0: .south
        case .arcadeRow1Column1: .east
        case .arcadeRow1Column2: .rightTrigger
        case .arcadeRow1Column3: .leftTrigger
        case .arcadeRow2Column0: .options
        case .arcadeRow2Column1: .menu
        case .arcadeRow2Column2: .leftStick
        case .arcadeRow2Column3: .rightStick
        }
    }

    private static func directionElements(
        for alias: StandardControllerDirectionAlias
    ) -> Set<ControllerElement> {
        switch alias {
        case .directionPad, .microDirectionPad,
             .directionalDirectionPad, .directionalCardinalDirectionPad:
            [.dpadUp, .dpadRight, .dpadDown, .dpadLeft]
        case .leftThumbstick:
            [.leftStickUp, .leftStickRight, .leftStickDown, .leftStickLeft]
        case .rightThumbstick:
            [.rightStickUp, .rightStickRight, .rightStickDown, .rightStickLeft]
        }
    }
}

private extension StandardControllerDirectionAlias {
    static let gameplayAliases: Set<Self> = [
        .directionPad, .leftThumbstick, .rightThumbstick,
        .microDirectionPad, .directionalDirectionPad,
        .directionalCardinalDirectionPad,
    ]
}

private extension StandardControllerButtonAlias {
    static let actionAliases: Set<Self> = [
        .buttonA, .buttonB, .buttonX, .buttonY,
        .microButtonA, .microButtonX,
        .directionalTouchSurface, .directionalCenter,
        .arcadeRow0Column0, .arcadeRow0Column1,
        .arcadeRow0Column2, .arcadeRow0Column3,
        .arcadeRow1Column0, .arcadeRow1Column1,
        .arcadeRow1Column2, .arcadeRow1Column3,
        .arcadeRow2Column0, .arcadeRow2Column1,
        .arcadeRow2Column2, .arcadeRow2Column3,
    ]
}

/// A pure, device-independent standard-controller snapshot. Extended profiles
/// populate every available field; micro profiles populate their D-pad, A/X,
/// and Menu controls and leave the unavailable fields neutral.
public struct StandardControllerSnapshot: Equatable, Sendable {
    public let dpad: ControllerDirectionState
    public let leftStick: ControllerDirectionState
    public let rightStick: ControllerDirectionState
    public let buttons: Set<StandardControllerButton>

    public init(
        dpad: ControllerDirectionState = .neutral,
        leftStick: ControllerDirectionState = .neutral,
        rightStick: ControllerDirectionState = .neutral,
        buttons: Set<StandardControllerButton> = []
    ) {
        self.dpad = dpad
        self.leftStick = leftStick
        self.rightStick = rightStick
        self.buttons = buttons
    }
}

public enum StandardControllerMapper {
    public static func elements(
        from snapshot: StandardControllerSnapshot
    ) -> Set<ControllerElement> {
        var result = Set<ControllerElement>()
        insert(
            snapshot.dpad,
            mapping: [.dpadUp, .dpadRight, .dpadDown, .dpadLeft],
            into: &result
        )
        insert(
            snapshot.leftStick,
            mapping: [.leftStickUp, .leftStickRight, .leftStickDown, .leftStickLeft],
            into: &result
        )
        insert(
            snapshot.rightStick,
            mapping: [.rightStickUp, .rightStickRight, .rightStickDown, .rightStickLeft],
            into: &result
        )
        for button in snapshot.buttons {
            result.insert(element(for: button))
        }
        return result
    }

    private static func insert(
        _ direction: ControllerDirectionState,
        mapping: [ControllerElement],
        into result: inout Set<ControllerElement>
    ) {
        if direction.up { result.insert(mapping[0]) }
        if direction.right { result.insert(mapping[1]) }
        if direction.down { result.insert(mapping[2]) }
        if direction.left { result.insert(mapping[3]) }
    }

    fileprivate static func element(
        for button: StandardControllerButton
    ) -> ControllerElement {
        switch button {
        case .north: .buttonNorth
        case .east: .buttonEast
        case .south: .buttonSouth
        case .west: .buttonWest
        case .leftShoulder: .leftShoulder
        case .rightShoulder: .rightShoulder
        case .leftTrigger: .leftTrigger
        case .rightTrigger: .rightTrigger
        case .leftStick: .leftStickButton
        case .rightStick: .rightStickButton
        case .menu: .menu
        case .options: .options
        case .leftBumper: .leftBumper
        case .rightBumper: .rightBumper
        case .share: .share
        case .backLeftPrimary: .backLeftPrimary
        case .backLeftSecondary: .backLeftSecondary
        case .backRightPrimary: .backRightPrimary
        case .backRightSecondary: .backRightSecondary
        case .paddleOne: .paddleOne
        case .paddleTwo: .paddleTwo
        case .paddleThree: .paddleThree
        case .paddleFour: .paddleFour
        case .touchpadButton: .touchpadButton
        }
    }
}

/// Reduces independent controller snapshots into one gameplay input set. A
/// disconnect removes only the departing device, preserving held controls from
/// every other connected controller.
public struct ControllerInputReducer<ID: Hashable & Sendable>: Sendable {
    private var elementsByController: [ID: Set<ControllerElement>] = [:]

    public init() {}

    public var connectedCount: Int { elementsByController.count }

    public var pressedElements: Set<ControllerElement> {
        elementsByController.values.reduce(into: Set<ControllerElement>()) {
            $0.formUnion($1)
        }
    }

    @discardableResult
    public mutating func update(
        _ elements: Set<ControllerElement>,
        for controller: ID
    ) -> Bool {
        let previous = pressedElements
        elementsByController[controller] = elements
        return previous != pressedElements
    }

    @discardableResult
    public mutating func disconnect(_ controller: ID) -> Bool {
        let previous = pressedElements
        elementsByController.removeValue(forKey: controller)
        return previous != pressedElements
    }

    /// Clears held input without forgetting which controllers are connected.
    /// The app uses this when it becomes inactive, because macOS does not
    /// forward background controller releases by default.
    @discardableResult
    public mutating func neutralize() -> Bool {
        let previous = pressedElements
        for controller in Array(elementsByController.keys) {
            elementsByController[controller] = []
        }
        return previous != pressedElements
    }
}

/// Reduces the standardized controls exposed by every connected controller.
/// This mirrors `ControllerInputReducer` for capabilities: a second device can
/// add missing controls, while disconnecting it removes only its contribution.
public struct ControllerCapabilityReducer<ID: Hashable & Sendable>: Sendable {
    private var elementsByController: [ID: Set<ControllerElement>] = [:]

    public init() {}

    public var connectedCount: Int { elementsByController.count }

    public var availableElements: Set<ControllerElement> {
        elementsByController.values.reduce(into: Set<ControllerElement>()) {
            $0.formUnion($1)
        }
    }

    @discardableResult
    public mutating func update(
        _ elements: Set<ControllerElement>,
        for controller: ID
    ) -> Bool {
        let previous = availableElements
        elementsByController[controller] = elements
        return previous != availableElements
    }

    @discardableResult
    public mutating func disconnect(_ controller: ID) -> Bool {
        let previous = availableElements
        elementsByController.removeValue(forKey: controller)
        return previous != availableElements
    }
}

public enum ControllerMappingPreset: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case twinCluster
    case dualStick
    case faceDiamond
    case custom

    public var id: Self { self }

    public var title: String {
        switch self {
        case .twinCluster: "D-pad + Right Stick"
        case .dualStick: "Dual Sticks"
        case .faceDiamond: "D-pad + Face Diamond"
        case .custom: "Custom"
        }
    }

    public var detail: String {
        switch self {
        case .twinCluster:
            "X uses the D-pad and Y uses the right stick—the SwanSong default."
        case .dualStick:
            "X uses the left stick and Y uses the right stick."
        case .faceDiamond:
            "X uses the D-pad and Y uses the four face buttons; actions move to the right shoulder and trigger."
        case .custom:
            "A binding has been customized for this controller layout."
        }
    }
}

public struct ControllerBinding: Codable, Equatable, Sendable {
    public let control: WonderSwanControl
    public let element: ControllerElement

    public init(control: WonderSwanControl, element: ControllerElement) {
        self.control = control
        self.element = element
    }
}

public struct ControllerProfile: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let preset: ControllerMappingPreset
    public let bindings: [ControllerBinding]

    public init(
        schemaVersion: Int = 1,
        preset: ControllerMappingPreset,
        bindings: [ControllerBinding]
    ) {
        self.schemaVersion = schemaVersion
        self.preset = preset
        var usedControls = Set<WonderSwanControl>()
        var usedElements = Set<ControllerElement>()
        let byControl = Dictionary(grouping: bindings, by: \.control)
        self.bindings = WonderSwanControl.allCases.compactMap { control in
            guard let binding = byControl[control]?.last,
                  usedControls.insert(control).inserted,
                  usedElements.insert(binding.element).inserted else { return nil }
            return ControllerBinding(control: control, element: binding.element)
        }
    }

    public static let `default` = preset(.twinCluster)

    public static func preset(_ preset: ControllerMappingPreset) -> ControllerProfile {
        let bindings: [ControllerBinding]
        switch preset {
        case .twinCluster, .custom:
            bindings = directionalBindings(
                x: [.dpadUp, .dpadRight, .dpadDown, .dpadLeft],
                y: [.rightStickUp, .rightStickRight, .rightStickDown, .rightStickLeft]
            ) + actionBindings(a: .buttonEast, b: .buttonSouth)
        case .dualStick:
            bindings = directionalBindings(
                x: [.leftStickUp, .leftStickRight, .leftStickDown, .leftStickLeft],
                y: [.rightStickUp, .rightStickRight, .rightStickDown, .rightStickLeft]
            ) + actionBindings(a: .buttonEast, b: .buttonSouth)
        case .faceDiamond:
            bindings = directionalBindings(
                x: [.dpadUp, .dpadRight, .dpadDown, .dpadLeft],
                y: [.buttonNorth, .buttonEast, .buttonSouth, .buttonWest]
            ) + actionBindings(a: .rightShoulder, b: .rightTrigger)
        }
        return ControllerProfile(
            preset: preset == .custom ? .twinCluster : preset,
            bindings: bindings
        )
    }

    public func element(for control: WonderSwanControl) -> ControllerElement? {
        bindings.first { $0.control == control }?.element
    }

    public func control(for element: ControllerElement) -> WonderSwanControl? {
        bindings.first { $0.element == element }?.control
    }

    public func input(for pressedElements: Set<ControllerElement>) -> EngineInput {
        var result: EngineInput = []
        for binding in bindings where pressedElements.contains(binding.element) {
            result.insert(binding.control.engineInput)
        }
        return result
    }

    /// Saved bindings that cannot be emitted by the currently connected
    /// standardized controller surfaces. The order remains WonderSwan-native
    /// so capability warnings are stable and easy to scan.
    public func unavailableBindings(
        for availableElements: Set<ControllerElement>
    ) -> [ControllerBinding] {
        bindings.filter { !availableElements.contains($0.element) }
    }

    public func updating(
        _ control: WonderSwanControl,
        to element: ControllerElement?
    ) -> ControllerProfile {
        var updated = bindings.filter {
            $0.control != control && (element == nil || $0.element != element)
        }
        if let element {
            updated.append(ControllerBinding(control: control, element: element))
        }
        return ControllerProfile(preset: .custom, bindings: updated)
    }

    private static func directionalBindings(
        x: [ControllerElement],
        y: [ControllerElement]
    ) -> [ControllerBinding] {
        let controls: [WonderSwanControl] = [.x1, .x2, .x3, .x4, .y1, .y2, .y3, .y4]
        return zip(controls, x + y).map(ControllerBinding.init)
    }

    private static func actionBindings(
        a: ControllerElement,
        b: ControllerElement
    ) -> [ControllerBinding] {
        [
            ControllerBinding(control: .a, element: a),
            ControllerBinding(control: .b, element: b),
            ControllerBinding(control: .start, element: .menu),
            ControllerBinding(control: .volume, element: .leftShoulder),
        ]
    }
}

public struct ControllerProfileStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultStore(fileManager: FileManager = .default) -> Self {
        let root = SwanSongDataRootPolicy.defaultResolution(fileManager: fileManager).rootURL
        return Self(
            fileURL: root
                .appendingPathComponent("ControllerProfile.json")
        )
    }

    public func load() throws -> ControllerProfile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .default
        }
        let profile = try JSONDecoder().decode(
            ControllerProfile.self,
            from: Data(contentsOf: fileURL)
        )
        guard profile.schemaVersion == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return ControllerProfile(
            schemaVersion: profile.schemaVersion,
            preset: profile.preset,
            bindings: profile.bindings
        )
    }

    public func save(_ profile: ControllerProfile) throws {
        guard profile.schemaVersion == 1 else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(profile).write(to: fileURL, options: [.atomic])
    }
}
