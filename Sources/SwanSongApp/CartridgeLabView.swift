import AppKit
import Foundation
import Observation
import SwanSongKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class CartridgeLabModel {
    enum Operation: Equatable {
        case connecting
        case refreshingCartridge
        case dumpingROM
        case dumpingSave
        case restoringSave
        case installingBootMedia

        var title: String {
            switch self {
            case .connecting: "Connecting"
            case .refreshingCartridge: "Refreshing cartridge"
            case .dumpingROM: "Reading cartridge"
            case .dumpingSave: "Backing up save"
            case .restoringSave: "Restoring save"
            case .installingBootMedia: "Preparing SD card"
            }
        }
    }

    var serialPorts: [YokoiSerialPortDescriptor] = []
    var selectedSerialPortPath = ""
    var serviceIdentity: YokoiServiceIdentity?
    var cartridgeInfo: YokoiCartridgeInfo?
    var operation: Operation?
    var progress: YokoiTransferProgress?
    var status = "Connect the EXT adapter, choose it below, then power on the WonderSwan when asked."
    var issue: String?
    var payloadIssue: String?
    var lastROMDump: YokoiDumpResult?
    var lastSaveDump: YokoiDumpResult?
    var installerResult: YokoiInstallerMediaResult?
    var restoreConfirmationIsPresented = false
    var pendingRestoreURL: URL?

    private(set) var payload: YokoiHardwarePayload?
    private var session: YokoiCartridgeSession?
    private var task: Task<Void, Never>?
    private var operationID = UUID()

    init(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        refreshPorts()
        do {
            let isBundledApp = bundle.bundleURL.pathExtension.lowercased() == "app"
            if !isBundledApp, let override = environment["SWAN_YOKOI_HARDWARE_DIR"] {
                payload = try YokoiHardwarePayloadLoader.load(
                    at: URL(fileURLWithPath: override, isDirectory: true)
                )
            } else if let root = YokoiHardwarePayloadLoader.bundledRoot(bundle: bundle),
                      FileManager.default.fileExists(atPath: root.path) {
                payload = try YokoiHardwarePayloadLoader.load(at: root)
            } else if !isBundledApp {
                let sourceFallback = URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Packaging/YokoiHardware", isDirectory: true)
                payload = try YokoiHardwarePayloadLoader.load(at: sourceFallback)
            } else {
                throw YokoiHardwareError.invalidFirmware(
                    "The signed app is missing its Yokoi hardware-support payload."
                )
            }
        } catch {
            payloadIssue = error.localizedDescription
        }
    }

    var isConnected: Bool { session != nil && serviceIdentity != nil }
    var isBusy: Bool { operation != nil }
    var canDumpROM: Bool {
        isConnected && cartridgeInfo?.footerIsUsable == true && (cartridgeInfo?.romSize ?? 0) > 0
    }
    var canReadSave: Bool {
        isConnected && (cartridgeInfo?.saveKind == .sram || cartridgeInfo?.saveKind == .eeprom)
            && (cartridgeInfo?.saveSize ?? 0) > 0
    }
    var canRestoreSave: Bool {
        canReadSave && cartridgeInfo?.saveGeometryIsAmbiguous == false
    }

    func refreshPorts() {
        let previous = selectedSerialPortPath
        serialPorts = YokoiSerialPortDescriptor.discover()
        if serialPorts.contains(where: { $0.path == previous }) {
            selectedSerialPortPath = previous
        } else {
            selectedSerialPortPath = serialPorts.first?.path ?? ""
        }
    }

    func connectAndLoadService() {
        guard !isBusy else { return }
        guard let payload else {
            issue = payloadIssue ?? "The Yokoi hardware-support payload is unavailable."
            return
        }
        guard !selectedSerialPortPath.isEmpty else {
            issue = "Connect a 3.3 V WonderSwan EXT-to-USB adapter, then refresh the device list."
            return
        }
        disconnect()
        do {
            session = try YokoiCartridgeSession(serialPortPath: selectedSerialPortPath)
        } catch {
            issue = error.localizedDescription
            return
        }
        guard let session else { return }
        operation = .connecting
        let operationID = beginOperation()
        progress = .init(kind: .loadingService, completed: 0, total: payload.cartService.count)
        status = "Waiting for Yokoi Boot. Insert the cartridge and power on the WonderSwan now."
        issue = nil
        task = Task { [weak self] in
            let channel = AsyncStream.makeStream(of: YokoiTransferProgress.self)
            let progressTask = Task { @MainActor [weak self] in
                for await value in channel.stream where self?.operationID == operationID {
                    self?.progress = value
                }
            }
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    try session.loadService(payload.cartService) { value in
                        channel.continuation.yield(value)
                    }
                    let identity = try session.hello()
                    let info = try session.cartridgeInfo()
                    return ConnectionOutcome.connected(identity, info)
                } catch {
                    session.close()
                    return ConnectionOutcome.failed(error.localizedDescription)
                }
            }.value
            channel.continuation.finish()
            await progressTask.value
            guard let self, self.operationID == operationID else { return }
            operation = nil
            progress = nil
            switch outcome {
            case let .connected(identity, info):
                serviceIdentity = identity
                cartridgeInfo = info
                status = "Connected to \(info.consoleName). The cartridge is ready."
            case let .failed(message):
                self.session = nil
                serviceIdentity = nil
                cartridgeInfo = nil
                issue = message
                status = "Not connected."
            }
            task = nil
        }
    }

    func refreshCartridge() {
        guard let session, !isBusy else { return }
        operation = .refreshingCartridge
        let operationID = beginOperation()
        issue = nil
        task = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    return CartridgeInfoOutcome.completed(try session.cartridgeInfo())
                } catch {
                    return CartridgeInfoOutcome.failed(error.localizedDescription)
                }
            }.value
            guard let self, self.operationID == operationID else { return }
            operation = nil
            switch outcome {
            case let .completed(info):
                cartridgeInfo = info
                status = "Cartridge information refreshed."
            case let .failed(message):
                issue = message
            }
            task = nil
        }
    }

    func disconnect() {
        task?.cancel()
        session?.close()
        operationID = UUID()
        task = nil
        session = nil
        serviceIdentity = nil
        cartridgeInfo = nil
        operation = nil
        progress = nil
    }

    func cancel() {
        task?.cancel()
        session?.close()
        operationID = UUID()
        session = nil
        serviceIdentity = nil
        cartridgeInfo = nil
        operation = nil
        progress = nil
        status = "Operation cancelled. Reconnect and power-cycle the WonderSwan before continuing."
    }

    func dumpROM(to destination: URL) {
        guard let session, let info = cartridgeInfo, canDumpROM, !isBusy else { return }
        operation = .dumpingROM
        let operationID = beginOperation()
        progress = .init(kind: .dumpingROM, completed: 0, total: Int(info.romSize))
        issue = nil
        task = Task { [weak self] in
            let channel = AsyncStream.makeStream(of: YokoiTransferProgress.self)
            let progressTask = Task { @MainActor [weak self] in
                for await value in channel.stream where self?.operationID == operationID {
                    self?.progress = value
                }
            }
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    let result = try session.dumpROM(using: info, to: destination) { value in
                        channel.continuation.yield(value)
                    }
                    return DumpOutcome.completed(result)
                } catch {
                    return DumpOutcome.failed(error.localizedDescription)
                }
            }.value
            channel.continuation.finish()
            await progressTask.value
            guard let self, self.operationID == operationID else { return }
            operation = nil
            progress = nil
            switch outcome {
            case let .completed(result):
                lastROMDump = result
                status = "Cartridge read and checksum verified."
            case let .failed(message):
                issue = message
            }
            task = nil
        }
    }

    func dumpSave(to destination: URL) {
        guard let session, let info = cartridgeInfo, canReadSave, !isBusy else { return }
        operation = .dumpingSave
        let operationID = beginOperation()
        progress = .init(kind: .dumpingSave, completed: 0, total: Int(info.saveSize))
        issue = nil
        task = Task { [weak self] in
            let channel = AsyncStream.makeStream(of: YokoiTransferProgress.self)
            let progressTask = Task { @MainActor [weak self] in
                for await value in channel.stream where self?.operationID == operationID {
                    self?.progress = value
                }
            }
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    let result = try session.dumpSave(using: info, to: destination) { value in
                        channel.continuation.yield(value)
                    }
                    return DumpOutcome.completed(result)
                } catch {
                    return DumpOutcome.failed(error.localizedDescription)
                }
            }.value
            channel.continuation.finish()
            await progressTask.value
            guard let self, self.operationID == operationID else { return }
            operation = nil
            progress = nil
            switch outcome {
            case let .completed(result):
                lastSaveDump = result
                status = "Save backup completed and verified."
            case let .failed(message):
                issue = message
            }
            task = nil
        }
    }

    func requestRestore(from source: URL) {
        guard canRestoreSave, !isBusy else { return }
        pendingRestoreURL = source
        restoreConfirmationIsPresented = true
    }

    func confirmRestore() {
        guard let session, let info = cartridgeInfo, let source = pendingRestoreURL,
              canRestoreSave, !isBusy else { return }
        pendingRestoreURL = nil
        restoreConfirmationIsPresented = false
        operation = .restoringSave
        let operationID = beginOperation()
        progress = .init(kind: .restoringSave, completed: 0, total: Int(info.saveSize))
        status = "Hold A+B on the WonderSwan when prompted. Keep the cartridge and power connected."
        issue = nil
        task = Task { [weak self] in
            let channel = AsyncStream.makeStream(of: YokoiTransferProgress.self)
            let progressTask = Task { @MainActor [weak self] in
                for await value in channel.stream where self?.operationID == operationID {
                    self?.progress = value
                }
            }
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    let image = try Data(contentsOf: source, options: [.mappedIfSafe])
                    try session.restoreSave(image, using: info) { value in
                        channel.continuation.yield(value)
                    }
                    return MessageOutcome.completed("Save restored and fully read back from the cartridge.")
                } catch {
                    return MessageOutcome.failed(error.localizedDescription)
                }
            }.value
            channel.continuation.finish()
            await progressTask.value
            guard let self, self.operationID == operationID else { return }
            operation = nil
            progress = nil
            switch outcome {
            case let .completed(message): status = message
            case let .failed(message): issue = message
            }
            task = nil
        }
    }

    func addInstaller(to selectedFolder: URL) {
        guard let payload, !isBusy else { return }
        operation = .installingBootMedia
        let operationID = beginOperation()
        issue = nil
        installerResult = nil
        task = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                let accessed = selectedFolder.startAccessingSecurityScopedResource()
                defer { if accessed { selectedFolder.stopAccessingSecurityScopedResource() } }
                do {
                    let plan = try YokoiInstallerMedia.plan(
                        payload: payload,
                        selectedFolder: selectedFolder
                    )
                    let result = try YokoiInstallerMedia.install(payload: payload, plan: plan)
                    return InstallerOutcome.completed(result, plan.volumeIsRemovable)
                } catch {
                    return InstallerOutcome.failed(error.localizedDescription)
                }
            }.value
            guard let self, self.operationID == operationID else { return }
            operation = nil
            switch outcome {
            case let .completed(result, removable):
                installerResult = result
                if result.wasAlreadyPresent {
                    status = "The verified Yokoi Boot installer was already on the selected card."
                } else if removable == false {
                    status = "Installer copied and verified. macOS did not identify the selected volume as removable; confirm that you chose the flash cartridge's SD card."
                } else {
                    status = "Installer copied and verified. Eject the SD card before removing it."
                }
            case let .failed(message):
                issue = message
            }
            task = nil
        }
    }

    private func beginOperation() -> UUID {
        let value = UUID()
        operationID = value
        return value
    }

    private enum ConnectionOutcome: @unchecked Sendable {
        case connected(YokoiServiceIdentity, YokoiCartridgeInfo)
        case failed(String)
    }

    private enum DumpOutcome: Sendable {
        case completed(YokoiDumpResult)
        case failed(String)
    }

    private enum CartridgeInfoOutcome: Sendable {
        case completed(YokoiCartridgeInfo)
        case failed(String)
    }

    private enum MessageOutcome: Sendable {
        case completed(String)
        case failed(String)
    }

    private enum InstallerOutcome: Sendable {
        case completed(YokoiInstallerMediaResult, Bool?)
        case failed(String)
    }
}

