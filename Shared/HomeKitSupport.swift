import Foundation
#if canImport(HomeKit)
import HomeKit
#endif

/// What a HomeKit accessory contributes to the Home panel. Shared so the
/// iPhone picker and the TV board agree on which accessories count.
nonisolated enum HomeAccessoryKind: String, Sendable, CaseIterable {
    case lock, garageDoor, door, window, contactSensor, motionSensor, temperature, doorbell, light, outlet, `switch`

    var title: String {
        switch self {
        case .lock: String(localized: "Lock")
        case .garageDoor: String(localized: "Garage door")
        case .door: String(localized: "Door")
        case .window: String(localized: "Window")
        case .contactSensor: String(localized: "Contact sensor")
        case .motionSensor: String(localized: "Motion sensor")
        case .temperature: String(localized: "Temperature")
        case .doorbell: String(localized: "Doorbell")
        case .light: String(localized: "Light")
        case .outlet: String(localized: "Smart plug")
        case .switch: String(localized: "Switch")
        }
    }

    var symbolName: String {
        switch self {
        case .lock: "lock"
        case .garageDoor: "door.garage.closed"
        case .door: "door.left.hand.closed"
        case .window: "window.vertical.closed"
        case .contactSensor: "sensor"
        case .motionSensor: "figure.walk.motion"
        case .temperature: "thermometer.medium"
        case .doorbell: "bell"
        case .light: "lightbulb"
        case .outlet: "powerplug"
        case .switch: "lightswitch.off"
        }
    }
}

#if canImport(HomeKit)
extension HomeAccessoryKind {
    /// Maps a HomeKit service type to the kind the board can display.
    nonisolated static func kind(forServiceType type: String) -> HomeAccessoryKind? {
        switch type {
        case HMServiceTypeLockMechanism: .lock
        case HMServiceTypeGarageDoorOpener: .garageDoor
        case HMServiceTypeDoor: .door
        case HMServiceTypeWindow: .window
        case HMServiceTypeContactSensor: .contactSensor
        case HMServiceTypeMotionSensor: .motionSensor
        case HMServiceTypeTemperatureSensor, HMServiceTypeThermostat: .temperature
        case HMServiceTypeDoorbell: .doorbell
        case HMServiceTypeLightbulb: .light
        case HMServiceTypeOutlet: .outlet
        case HMServiceTypeSwitch: .switch
        default: nil
        }
    }
}

extension HMAccessory {
    /// The first service on this accessory the board knows how to show.
    var lookoutStatusService: (HMService, HomeAccessoryKind)? {
        for service in services {
            if let kind = HomeAccessoryKind.kind(forServiceType: service.serviceType) {
                return (service, kind)
            }
        }
        return nil
    }

    var lookoutIsCamera: Bool {
        !(cameraProfiles ?? []).isEmpty
    }

    /// The key the iPhone stores for a chosen accessory and the TV matches
    /// against. HomeKit's `uniqueIdentifier` is scoped to one device, so the
    /// same accessory has different UUIDs on the phone and the Apple TV; home
    /// and accessory names are the same everywhere.
    func lookoutKey(in home: HMHome) -> String {
        Self.lookoutKey(home: home.name, accessory: name)
    }

    nonisolated static func lookoutKey(home: String, accessory: String) -> String {
        // Selections are stored comma-separated, so keep commas out of the key.
        [home, accessory]
            .map { $0.replacingOccurrences(of: ",", with: "%2C") }
            .joined(separator: "|")
    }
}
#endif
