import CoreLocation
import Foundation
import Observation
import WeatherKit

/// A plain copy of what the weather panel shows, so demo mode and WeatherKit
/// feed the same view.
nonisolated struct WeatherSnapshot: Sendable {
    struct Hour: Sendable, Identifiable {
        var id: Date { date }
        var date: Date
        var symbolName: String
        var celsius: Double
        var precipitationChance: Double
    }

    struct Day: Sendable, Identifiable {
        var id: Date { date }
        var date: Date
        var symbolName: String
        var highCelsius: Double
        var lowCelsius: Double
        var precipitationChance: Double
    }

    var celsius: Double
    var feelsLikeCelsius: Double
    var humidity: Double
    var windMetersPerSecond: Double
    var windDirection: String
    var symbolName: String
    var conditionText: String
    var sunrise: Date?
    var sunset: Date?
    var uvIndex: Int
    var hourly: [Hour]
    var daily: [Day]
    var fetchedAt: Date
}

/// Fetches WeatherKit for the TV's configured location and refreshes every
/// 20 minutes while the board is on screen.
@Observable
final class WeatherModel {
    private(set) var snapshot: WeatherSnapshot?
    private(set) var errorText: String?
    private(set) var attributionMarkURL: URL?
    private(set) var isLoading = false

    /// Runs until cancelled; call from `.task(id:)` keyed on the location.
    func run(latitude: Double?, longitude: Double?) async {
        guard let latitude, let longitude else {
            snapshot = nil
            return
        }
        if LookoutStore.isDemo {
            snapshot = Self.demoSnapshot()
            return
        }
        if attributionMarkURL == nil {
            attributionMarkURL = try? await WeatherService.shared.attribution.combinedMarkDarkURL
        }
        while !Task.isCancelled {
            await refresh(latitude: latitude, longitude: longitude)
            try? await Task.sleep(for: .seconds(20 * 60))
        }
    }

    private func refresh(latitude: Double, longitude: Double) async {
        isLoading = true
        defer { isLoading = false }
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let (current, hourly, daily) = try await WeatherService.shared.weather(
                for: location, including: .current, .hourly, .daily)
            let now = Date.now
            let hours = hourly.forecast
                .filter { $0.date >= now.addingTimeInterval(-30 * 60) }
                .prefix(6)
                .map { hour in
                    WeatherSnapshot.Hour(date: hour.date, symbolName: hour.symbolName,
                                         celsius: hour.temperature.converted(to: .celsius).value,
                                         precipitationChance: hour.precipitationChance)
                }
            let today = Calendar.current.startOfDay(for: now)
            let days = daily.forecast
                .filter { $0.date >= today }
                .prefix(5)
                .map { day in
                    WeatherSnapshot.Day(date: day.date, symbolName: day.symbolName,
                                        highCelsius: day.highTemperature.converted(to: .celsius).value,
                                        lowCelsius: day.lowTemperature.converted(to: .celsius).value,
                                        precipitationChance: day.precipitationChance)
                }
            let todayForecast = daily.forecast.first { Calendar.current.isDate($0.date, inSameDayAs: now) }
            snapshot = WeatherSnapshot(
                celsius: current.temperature.converted(to: .celsius).value,
                feelsLikeCelsius: current.apparentTemperature.converted(to: .celsius).value,
                humidity: current.humidity,
                windMetersPerSecond: current.wind.speed.converted(to: .metersPerSecond).value,
                windDirection: current.wind.compassDirection.abbreviation,
                symbolName: current.symbolName,
                conditionText: current.condition.description,
                sunrise: todayForecast?.sun.sunrise,
                sunset: todayForecast?.sun.sunset,
                uvIndex: current.uvIndex.value,
                hourly: Array(hours),
                daily: Array(days),
                fetchedAt: now
            )
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    nonisolated static func demoSnapshot() -> WeatherSnapshot {
        let calendar = Calendar.current
        let now = Date.now
        let hourStart = calendar.date(bySetting: .minute, value: 0, of: now) ?? now
        let symbols = ["cloud.fill", "sun.max.fill", "sun.max.fill", "sun.max.fill", "cloud.fill", "cloud.moon.fill"]
        let temps: [Double] = [24.4, 25.6, 23.9, 22.8, 21.1, 19.4]
        let hourly = (0..<6).map { i in
            WeatherSnapshot.Hour(date: calendar.date(byAdding: .hour, value: i, to: hourStart)!,
                                 symbolName: symbols[i], celsius: temps[i], precipitationChance: 0)
        }
        let daySymbols = ["cloud.rain.fill", "cloud.heavyrain.fill", "cloud.rain.fill", "sun.max.fill", "sun.max.fill"]
        let highs: [Double] = [25.6, 17.8, 19.4, 24.4, 26.7]
        let lows: [Double] = [16.1, 12.2, 12.8, 14.4, 16.7]
        let today = calendar.startOfDay(for: now)
        let daily = (0..<5).map { i in
            WeatherSnapshot.Day(date: calendar.date(byAdding: .day, value: i, to: today)!,
                                symbolName: daySymbols[i], highCelsius: highs[i], lowCelsius: lows[i],
                                precipitationChance: i < 3 ? 0.6 : 0.05)
        }
        return WeatherSnapshot(
            celsius: 24.4, feelsLikeCelsius: 23.9, humidity: 0.52, windMetersPerSecond: 5.4,
            windDirection: "SSE", symbolName: "cloud.fill", conditionText: "Overcast",
            sunrise: calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now),
            sunset: calendar.date(bySettingHour: 18, minute: 9, second: 0, of: now),
            uvIndex: 4, hourly: hourly, daily: daily, fetchedAt: now)
    }
}