struct CartridgeLabView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case cartridges = "Cartridges"
        case setup = "Set Up Yokoi Boot"
        var id: Self { self }
    }

    let appModel: AppModel
    @State private var model = CartridgeLabModel()
    @State private var section = Section.cartridges

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("Cartridge Tools section", selection: $section) {
                ForEach(Section.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            .padding(14)
            Divider()
            ScrollView {
                Group {
                    switch section {
                    case .cartridges: cartridgeSection
                    case .setup: setupSection
                    }
                }
                .padding(20)
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 600, idealHeight: 700)
        .background(SwanTheme.libraryBackground.ignoresSafeArea())
        .alert(
            "Cartridge Tools",
            isPresented: Binding(
                get: { model.issue != nil },
                set: { if !$0 { model.issue = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.issue = nil }
        } message: {
            Text(model.issue ?? "")
        }
        .confirmationDialog(
            "Overwrite all save data on this cartridge?",
            isPresented: $model.restoreConfirmationIsPresented,
            titleVisibility: .visible
        ) {
            Button("Restore and Verify Save", role: .destructive) {
                model.confirmRestore()
            }
            Button("Cancel", role: .cancel) {
                model.pendingRestoreURL = nil
            }
        } message: {
            Text(
                "SwanSong will require A+B on the WonderSwan, verify each write, and perform a complete readback. Keep the cartridge inserted and the console powered."
            )
        }
        .onDisappear { model.disconnect() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            SwanIconTile(symbol: "externaldrive.connected.to.line.below", tint: SwanTheme.cyan, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("Cartridge Tools").font(.title2.bold())
                Text("Read cartridges and safely manage saves with a WonderSwan Color or SwanCrystal.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isBusy {
                Button("Cancel", role: .cancel) { model.cancel() }
            } else if model.isConnected {
                Button("Disconnect") { model.disconnect() }
            }
        }
        .padding(20)
    }

    private var cartridgeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            cableGuide

            labCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Connect the WonderSwan", systemImage: "cable.connector")
                        .font(.headline)
                    Text(
                        "Insert the cartridge while the console is off. Connect the EXT adapter, choose the USB device below, then let SwanSong tell you when to power on."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    HStack {
                        Picker("USB adapter", selection: $model.selectedSerialPortPath) {
                            if model.serialPorts.isEmpty {
                                Text("No EXT adapters found").tag("")
                            }
                            ForEach(model.serialPorts) { port in
                                Text(port.displayName).tag(port.path)
                            }
                        }
                        .frame(maxWidth: 360)
                        Button("Refresh Devices", systemImage: "arrow.clockwise") { model.refreshPorts() }
                        Button("Connect WonderSwan") { model.connectAndLoadService() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.selectedSerialPortPath.isEmpty || model.isBusy || model.payload == nil)
                    }
                }
            }

            if let info = model.cartridgeInfo {
                labCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Inserted cartridge", systemImage: "shippingbox.fill")
                                .font(.headline)
                            Spacer()
                            Button("Refresh") { model.refreshCartridge() }
                                .disabled(model.isBusy)
                        }
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                            infoRow("Console", info.consoleName)
                            infoRow("ROM", ByteCountFormatter.string(fromByteCount: Int64(info.romSize), countStyle: .file))
                            infoRow(
                                "Save memory",
                                info.saveSize > 0
                                    ? "\(info.saveKind.title), \(ByteCountFormatter.string(fromByteCount: Int64(info.saveSize), countStyle: .memory))\(info.saveGeometryIsAmbiguous ? " (size needs confirmation)" : "")"
                                    : info.saveKind.title
                            )
                        }
                        Divider()
                        HStack {
                            Button("Read Cartridge…", systemImage: "square.and.arrow.down") { chooseROMDestination() }
                                .buttonStyle(.borderedProminent)
                                .disabled(!model.canDumpROM || model.isBusy)
                            Button("Back Up Save…") { chooseSaveDestination() }
                                .disabled(!model.canReadSave || model.isBusy)
                            Button("Restore Save…") { chooseSaveToRestore() }
                                .disabled(!model.canRestoreSave || model.isBusy)
                        }
                        if info.saveGeometryIsAmbiguous {
                            Label(
                                "This footer's SRAM code is used by more than one physical size. Backup is available, but SwanSong will not restore a save until the cartridge geometry is identified.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    }
                }
            }

            if let dump = model.lastROMDump {
                resultCard(
                    title: "Verified cartridge dump",
                    result: dump,
                    actionTitle: "Add to SwanSong Library"
                ) {
                    appModel.importGame(at: dump.url)
                }
            }
            if let dump = model.lastSaveDump {
                resultCard(title: "Verified save backup", result: dump, actionTitle: "Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([dump.url])
                }
            }

            if appModel.debugToolsEnabled {
                developerDiagnostics
            }

            labCard(tint: .orange) {
                Label("ROM writing remains locked", systemImage: "lock.fill")
                    .font(.headline)
                Text(
                    "Retail cartridges use non-writable mask ROM. Flash-cartridge programming stays disabled until individual mapper, flash-chip, power-loss, and recovery behavior has physical-hardware evidence. Save restoration is available now."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var cableGuide: some View {
        labCard(tint: SwanTheme.cyan) {
            VStack(alignment: .leading, spacing: 12) {
                Label("USB needs a WonderSwan EXT adapter", systemImage: "cable.connector.horizontal")
                    .font(.headline)
                Text(
                    "A USB cable cannot plug directly into a WonderSwan. Use an ExtFriend-compatible adapter that converts the console's 3.3 V EXT connection to USB, then use a normal data-capable USB cable from the adapter to your Mac."
                )
                .font(.callout)
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    connectionNode("WonderSwan", detail: "EXT port", symbol: "gamecontroller.fill")
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    connectionNode("3.3 V adapter", detail: "ExtFriend-compatible", symbol: "memorychip")
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    connectionNode("Mac", detail: "USB data cable", symbol: "laptopcomputer")
                }
                .frame(maxWidth: .infinity)

                Label(
                    "Do not use a PC RS-232 cable or connect loose EXT pins directly to USB.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
                Text(
                    "Console support: WonderSwan Color and SwanCrystal. The original monochrome WonderSwan cannot use this Yokoi Boot workflow."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Link(
                    "Open the ExtFriend adapter build guide",
                    destination: URL(string: "https://github.com/asiekierka/ws-extfriend")!
                )
                .font(.caption.weight(.medium))
            }
        }
        .accessibilityIdentifier("cartridge-usb-cable-guide")
    }

    private func connectionNode(
        _ title: String,
        detail: String,
        symbol: String
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(SwanTheme.cyan)
            Text(title).font(.caption.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .padding(.horizontal, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var developerDiagnostics: some View {
        labCard(tint: SwanTheme.violet) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Developer diagnostics", systemImage: "wrench.and.screwdriver.fill")
                    .font(.headline)
                Text("Visible because Developer Tools is enabled in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                    developerRow(
                        "Serial device",
                        model.selectedSerialPortPath.isEmpty ? "Not selected" : model.selectedSerialPortPath
                    )
                    developerRow("Transport", "38,400 baud · 8-N-1 · protocol v1")
                    developerRow("Boot transfer", "128-byte XMODEM checksum blocks")
                    if let identity = model.serviceIdentity {
                        developerRow("Service", "Yokoi Cart Service \(identity.version)")
                        developerRow(
                            "Capabilities",
                            String(format: "0x%04X · max transfer %d bytes", identity.capabilities, identity.maximumTransfer)
                        )
                    }
                    if let info = model.cartridgeInfo {
                        developerRow(
                            "Console registers",
                            String(format: "model 0x%02X · control 0x%02X · flags 0x%02X", info.consoleModel, info.systemControl, info.flags)
                        )
                        developerRow("EEPROM address bits", String(info.eepromAddressBits))
                        developerRow(
                            "Raw footer",
                            info.footer.map { String(format: "%02X", $0) }.joined(separator: " ")
                        )
                    }
                    if let payload = model.payload {
                        developerRow("Payload", payload.version)
                        developerRow(
                            "Release gate",
                            payload.releaseReady ? "release-ready" : "development / hardware validation pending"
                        )
                        developerRow("Bundled source SHA-256", payload.correspondingSourceSHA256)
                        developerRow("Installer SHA-256", payload.installerSHA256)
                        developerRow("Service SHA-256", payload.cartServiceSHA256)
                    }
                }
            }
        }
        .accessibilityIdentifier("cartridge-developer-diagnostics")
    }

    @ViewBuilder
    private func developerRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            labCard(tint: SwanTheme.cyan) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Add the installer to a flash-cartridge SD card", systemImage: "sdcard.fill")
                        .font(.headline)
                    Text(
                        "Choose the SD-card folder your flash cartridge browses. SwanSong adds a verified Yokoi Boot Installer.wsc without replacing a different file."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    Button("Choose SD Card or ROM Folder…", systemImage: "externaldrive.badge.plus") {
                        chooseInstallerFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.payload == nil || model.isBusy)
                    if let payload = model.payload, appModel.debugToolsEnabled {
                        Text("Payload \(payload.version) · SHA-256 \(payload.installerSHA256)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else if let issue = model.payloadIssue {
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            if let result = model.installerResult {
                labCard(tint: .green) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            result.wasAlreadyPresent ? "Verified installer already present" : "Installer copied and verified",
                            systemImage: "checkmark.seal.fill"
                        )
                        .font(.headline)
                        Text(result.destination.path)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                        Button("Show on SD Card") {
                            NSWorkspace.shared.activateFileViewerSelecting([result.destination])
                        }
                    }
                }
            }

            if appModel.debugToolsEnabled {
                developerDiagnostics
            }

            labCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("First installation", systemImage: "1.circle.fill").font(.headline)
                    setupStep(
                        "Put the SD card back into a compatible flash cartridge with at least 8 KiB of SRAM, then select Yokoi Boot Installer from that cartridge's own menu."
                    )
                    setupStep(
                        "Boot it directly on a WonderSwan Color or SwanCrystal. Follow the console prompts and hold A+B only when asked."
                    )
                    setupStep(
                        "Keep the installer cartridge unchanged: its SRAM contains the verified 2 KiB internal-EEPROM recovery backup."
                    )
                    setupStep(
                        "Power off, insert the cartridge you want to service, then return to the Cartridges tab."
                    )
                }
            }

            labCard(tint: .orange) {
                Label("A stock console cannot be installed over EXT alone", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                Text(
                    "The SD-card step works only for flash cartridges that can browse and launch .wsc files and provide at least 8 KiB of SRAM for the recovery backup. A completely stock console still needs that bootstrap cartridge, a WonderWitch path, or direct EEPROM programming once. Original monochrome WonderSwan is unsupported."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if let operation = model.operation {
                ProgressView(value: model.progress?.fraction ?? 0)
                    .frame(width: 160)
                Text(operation.title).font(.callout.weight(.medium))
            }
            Text(model.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func labCard<Content: View>(
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .swanSurface(.standard, tint: tint, cornerRadius: 14)
    }

    @ViewBuilder
    private func infoRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).font(title == "Footer" ? .caption.monospaced() : .callout)
                .textSelection(.enabled)
        }
    }

    private func resultCard(
        title: String,
        result: YokoiDumpResult,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        labCard(tint: .green) {
            Label(title, systemImage: "checkmark.seal.fill").font(.headline)
            Text(result.url.path).font(.callout.monospaced()).textSelection(.enabled)
            if appModel.debugToolsEnabled {
                Text("SHA-256 \(result.sha256)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Button(actionTitle, action: action)
        }
    }

    private func setupStep(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(SwanTheme.cyan)
                .padding(.top, 1)
            Text(text).font(.callout)
        }
    }

    private func chooseROMDestination() {
        let panel = NSSavePanel()
        panel.title = "Save WonderSwan Cartridge Dump"
        panel.nameFieldStringValue = "cartridge.wsc"
        panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.dumpROM(to: url)
    }

    private func chooseSaveDestination() {
        let panel = NSSavePanel()
        panel.title = "Save Cartridge Save Backup"
        panel.nameFieldStringValue = "cartridge.sav"
        panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.dumpSave(to: url)
    }

    private func chooseSaveToRestore() {
        let panel = NSOpenPanel()
        panel.title = "Choose Cartridge Save to Restore"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.requestRestore(from: url)
    }

    private func chooseInstallerFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Flash-Cartridge SD Card or ROM Folder"
        panel.prompt = "Add Installer Here"
        panel.message = "Choose the folder your flash cartridge can browse. SwanSong will add one verified .wsc file."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.addInstaller(to: url)
    }
}
