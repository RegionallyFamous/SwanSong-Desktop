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
        }
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
