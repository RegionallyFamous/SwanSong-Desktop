@preconcurrency import Foundation
@preconcurrency import GameController
import SwanSongKit

enum ControllerBatteryChargeState: Equatable, Sendable {
    case unknown
    case discharging
    case charging
    case full
}

struct ControllerBatterySummary: Equatable, Sendable {
    let level: Double
    let state: ControllerBatteryChargeState

    init(level: Double, state: ControllerBatteryChargeState) {
        self.level = min(max(level, 0), 1)
        self.state = state
    }

    var percentage: Int {
        Int((level * 100).rounded())
    }

    var isLow: Bool {
        percentage <= 20 && state == .discharging
    }

    var statusText: String {
        switch state {
        case .charging:
            "\(percentage)% · Charging"
        case .full:
            "100% · Fully charged"
        case .unknown, .discharging:
            "\(percentage)% battery"
        }
    }

    var symbolName: String {
        if state == .charging { return "battery.100percent.bolt" }
        return switch percentage {
        case 76...: "battery.100percent"
        case 51...: "battery.75percent"
        case 26...: "battery.50percent"
        case 1...: "battery.25percent"
        default: "battery.0percent"
        }
    }
}

@MainActor
final class ControllerInput {
    var onChange: ((Set<ControllerElement>) -> Void)?
    var onConnectionChange: ((String?, Set<ControllerElement>, ControllerBatterySummary?) -> Void)?

    nonisolated(unsafe) private var connectObserver: NSObjectProtocol?
    nonisolated(unsafe) private var disconnectObserver: NSObjectProtocol?
    nonisolated(unsafe) private var customizationObserver: NSObjectProtocol?
    private var controllers: [ObjectIdentifier: GCController] = [:]
    private var controllerNames: [ObjectIdentifier: String] = [:]
    private var reducer = ControllerInputReducer<ObjectIdentifier>()
    private var capabilityReducer = ControllerCapabilityReducer<ObjectIdentifier>()
    private var acceptsGameplayInput = true
    private var lastPublishedBatterySummary: ControllerBatterySummary?
    nonisolated(unsafe) private var batteryRefreshTimer: Timer?
    private(set) var pressedElements: Set<ControllerElement> = []

    var availableElements: Set<ControllerElement> {
        capabilityReducer.availableElements
    }

    var connectedControllerName: String? {
        switch controllerNames.count {
        case 0:
            return nil
        case 1:
            return controllerNames.values.first
        default:
            return "\(controllerNames.count) controllers connected"
        }
    }

    var batterySummary: ControllerBatterySummary? {
        controllers.values.compactMap(Self.batterySummary(for:)).min {
            $0.level < $1.level
        }
    }

