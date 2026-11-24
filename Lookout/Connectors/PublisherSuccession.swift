import Foundation

/// Whose turn it is to publish. Only one iPhone or iPad publishes
/// automatically, the one named in `BoardConfig.publishedFromDevice`, and the
/// others leave it alone until it has been silent for `ownerTimeout`.
///
/// A device's own name carries a tail of its vendor identifier, which changes
/// when Lookout is deleted and installed again and when its data moves to a
/// new phone. The record then names a publisher that no longer exists, and
/// without help this device would wait out the timeout for its old self.
/// So it takes over at once, but only from a name it can show was its own:
/// one it remembers publishing under (`PublisherMemory`). Nothing here is
/// guessed from the name alone, since a second iPhone on the account looks
/// exactly like a reinstalled one from the synced record.
nonisolated enum PublisherSuccession {
    /// How this device knows the recorded publisher was its earlier self.
    enum Predecessor: String, Codable, Sendable {
        /// Remembered in this device's keychain, which outlives the app:
        /// Lookout was deleted and installed again here.
        case reinstalled
        /// Remembered only in the app's own data, which arrived with a
        /// backup or a transfer: this device was set up from that one.
        case replaced
    }

    enum Turn: Equatable, Sendable {
        /// This device's turn: the board is its own, free, or just claimed.
        case publish
        /// The publisher is this device's earlier self. Publish in its place.
        case takeOver(from: String, Predecessor)
        /// Another device publishes. Skip.
        case leave(to: String)
    }

    struct Facts: Sendable {
        /// `BoardConfig.publishedFromDevice`.
        var owner: String
        /// `BoardConfig.lastPublishedAt`, stamped by the owner's clock.
        var ownerLastPublished: Date?
        var now: Date
        /// The user changed something here or tapped Publish now.
        var claim: Bool
        /// What this device signs with now: its name plus the tail.
        var identity: String
        /// The bare device name, "iPhone" or "iPad".
        var deviceName: String
        /// When this install first ran under `identity`.
        var identitySince: Date
        /// Names this very device has published under (keychain).
        var publishedHere: Set<String>
        /// Names the app's data has published under (carried by backups).
        var publishedBefore: Set<String>
        /// Names this install has already taken over from, once each.
        var tookOverFrom: Set<String>
    }

    /// If the publishing device has been silent this long, any device may
    /// take over, so a phone that was reset or retired cannot freeze the board.
    static let ownerTimeout: TimeInterval = 36 * 60 * 60

    static func turn(_ facts: Facts) -> Turn {
        let owner = facts.owner
        // A bare "iPhone" or "iPad" owner comes from a build before 1.3 and
        // is treated as free.
        if facts.claim || owner.isEmpty || owner == facts.identity || owner == facts.deviceName {
            return .publish
        }
        guard let last = facts.ownerLastPublished,
              facts.now.timeIntervalSince(last) < ownerTimeout else {
            return .publish
        }

        let predecessor: Predecessor? =
            facts.publishedHere.contains(owner) ? .reinstalled
            : facts.publishedBefore.contains(owner) ? .replaced
            : nil
        // Three more conditions keep two devices that are both in use from
        // ever trading the board back and forth:
        // - the same kind of device, so an iPad set up from an iPhone's
        //   backup does not take the iPhone's place;
        // - the owner has not published since this identity appeared. An
        //   earlier self stops before its successor starts; one that has
        //   published since is still running somewhere. Its clock running
        //   ahead only makes this stricter;
        // - once per name, so if that device does claim the board back, by
        //   a change made on it, it keeps it.
        if let predecessor,
           owner.hasPrefix(facts.deviceName + " "),
           last <= min(facts.identitySince, facts.now),
           !facts.tookOverFrom.contains(owner) {
            return .takeOver(from: owner, predecessor)
        }
        return .leave(to: owner)
    }
}
