import Foundation
import HomeKit
import Observation

/// A HomeKit accessory as the picker lists it. Identifiers are HomeKit's own
/// UUIDs, which are the same on every device sharing the home, so the TV can
/// look them up directly.
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

    func start() {
        guard manager == nil else { return }
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
                    cameras.append(HomeAccessoryEntry(id: accessory.uniqueIdentifier.uuidString,
                                                      name: accessory.name, room: room, home: home.name,
                                                      kind: nil, isCamera: true))
                }
                if let (_, kind) = accessory.lookoutStatusService {
                    others.append(HomeAccessoryEntry(id: accessory.uniqueIdentifier.uuidString,
                                                     name: accessory.name, room: room, home: home.name,
                                                     kind: kind, isCamera: false))
                }
            }
        }
        self.cameras = cameras.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.accessories = others.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        isLoading = false
    }
}