    init() {
        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            Task { @MainActor [weak self] in
                self?.configure(controller)
            }
        }
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let disconnected = notification.object as? GCController else { return }
            Task { @MainActor [weak self] in
                self?.disconnect(disconnected)
            }
        }
        customizationObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerUserCustomizationsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            Task { @MainActor [weak self] in
                self?.refresh(controller)
            }
        }
        for controller in GCController.controllers() where Self.supports(controller) {
            configure(controller)
        }
        GCController.startWirelessControllerDiscovery()
    }

    deinit {
        batteryRefreshTimer?.invalidate()
        for controller in controllers.values {
            controller.physicalInputProfile.valueDidChangeHandler = nil
        }
        if let connectObserver { NotificationCenter.default.removeObserver(connectObserver) }
        if let disconnectObserver { NotificationCenter.default.removeObserver(disconnectObserver) }
        if let customizationObserver {
            NotificationCenter.default.removeObserver(customizationObserver)
        }
    }

    private func configure(_ controller: GCController) {
        let identifier = ObjectIdentifier(controller)
        guard controllers[identifier] == nil else { return }

        let profile = controller.physicalInputProfile
        let snapshot = Self.snapshot(from: profile)
        guard StandardControllerPhysicalMapper.supportsGameplay(snapshot) else {
            return
        }
        let elements = StandardControllerPhysicalMapper.elements(from: snapshot)
        profile.valueDidChangeHandler = { [weak self, weak controller] _, _ in
            Task { @MainActor [weak self, weak controller] in
                guard let controller else { return }
                self?.receiveCurrentState(from: controller)
            }
        }

        controllers[identifier] = controller
        controllerNames[identifier] = Self.displayName(for: controller)
        capabilityReducer.update(
            StandardControllerPhysicalMapper.availableElements(from: snapshot),
            for: identifier
        )
        let changed = reducer.update(
            acceptsGameplayInput ? elements : [],
            for: identifier
        )
        publishInputIfNeeded(changed)
        updateBatteryRefreshTimer()
        publishConnection()
    }

    private func receiveCurrentState(from controller: GCController) {
        let identifier = ObjectIdentifier(controller)
        guard acceptsGameplayInput,
              controllers[identifier] === controller else { return }
        let elements = StandardControllerPhysicalMapper.elements(
            from: Self.snapshot(from: controller.physicalInputProfile)
        )
        publishInputIfNeeded(reducer.update(elements, for: identifier))
        publishBatteryIfChanged()
    }

    private func refresh(_ controller: GCController) {
        let identifier = ObjectIdentifier(controller)
        guard controllers[identifier] === controller else {
            configure(controller)
            return
        }
        let snapshot = Self.snapshot(from: controller.physicalInputProfile)
        guard StandardControllerPhysicalMapper.supportsGameplay(snapshot) else {
            disconnect(controller)
            return
        }
        let elements = StandardControllerPhysicalMapper.elements(from: snapshot)
        publishInputIfNeeded(
            reducer.update(
                acceptsGameplayInput ? elements : [],
                for: identifier
            )
        )
        capabilityReducer.update(
            StandardControllerPhysicalMapper.availableElements(from: snapshot),
            for: identifier
        )
        publishConnection()
    }

    /// Stops gameplay input while retaining connected-controller identity and
    /// capabilities. macOS intentionally suppresses controller events while
    /// an app is not frontmost, so held state must be made neutral explicitly.
    func suspendGameplayInput() {
        acceptsGameplayInput = false
        publishInputIfNeeded(reducer.neutralize())
    }

    /// Re-reads every connected controller after activation. This observes
    /// releases that happened while background events were suppressed and
    /// restores only controls that are physically held now.
    func resumeGameplayInput() {
        acceptsGameplayInput = true
        var changed = false
        for controller in Array(controllers.values) {
            let identifier = ObjectIdentifier(controller)
            let snapshot = Self.snapshot(from: controller.physicalInputProfile)
            guard StandardControllerPhysicalMapper.supportsGameplay(snapshot) else {
                disconnect(controller)
                continue
            }
            changed = reducer.update(
                StandardControllerPhysicalMapper.elements(from: snapshot),
                for: identifier
            ) || changed
            capabilityReducer.update(
                StandardControllerPhysicalMapper.availableElements(from: snapshot),
                for: identifier
            )
        }
        publishInputIfNeeded(changed)
        publishConnection()
    }

    private func disconnect(_ controller: GCController) {
        let identifier = ObjectIdentifier(controller)
        guard controllers[identifier] === controller else { return }
        controller.physicalInputProfile.valueDidChangeHandler = nil
        controllers.removeValue(forKey: identifier)
        controllerNames.removeValue(forKey: identifier)
        capabilityReducer.disconnect(identifier)
        let changed = reducer.disconnect(identifier)
        publishInputIfNeeded(changed)
        updateBatteryRefreshTimer()
        publishConnection()
    }

    private func publishInputIfNeeded(_ changed: Bool) {
        guard changed || pressedElements != reducer.pressedElements else { return }
        pressedElements = reducer.pressedElements
        onChange?(pressedElements)
    }

    private func publishConnection() {
        let summary = batterySummary
        lastPublishedBatterySummary = summary
        onConnectionChange?(connectedControllerName, availableElements, summary)
    }

    private func publishBatteryIfChanged() {
        let summary = batterySummary
        guard summary != lastPublishedBatterySummary else { return }
        lastPublishedBatterySummary = summary
        onConnectionChange?(connectedControllerName, availableElements, summary)
    }

    private func updateBatteryRefreshTimer() {
        if controllers.isEmpty {
            batteryRefreshTimer?.invalidate()
            batteryRefreshTimer = nil
        } else if batteryRefreshTimer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) {
                [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.publishBatteryIfChanged()
                }
            }
            timer.tolerance = 5
            batteryRefreshTimer = timer
        }
    }

    private nonisolated static func supports(_ controller: GCController) -> Bool {
        StandardControllerPhysicalMapper.supportsGameplay(
            snapshot(from: controller.physicalInputProfile)
        )
    }

    private nonisolated static func displayName(for controller: GCController) -> String {
        for candidate in [controller.vendorName, controller.productCategory] {
            if let name = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return name
            }
        }
        return "Game Controller"
    }

    private nonisolated static func batterySummary(
        for controller: GCController
    ) -> ControllerBatterySummary? {
        guard let battery = controller.battery,
              battery.batteryLevel >= 0 else { return nil }
        let state: ControllerBatteryChargeState
        switch battery.batteryState {
        case .discharging:
            state = .discharging
        case .charging:
            state = .charging
        case .full:
            state = .full
        case .unknown:
            state = .unknown
        @unknown default:
            state = .unknown
        }
        return ControllerBatterySummary(
            level: Double(battery.batteryLevel),
            state: state
        )
    }

    private nonisolated static func snapshot(
        from profile: GCPhysicalInputProfile
    ) -> StandardControllerPhysicalSnapshot {
        var availableDirections = Set<StandardControllerDirectionAlias>()
        var directions: [
            StandardControllerDirectionAlias: ControllerDirectionState
        ] = [:]
        for (name, alias) in directionAliases {
            guard let pad = profile.dpads[name] else { continue }
            availableDirections.insert(alias)
            directions[alias] = direction(from: pad)
        }

        var availableButtons = Set<StandardControllerButtonAlias>()
        var pressedButtons = Set<StandardControllerButtonAlias>()
        var seenButtons = Set<ObjectIdentifier>()
        for (name, alias) in buttonAliases + arcadeButtonAliases {
            guard let button = profile.buttons[name] else { continue }
            // A physical button may have both an Extended/Micro alias and an
            // arcade-grid alias. Prefer the earlier core alias so one press
            // never emits two logical controls.
            guard seenButtons.insert(ObjectIdentifier(button)).inserted else {
                continue
            }
            availableButtons.insert(alias)
            if button.isPressed { pressedButtons.insert(alias) }
        }
        return StandardControllerPhysicalSnapshot(
            availableDirections: availableDirections,
            availableButtons: availableButtons,
            directions: directions,
            pressedButtons: pressedButtons
        )
    }

    private nonisolated static let directionAliases: [
        (String, StandardControllerDirectionAlias)
    ] = [
        (GCInputDirectionPad, .directionPad),
        (GCInputLeftThumbstick, .leftThumbstick),
        (GCInputRightThumbstick, .rightThumbstick),
        (GCInputMicroGamepadDpad, .microDirectionPad),
        (GCInputDirectionalDpad, .directionalDirectionPad),
        (GCInputDirectionalCardinalDpad, .directionalCardinalDirectionPad),
    ]

    private nonisolated static var buttonAliases: [
        (String, StandardControllerButtonAlias)
    ] {
        var aliases: [(String, StandardControllerButtonAlias)] = [
            (GCInputButtonA, .buttonA),
            (GCInputButtonB, .buttonB),
            (GCInputButtonX, .buttonX),
            (GCInputButtonY, .buttonY),
            (GCInputLeftShoulder, .leftShoulder),
            (GCInputRightShoulder, .rightShoulder),
            (GCInputLeftTrigger, .leftTrigger),
            (GCInputRightTrigger, .rightTrigger),
            (GCInputLeftThumbstickButton, .leftThumbstick),
            (GCInputRightThumbstickButton, .rightThumbstick),
            (GCInputButtonMenu, .menu),
            (GCInputButtonOptions, .options),
            (GCInputButtonShare, .share),
            (GCInputDualShockTouchpadButton, .touchpadButton),
        ]
        if #available(macOS 14.4, *) {
            // Prefer Apple's cross-vendor back-button positions when a device
            // exposes the same physical paddle under both generic and Xbox
            // aliases. Snapshot de-duplication keeps the first identity.
            aliases += [
                (GCButtonElementName.leftBumper.rawValue, .leftBumper),
                (GCButtonElementName.rightBumper.rawValue, .rightBumper),
                (GCButtonElementName.backLeftButton(position: 0).rawValue,
                 .backLeftPrimary),
                (GCButtonElementName.backLeftButton(position: 1).rawValue,
                 .backLeftSecondary),
                (GCButtonElementName.backRightButton(position: 0).rawValue,
                 .backRightPrimary),
                (GCButtonElementName.backRightButton(position: 1).rawValue,
                 .backRightSecondary),
            ]
        }
        aliases += [
            (GCInputXboxPaddleOne, .paddleOne),
            (GCInputXboxPaddleTwo, .paddleTwo),
            (GCInputXboxPaddleThree, .paddleThree),
            (GCInputXboxPaddleFour, .paddleFour),
            (GCInputMicroGamepadButtonA, .microButtonA),
            (GCInputMicroGamepadButtonX, .microButtonX),
            (GCInputMicroGamepadButtonMenu, .microMenu),
            (GCInputDirectionalTouchSurfaceButton, .directionalTouchSurface),
            (GCInputDirectionalCenterButton, .directionalCenter),
        ]
        return aliases
    }

    /// Apple's arcade aliases are positional rather than vendor-labelled.
    /// SwanSong supports a bounded three-row, four-column panel: the common
    /// two gameplay rows plus one service-button row. Larger panels retain
    /// their core aliases but intentionally do not acquire guessed mappings.
    private nonisolated static let arcadeButtonAliases: [
        (String, StandardControllerButtonAlias)
    ] = [
        (GCButtonElementName.arcadeButton(row: 0, column: 0).rawValue,
         .arcadeRow0Column0),
        (GCButtonElementName.arcadeButton(row: 0, column: 1).rawValue,
         .arcadeRow0Column1),
        (GCButtonElementName.arcadeButton(row: 0, column: 2).rawValue,
         .arcadeRow0Column2),
        (GCButtonElementName.arcadeButton(row: 0, column: 3).rawValue,
         .arcadeRow0Column3),
        (GCButtonElementName.arcadeButton(row: 1, column: 0).rawValue,
         .arcadeRow1Column0),
        (GCButtonElementName.arcadeButton(row: 1, column: 1).rawValue,
         .arcadeRow1Column1),
        (GCButtonElementName.arcadeButton(row: 1, column: 2).rawValue,
         .arcadeRow1Column2),
        (GCButtonElementName.arcadeButton(row: 1, column: 3).rawValue,
         .arcadeRow1Column3),
        (GCButtonElementName.arcadeButton(row: 2, column: 0).rawValue,
         .arcadeRow2Column0),
        (GCButtonElementName.arcadeButton(row: 2, column: 1).rawValue,
         .arcadeRow2Column1),
        (GCButtonElementName.arcadeButton(row: 2, column: 2).rawValue,
         .arcadeRow2Column2),
        (GCButtonElementName.arcadeButton(row: 2, column: 3).rawValue,
         .arcadeRow2Column3),
    ]

    private nonisolated static func direction(
        from pad: GCControllerDirectionPad
    ) -> ControllerDirectionState {
        ControllerDirectionState(
            xAxis: pad.xAxis.value,
            yAxis: pad.yAxis.value
        )
    }
}
