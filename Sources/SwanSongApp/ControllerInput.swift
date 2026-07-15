@preconcurrency import Foundation
@preconcurrency import GameController
import SwanSongKit

@MainActor
final class ControllerInput {
    var onChange: ((Set<ControllerElement>) -> Void)?
    var onConnectionChange: ((String?) -> Void)?

    nonisolated(unsafe) private var connectObserver: NSObjectProtocol?
    nonisolated(unsafe) private var disconnectObserver: NSObjectProtocol?
    private weak var activeController: GCController?
    private(set) var pressedElements: Set<ControllerElement> = []

    var connectedControllerName: String? {
        guard let activeController else { return nil }
        return activeController.vendorName ?? activeController.productCategory
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
                guard let self else { return }
                guard self.activeController === disconnected else { return }
                self.activeController = nil
                self.pressedElements = []
                self.onChange?([])
                self.onConnectionChange?(nil)
                if let replacement = GCController.controllers().first {
                    self.configure(replacement)
                }
            }
        }
        if let controller = GCController.controllers().first {
            configure(controller)
        }
        GCController.startWirelessControllerDiscovery()
    }

    deinit {
        if let connectObserver { NotificationCenter.default.removeObserver(connectObserver) }
        if let disconnectObserver { NotificationCenter.default.removeObserver(disconnectObserver) }
    }

    private func configure(_ controller: GCController) {
        activeController = controller
        onConnectionChange?(connectedControllerName)
        controller.extendedGamepad?.valueChangedHandler = { [weak self, weak controller] _, _ in
            guard let gamepad = controller?.extendedGamepad else { return }
            let elements = Self.elements(from: gamepad)
            Task { @MainActor [weak self] in
                guard self?.activeController === controller else { return }
                self?.pressedElements = elements
                self?.onChange?(elements)
            }
        }
    }

    private nonisolated static func elements(from gamepad: GCExtendedGamepad) -> Set<ControllerElement> {
        var elements = Set<ControllerElement>()
        insertDirections(
            gamepad.dpad,
            [.dpadUp, .dpadRight, .dpadDown, .dpadLeft],
            into: &elements
        )
        insertDirections(
            gamepad.leftThumbstick,
            [.leftStickUp, .leftStickRight, .leftStickDown, .leftStickLeft],
            into: &elements
        )
        insertDirections(
            gamepad.rightThumbstick,
            [.rightStickUp, .rightStickRight, .rightStickDown, .rightStickLeft],
            into: &elements
        )
        if gamepad.buttonY.isPressed { elements.insert(.buttonNorth) }
        if gamepad.buttonB.isPressed { elements.insert(.buttonEast) }
        if gamepad.buttonA.isPressed { elements.insert(.buttonSouth) }
        if gamepad.buttonX.isPressed { elements.insert(.buttonWest) }
        if gamepad.leftShoulder.isPressed { elements.insert(.leftShoulder) }
        if gamepad.rightShoulder.isPressed { elements.insert(.rightShoulder) }
        if gamepad.leftTrigger.isPressed { elements.insert(.leftTrigger) }
        if gamepad.rightTrigger.isPressed { elements.insert(.rightTrigger) }
        if gamepad.leftThumbstickButton?.isPressed == true { elements.insert(.leftStickButton) }
        if gamepad.rightThumbstickButton?.isPressed == true { elements.insert(.rightStickButton) }
        if gamepad.buttonMenu.isPressed { elements.insert(.menu) }
        if gamepad.buttonOptions?.isPressed == true { elements.insert(.options) }
        return elements
    }

    private nonisolated static func insertDirections(
        _ pad: GCControllerDirectionPad,
        _ mapping: [ControllerElement],
        into elements: inout Set<ControllerElement>
    ) {
        if pad.up.isPressed { elements.insert(mapping[0]) }
        if pad.right.isPressed { elements.insert(mapping[1]) }
        if pad.down.isPressed { elements.insert(mapping[2]) }
        if pad.left.isPressed { elements.insert(mapping[3]) }
    }
}
