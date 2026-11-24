import Foundation
import Security

/// What this device remembers about the names it has published under. All of
/// it stays on the device; nothing here is synced.
///
/// Two places, because they outlive different things:
/// - the keychain keeps its items when the app is deleted and never leaves
///   the device, so a name found there was this very device before a
///   reinstall;
/// - UserDefaults is erased with the app but travels in a backup or a
///   transfer, so a name found only there was the device this one was set up
///   from.
nonisolated enum PublisherMemory {
    /// A takeover this install made, kept to explain it on the status card.
    struct Takeover: Codable, Equatable, Sendable {
        var from: String
        var kind: PublisherSuccession.Predecessor
        var date: Date
    }

    private static let identityKey = "publisherIdentity"
    private static let identitySinceKey = "publisherIdentitySince"
    private static let publishedKey = "publisherPublishedAs"
    private static let tookOverKey = "publisherTookOverFrom"
    private static let takeoverKey = "publisherLastTakeover"
    /// Enough for many reinstalls; older names can no longer own the board.
    private static let maxRemembered = 12

    private static var defaults: UserDefaults { .standard }

    /// When this install first ran under `identity`. A different name from
    /// last time (a new install has none) starts the clock now.
    static func since(_ identity: String, now: Date = .now) -> Date {
        if defaults.string(forKey: identityKey) == identity,
           let since = defaults.object(forKey: identitySinceKey) as? Date {
            return since
        }
        defaults.set(identity, forKey: identityKey)
        defaults.set(now, forKey: identitySinceKey)
        return now
    }

    /// Names this very device has published under, across reinstalls.
    static var publishedHere: Set<String> { Set(keychainNames()) }

    /// Names the app's data has published under, across backups.
    static var publishedBefore: Set<String> { Set(defaults.stringArray(forKey: publishedKey) ?? []) }

    static var tookOverFrom: Set<String> { Set(defaults.stringArray(forKey: tookOverKey) ?? []) }

    static var lastTakeover: Takeover? {
        guard let data = defaults.data(forKey: takeoverKey) else { return nil }
        return try? JSONDecoder().decode(Takeover.self, from: data)
    }

    /// Call after each publish. Writes only when the name is new.
    static func rememberPublished(as identity: String) {
        var before = defaults.stringArray(forKey: publishedKey) ?? []
        if !before.contains(identity) {
            before.append(identity)
            defaults.set(Array(before.suffix(maxRemembered)), forKey: publishedKey)
        }
        var here = keychainNames()
        if !here.contains(identity) {
            here.append(identity)
            setKeychainNames(Array(here.suffix(maxRemembered)))
        }
    }

    @discardableResult
    static func rememberTakeover(from owner: String, _ kind: PublisherSuccession.Predecessor,
                                 at date: Date = .now) -> Takeover {
        var took = defaults.stringArray(forKey: tookOverKey) ?? []
        if !took.contains(owner) {
            took.append(owner)
            defaults.set(Array(took.suffix(maxRemembered)), forKey: tookOverKey)
        }
        let takeover = Takeover(from: owner, kind: kind, date: date)
        if let data = try? JSONEncoder().encode(takeover) {
            defaults.set(data, forKey: takeoverKey)
        }
        return takeover
    }

    // MARK: Keychain

    private static var keychainItem: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "fm.beard.Lookout.publisher",
         kSecAttrAccount as String: "names"]
    }

    private static func keychainNames() -> [String] {
        var query = keychainItem
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private static func setKeychainNames(_ names: [String]) {
        guard let data = try? JSONEncoder().encode(names) else { return }
        let update = [kSecValueData as String: data]
        if SecItemUpdate(keychainItem as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var item = keychainItem
            item[kSecValueData as String] = data
            // Readable during a background refresh, and never copied to
            // another device or to iCloud Keychain.
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
