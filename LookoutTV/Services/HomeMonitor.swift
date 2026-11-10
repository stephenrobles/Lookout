import Foundation
import HomeKit
import Observation

/// A HomeKit camera the board can show.
struct CameraEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let room: String
    let home: String
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
    let home: String
    let kind: HomeAccessoryKind
    let symbolName: String
    let stateText: String
    /// Unlocked door, open garage, jammed lock: something worth a glance.
    let isAlert: Bool
    let isReachable: Bool
    /// Temperature in Celsius, when the accessory reports one.
    let celsius: Double?
}

/// Reads every home this Apple TV can see and keeps light, plug, lock, door
/// and sensor states current through HomeKit notifications. Cameras are exposed for the
/// cameras panel to snapshot and stream.
@Observable
final class HomeMonitor: NSObject, HMHomeManagerDelegate, HMAccessoryDelegate {
    private var manager: HMHomeManager?
    private(set) var isReady = false
    private(set) var isDenied = false
    private(set) var cameras: [CameraEntry] = []
    private(set) var statuses: [HomeStatusItem] = []
    /// True when the account has more than one home, so names can say which.
    private(set) var hasMultipleHomes = false

    func start() {
        guard manager == nil else { return }
        if LookoutStore.isDemo {
            cameras = [
                CameraEntry(id: "demo-cam-1", name: "Front Right Camera", room: "Outside", home: "Home", profile: nil),
                CameraEntry(id: "demo-cam-2", name: "Porch Camera", room: "Outside", home: "Home", profile: nil),
                CameraEntry(id: "demo-cam-3", name: "Walkway Camera", room: "Outside", home: "Home", profile: nil),
            ]
            statuses = [
                HomeStatusItem(id: "demo-1", name: "Back Door", room: "Kitchen", home: "Home", kind: .lock, symbolName: "lock.fill",
                               stateText: String(localized: "Locked"), isAlert: false, isReachable: true, celsius: nil),
                HomeStatusItem(id: "demo-2", name: "Front Door", room: "Entry", home: "Home", kind: .lock, symbolName: "lock.fill",
                               stateText: String(localized: "Locked"), isAlert: false, isReachable: true, celsius: nil),
                HomeStatusItem(id: "demo-3", name: "Laundry Door", room: "Laundry", home: "Home", kind: .lock, symbolName: "lock.open.fill",
                               stateText: String(localized: "Unlocked"), isAlert: true, isReachable: true, celsius: nil),
                HomeStatusItem(id: "demo-4", name: "Garage", room: "Garage", home: "Home", kind: .garageDoor, symbolName: "door.garage.closed",
                               stateText: String(localized: "Closed"), isAlert: false, isReachable: true, celsius: nil),
                HomeStatusItem(id: "demo-5", name: "Office", room: "Office", home: "Home", kind: .temperature, symbolName: "thermometer.medium",
                               stateText: "", isAlert: false, isReachable: true, celsius: 22.5),
                HomeStatusItem(id: "demo-6", name: "Living Room Lamp", room: "Living Room", home: "Home", kind: .light, symbolName: "lightbulb.fill",
                               stateText: String(localized: "On · \(60)%"), isAlert: false, isReachable: true, celsius: nil),
                HomeStatusItem(id: "demo-7", name: "Christmas Tree", room: "Living Room", home: "Home", kind: .outlet, symbolName: "powerplug",
                               stateText: String(localized: "Off"), isAlert: false, isReachable: true, celsius: nil),
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
        case .light: types = [HMCharacteristicTypePowerState, HMCharacteristicTypeBrightness]
        case .outlet, .switch: types = [HMCharacteristicTypePowerState]
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
                    cameras.append(CameraEntry(id: accessory.lookoutKey(in: home),
                                               name: accessory.name, room: room, home: home.name, profile: profile))
                }
                if let (service, kind) = accessory.lookoutStatusService {
                    statuses.append(Self.status(for: accessory, in: home, service: service, kind: kind, room: room))
                }
            }
        }
        self.cameras = cameras.sorted { Self.ordered($0.home, $0.name, before: $1.home, $1.name) }
        self.statuses = statuses.sorted { Self.ordered($0.home, $0.name, before: $1.home, $1.name) }
        hasMultipleHomes = manager.homes.count > 1
        isReady = true
    }

    /// Home name first, then accessory name, so a second home's accessories
    /// stay together instead of interleaving.
    private static func ordered(_ homeA: String, _ nameA: String, before homeB: String, _ nameB: String) -> Bool {
        let homes = homeA.localizedStandardCompare(homeB)
        if homes != .orderedSame { return homes == .orderedAscending }
        return nameA.localizedStandardCompare(nameB) == .orderedAscending
    }

    private static func status(for accessory: HMAccessory, in home: HMHome, service: HMService,
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
            case 0?: text = String(localized: "Unlocked"); symbol = "lock.open.fill"; alert = true
            case 1?: text = String(localized: "Locked"); symbol = "lock.fill"
            case 2?: text = String(localized: "Jammed"); symbol = "lock.trianglebadge.exclamationmark.fill"; alert = true
            default: text = String(localized: "Unknown"); symbol = "lock"
            }
        case .garageDoor:
            switch value(HMCharacteristicTypeCurrentDoorState) as? Int {
            case 0?: text = String(localized: "Open"); symbol = "door.garage.open"; alert = true
            case 1?: text = String(localized: "Closed"); symbol = "door.garage.closed"
            case 2?: text = String(localized: "Opening"); symbol = "door.garage.open"
            case 3?: text = String(localized: "Closing"); symbol = "door.garage.closed"
            case 4?: text = String(localized: "Stopped"); symbol = "door.garage.open"; alert = true
            default: text = String(localized: "Unknown")
            }
        case .door, .window:
            let position = value(HMCharacteristicTypeCurrentPosition) as? Int
            let isOpen = (position ?? 0) > 0
            text = isOpen ? String(localized: "Open") : String(localized: "Closed")
            alert = isOpen && kind == .door
            symbol = kind == .door
                ? (isOpen ? "door.left.hand.open" : "door.left.hand.closed")
                : (isOpen ? "window.vertical.open" : "window.vertical.closed")
        case .contactSensor:
            let detected = (value(HMCharacteristicTypeContactState) as? Int) == 0
            text = detected ? String(localized: "Closed") : String(localized: "Open")
            alert = !detected
            symbol = detected ? "sensor.fill" : "sensor"
        case .motionSensor:
            let motion = (value(HMCharacteristicTypeMotionDetected) as? Bool) ?? false
            text = motion ? String(localized: "Motion") : String(localized: "Clear")
            symbol = motion ? "figure.walk.motion" : "figure.stand"
        case .temperature:
            celsius = value(HMCharacteristicTypeCurrentTemperature) as? Double
            text = ""
        case .doorbell:
            text = String(localized: "Ready")
        case .light:
            let on = (value(HMCharacteristicTypePowerState) as? Bool) ?? false
            if on, let brightness = value(HMCharacteristicTypeBrightness) as? Int, brightness < 100 {
                text = String(localized: "On · \(brightness)%")
            } else {
                text = on ? String(localized: "On") : String(localized: "Off")
            }
            symbol = on ? "lightbulb.fill" : "lightbulb"
        case .outlet:
            let on = (value(HMCharacteristicTypePowerState) as? Bool) ?? false
            text = on ? String(localized: "On") : String(localized: "Off")
            symbol = on ? "powerplug.fill" : "powerplug"
        case .switch:
            let on = (value(HMCharacteristicTypePowerState) as? Bool) ?? false
            text = on ? String(localized: "On") : String(localized: "Off")
            symbol = on ? "lightswitch.on" : "lightswitch.off"
        }
        if !accessory.isReachable {
            text = String(localized: "No response")
            alert = false
        }
        return HomeStatusItem(id: accessory.lookoutKey(in: home), name: accessory.name, room: room, home: home.name,
                              kind: kind, symbolName: symbol, stateText: text, isAlert: alert,
                              isReachable: accessory.isReachable, celsius: celsius)
    }
}
