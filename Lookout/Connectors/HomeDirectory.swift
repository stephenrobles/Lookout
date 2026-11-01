import Foundation
import HomeKit
import Observation

/// A HomeKit accessory as the picker lists it. Identifiers are home-and-name
/// keys (see `HMAccessory.lookoutKey`), because HomeKit's UUIDs differ from
/// one device to the next and the TV has to find the same accessory.
struct HomeAccessoryEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let room: String
    let home: String
    let kind: HomeAccessoryKind?
    let isCamera: Bool
}

/// Lists the homes this iPhone can see so the user can choose what the board
/// shows. Created lazily: constructing `HMHomeManager` triggers the HomeKit
/// permission prompt.
@Observable
final class HomeDirectory: NSObject, HMHomeManagerDelegate {
    private var manager: HMHomeManager?
    private(set) var isLoading = true
    private(set) var isDenied = false
    private(set) var cameras: [HomeAccessoryEntry] = []
    private(set) var accessories: [HomeAccessoryEntry] = []
    /// True when the account has more than one home, so rows can say which.
    private(set) var hasMultipleHomes = false

    func start() {
        guard manager == nil else { return }
        if LookoutStore.isDemo {
            cameras = [
                HomeAccessoryEntry(id: "demo-cam-1", name: "Front Right Camera", room: "Driveway", home: "Home", kind: nil, isCamera: true),
                HomeAccessoryEntry(id: "demo-cam-2", name: "Porch Camera", room: "Entry", home: "Home", kind: nil, isCamera: true),
                HomeAccessoryEntry(id: "demo-cam-3", name: "Walkway Camera", room: "Side Yard", home: "Home", kind: nil, isCamera: true),
            ]
            accessories = [
                HomeAccessoryEntry(id: "demo-1", name: "Back Door", room: "Kitchen", home: "Home", kind: .lock, isCamera: false),
                HomeAccessoryEntry(id: "demo-2", name: "Front Door", room: "Entry", home: "Home", kind: .lock, isCamera: false),
                HomeAccessoryEntry(id: "demo-3", name: "Laundry Door", room: "Laundry", home: "Home", kind: .lock, isCamera: false),
                HomeAccessoryEntry(id: "demo-4", name: "Garage", room: "Garage", home: "Home", kind: .garageDoor, isCamera: false),
                HomeAccessoryEntry(id: "demo-5", name: "Office", room: "Office", home: "Home", kind: .temperature, isCamera: false),
                HomeAccessoryEntry(id: "demo-6", name: "Living Room Lamp", room: "Living Room", home: "Home", kind: .light, isCamera: false),
                HomeAccessoryEntry(id: "demo-7", name: "Christmas Tree", room: "Living Room", home: "Home", kind: .outlet, isCamera: false),
            ]
            isLoading = false
            return
        }
        let manager = HMHomeManager()
        manager.delegate = self
        self.manager = manager
    }

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        reload(from: manager)
    }

    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        isDenied = status.contains(.determined) && !status.contains(.authorized)
        reload(from: manager)
    }

    private func reload(from manager: HMHomeManager) {
        var cameras: [HomeAccessoryEntry] = []
        var others: [HomeAccessoryEntry] = []
        for home in manager.homes {
            for accessory in home.accessories {
                let room = accessory.room?.name ?? ""
                if accessory.lookoutIsCamera {
                    cameras.append(HomeAccessoryEntry(id: accessory.lookoutKey(in: home),
                                                      name: accessory.name, room: room, home: home.name,
                                                      kind: nil, isCamera: true))
                }
                if let (_, kind) = accessory.lookoutStatusService {
                    others.append(HomeAccessoryEntry(id: accessory.lookoutKey(in: home),
                                                     name: accessory.name, room: room, home: home.name,
                                                     kind: kind, isCamera: false))
                }
            }
        }
        self.cameras = cameras.sorted(by: Self.byHomeThenName)
        self.accessories = others.sorted(by: Self.byHomeThenName)
        hasMultipleHomes = manager.homes.count > 1
        isLoading = false
    }

    private static func byHomeThenName(_ a: HomeAccessoryEntry, _ b: HomeAccessoryEntry) -> Bool {
        let homes = a.home.localizedStandardCompare(b.home)
        if homes != .orderedSame { return homes == .orderedAscending }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}
