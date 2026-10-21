import Foundation
import Observation

/// Settings that live on the Apple TV itself: weather location, units, clock
/// style and a wallpaper override. Everything about *content* comes from the
/// iPhone through `BoardConfig`.
@Observable
final class TVSettings {
    static let shared = TVSettings()

    enum TemperatureChoice: String, CaseIterable, Identifiable {
        case automatic, fahrenheit, celsius
        var id: String { rawValue }
        var title: String {
            switch self {
            case .automatic: "Automatic"
            case .fahrenheit: "Fahrenheit"
            case .celsius: "Celsius"
            }
        }
    }

    enum ClockChoice: String, CaseIterable, Identifiable {
        case automatic, twelveHour, twentyFourHour
        var id: String { rawValue }
        var title: String {
            switch self {
            case .automatic: "Automatic"
            case .twelveHour: "12-hour"
            case .twentyFourHour: "24-hour"
            }
        }
    }

    /// "iphone" follows whatever the phone chose; otherwise a preset raw value.
    static let followPhoneWallpaper = "iphone"

    private let defaults = UserDefaults.standard

    var locationName: String { didSet { defaults.set(locationName, forKey: "locationName") } }
    var latitude: Double? { didSet { defaults.set(latitude, forKey: "latitude") } }
    var longitude: Double? { didSet { defaults.set(longitude, forKey: "longitude") } }
    var temperature: TemperatureChoice { didSet { defaults.set(temperature.rawValue, forKey: "temperature") } }
    var clock: ClockChoice { didSet { defaults.set(clock.rawValue, forKey: "clock") } }
    var wallpaperChoice: String { didSet { defaults.set(wallpaperChoice, forKey: "wallpaperChoice") } }

    private init() {
        locationName = defaults.string(forKey: "locationName") ?? ""
        latitude = defaults.object(forKey: "latitude") as? Double
        longitude = defaults.object(forKey: "longitude") as? Double
        temperature = TemperatureChoice(rawValue: defaults.string(forKey: "temperature") ?? "") ?? .automatic
        clock = ClockChoice(rawValue: defaults.string(forKey: "clock") ?? "") ?? .automatic
        wallpaperChoice = defaults.string(forKey: "wallpaperChoice") ?? Self.followPhoneWallpaper
        if LookoutStore.isDemo, latitude == nil {
            locationName = "Foothill Ranch"
            latitude = 33.6866
            longitude = -117.6626
        }
    }

    var hasLocation: Bool { latitude != nil && longitude != nil }

    /// Changes whenever the weather location changes; drives the refresh task.
    var locationKey: String { "\(latitude ?? 0),\(longitude ?? 0)" }

    func setLocation(name: String, latitude: Double, longitude: Double) {
        locationName = name
        self.latitude = latitude
        self.longitude = longitude
    }

    var usesFahrenheit: Bool {
        switch temperature {
        case .fahrenheit: true
        case .celsius: false
        case .automatic: Locale.current.measurementSystem == .us
        }
    }

    var uses24Hour: Bool {
        switch clock {
        case .twentyFourHour:
            return true
        case .twelveHour:
            return false
        case .automatic:
            let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
            return !format.contains("a")
        }
    }

    var wallpaperOverride: WallpaperPreset? {
        wallpaperChoice == Self.followPhoneWallpaper ? nil : WallpaperPreset(rawValue: wallpaperChoice)
    }

    // MARK: Formatting

    func temperatureText(celsius: Double) -> String {
        let value = usesFahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }

    func speedText(metersPerSecond: Double) -> String {
        if usesFahrenheit {
            return "\(Int((metersPerSecond * 2.23694).rounded())) mph"
        }
        return "\(Int((metersPerSecond * 3.6).rounded())) km/h"
    }

    private let twelveHour: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "h:mm"; return f
    }()
    private let twelveHourShort: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "h a"; return f
    }()
    private let twentyFourHour: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"; return f
    }()
    private let amPM: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "a"; return f
    }()

    /// "13:35" or "1:35" (the period comes from `periodText`).
    func clockText(_ date: Date) -> String {
        uses24Hour ? twentyFourHour.string(from: date) : twelveHour.string(from: date)
    }

    func periodText(_ date: Date) -> String? {
        uses24Hour ? nil : amPM.string(from: date)
    }

    /// Compact time for rows: "16:00" or "4:00 PM".
    func timeText(_ date: Date) -> String {
        uses24Hour ? twentyFourHour.string(from: date) : "\(twelveHour.string(from: date)) \(amPM.string(from: date))"
    }

    /// Hour-only labels for the hourly forecast: "14:00" or "2 PM".
    func hourText(_ date: Date) -> String {
        uses24Hour ? twentyFourHour.string(from: date) : twelveHourShort.string(from: date)
    }
}
