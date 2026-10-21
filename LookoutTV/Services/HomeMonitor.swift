import Foundation
import HomeKit
import Observation

/// A HomeKit camera the board can show.
struct CameraEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let room: String
    /// Nil in demo mode.
    let profile: HMCameraProfile?

    static func == (lhs: CameraEntry, rhs: CameraEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One accessory's current state, as the Home panel displays it.
struct HomeStatusItem: Identifiable, Hashable {
    let id: String
    let name: String
    let room: String
    let kind: HomeAccessoryKind
    let symbolName: String
    let stateText: String
    /// Unlocked door, open garage, jammed lock: something worth a glance.
    let isAlert: Bool
    let isReachable: Bool
    /// Temperature in Celsius, when the accessory reports one.
    let celsius: Double?
}

/// Reads the primary home on this Apple TV and keeps lock, door and sensor
/// states current through HomeKit notifications. Cameras are exposed for the
/// cameras panel to snapshot and stream.
@Observable
final class HomeMonitor: NSObject, HMHomeManagerDelegate, HMAccessoryDelegate {
    private var manager: HMHomeManager?
    private(set) var isReady = false
    private(set) var isDenied = false
    private(set) var cameras: [CameraEntry] = []
    private(set) var statuses: [HomeStatusItem] = []

    func start() {
        guard manager == nil else { return }
        if LookoutStore.isDemo {
            cameras = [
                CameraEntry(id: "demo-cam-1", name: "Front Right Camera", room: "Outside", profile: nil),
                CameraEntry(id: "demo-cam-2", name: "Porch Camera", room: "Outside", profile: nil),
                CameraEntry(id: "demo-cam-3", name: "Walkway Camera", room: "Outside", profile: nil),
            ]
            statuses = [
                HomeStatusItem(id: "demo-1", name: "Back Door", room: "Kitchen", kind: .lock, symbolName: "lock.fill",
                               stateText: "Locked", isAlert: false, isReachable: true, celsius: nil),
                HomeStatusItem(id: "demo-2", name: "Front Door", room: "Entry", kind: .lock, symbolName: "lock.fill",
                               stateText: "Locked", isAlert: false, isReachable: true, celsius: nil),
                HomeStatusItem(id: "demo-3", name: "Laundry Door", room: "Laundry", kind: .lock, symbolName: "lock.open.fill",
                               stateText: "Unlocked", isAlert: true, isReachable: true, celsius: nil),
                HomeStatusItem(id: "demo-4", name: "Garage", room: "Garage", kind: .garageDoor, symbolName: "door.garage.closed",
                               stateText: "Closed", isAlert: false, isReachable: true, celsius: nil),
                HomeStatusItem(id: "demo-5", name: "Office", room: "Office", kind: .temperature, symbolName: "thermometer.medium",
                               stateText: "", isAlert: false, isReachable: true, celsius: 22.5),
            ]
            isReady = true
            return
        }
        let manager = HMHomeManager()
        manager.delegate = self
        self.manager = manager
    }

    /// Re-reads every tracked characteristic. Called on a slow timer as a
    /// backstop for missed notifications.
    func refreshValues() {
        guard let manager else { return }
        for home in manager.homes {
            for accessory in home.accessories {
                guard let (service, kind) = accessory.lookoutStatusService else { continue }
                for characteristic in Self.trackedCharacteristics(in: service, kind: kind) {
                    characteristic.readValue { _ in
                        Task { @MainActor [weak self] in self?.rebuild() }
                    }
                }
            }
        }
    }

    // MARK: HMHomeManagerDelegate

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        subscribe(manager)
        rebuild()
    }

    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        isDenied = status.contains(.determined) && !status.contains(.authorized)
    }

    func homeManager(_ manager: HMHomeManager, didAdd home: HMHome) { subscribe(manager); rebuild() }
    func homeManager(_ manager: HMHomeManager, didRemove home: HMHome) { rebuild() }

    // MARK: HMAccessoryDelegate

    func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        rebuild()
    }

    func accessoryDidUpdateReachability(_ accessory: HMAccessory) {
        rebuild()
    }

    // MARK: Private

    private func subscribe(_ manager: HMHomeManager) {
        for home in manager.homes {
            for accessory in home.accessories {
                accessory.delegate = self
                guard let (service, kind) = accessory.lookoutStatusService else { continue }
                for characteristic in Self.trackedCharacteristics(in: service, kind: kind) {
                    characteristic.enableNotification(true) { _ in }
                    characteristic.readValue { _ in
                        Task { @MainActor [weak self] in self?.rebuild() }
                    }
                }
            }
        }
    }

    private static func trackedCharacteristics(in service: HMService, kind: HomeAccessoryKind) -> [HMCharacteristic] {
        let types: [String]
        switch kind {
        case .lock: types = [HMCharacteristicTypeCurrentLockMechanismState]
        case .garageDoor: types = [HMCharacteristicTypeCurrentDoorState]
        case .door, .window: types = [HMCharacteristicTypeCurrentPosition]
        case .contactSensor: types = [HMCharacteristicTypeContactState]
        case .motionSensor: types = [HMCharacteristicTypeMotionDetected]
        case .temperature: types = [HMCharacteristicTypeCurrentTemperature]
        case .doorbell: types = []
        }
        return service.characteristics.filter { types.contains($0.characteristicType) }
    }

    private func rebuild() {
        guard let manager else { return }
        var cameras: [CameraEntry] = []
        var statuses: [HomeStatusItem] = []
        for home in manager.homes {
            for accessory in home.accessories {
                let room = accessory.room?.name ?? ""
                if let profile = accessory.cameraProfiles?.first {
                    cameras.append(CameraEntry(id: accessory.uniqueIdentifier.uuidString,
                                               name: accessory.name, room: room, profile: profile))
                }
                if let (service, kind) = accessory.lookoutStatusService {
                    statuses.append(Self.status(for: accessory, service: service, kind: kind, room: room))
                }
            }
        }
        self.cameras = cameras.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.statuses = statuses.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        isReady = true
    }

    private static func status(for accessory: HMAccessory, service: HMService,
                               kind: HomeAccessoryKind, room: String) -> HomeStatusItem {
        func value(_ type: String) -> Any? {
            service.characteristics.first { $0.characteristicType == type }?.value
        }
        var symbol = kind.symbolName
        var text = "—"
        var alert = false
        var celsius: Double? = nil
        switch kind {
        case .lock:
            switch value(HMCharacteristicTypeCurrentLockMechanismState) as? Int {
            case 0?: text = "Unlocked"; symbol = "lock.open.fill"; alert = true
            case 1?: text = "Locked"; symbol = "lock.fill"
            case 2?: text = "Jammed"; symbol = "lock.trianglebadge.exclamationmark.fill"; alert = true
            default: text = "Unknown"; symbol = "lock"
            }
        case .garageDoor:
            switch value(HMCharacteristicTypeCurrentDoorState) as? Int {
            case 0?: text = "Open"; symbol = "door.garage.open"; alert = true
            case 1?: text = "Closed"; symbol = "door.garage.closed"
            case 2?: text = "Opening"; symbol = "door.garage.open"
            case 3?: text = "Closing"; symbol = "door.garage.closed"
            case 4?: text = "Stopped"; symbol = "door.garage.open"; alert = true
            default: text = "Unknown"
            }
        case .door, .window:
            let position = value(HMCharacteristicTypeCurrentPosition) as? Int
            let isOpen = (position ?? 0) > 0
            text = isOpen ? "Open" : "Closed"
            alert = isOpen && kind == .door
            symbol = kind == .door
                ? (isOpen ? "door.left.hand.open" : "door.left.hand.closed")
                : (isOpen ? "window.vertical.open" : "window.vertical.closed")
        case .contactSensor:
            let detected = (value(HMCharacteristicTypeContactState) as? Int) == 0
            text = detected ? "Closed" : "Open"
            alert = !detected
            symbol = detected ? "sensor.fill" : "sensor"
        case .motionSensor:
            let motion = (value(HMCharacteristicTypeMotionDetected) as? Bool) ?? false
            text = motion ? "Motion" : "Clear"
            symbol = motion ? "figure.walk.motion" : "figure.stand"
        case .temperature:
            celsius = value(HMCharacteristicTypeCurrentTemperature) as? Double
            text = ""
        case .doorbell:
            text = "Ready"
        }
        if !accessory.isReachable {
            text = "No response"
            alert = false
        }
        return HomeStatusItem(id: accessory.uniqueIdentifier.uuidString, name: accessory.name, room: room,
                              kind: kind, symbolName: symbol, stateText: text, isAlert: alert,
                              isReachable: accessory.isReachable, celsius: celsius)
    }
}
