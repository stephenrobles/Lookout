import SwiftUI

/// Current conditions, the next six hours and the next five days.
struct WeatherPanel: View {
    let weather: WeatherModel
    let settings: TVSettings
    let openSettings: () -> Void

    var body: some View {
        BoardCard(title: settings.hasLocation ? settings.locationName : "Weather", symbolName: "location.fill") {
            if !settings.hasLocation {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose a location to show the weather here.")
                        .font(BoardTheme.row)
                        .foregroundStyle(.secondary)
                    Button("Set location", action: openSettings)
                }
            } else if let snapshot = weather.snapshot {
                current(snapshot)
                Divider().overlay(.white.opacity(0.12))
                hourly(snapshot)
                Divider().overlay(.white.opacity(0.12))
                daily(snapshot)
                attribution
            } else if let error = weather.errorText {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Weather unavailable")
                        .font(BoardTheme.row)
                    Text(error)
                        .font(BoardTheme.rowSecondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            } else {
                HStack(spacing: 14) {
                    ProgressView()
                    Text("Loading…")
                        .font(BoardTheme.row)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func current(_ snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 20) {
                Text(settings.temperatureText(celsius: snapshot.celsius))
                    .font(BoardTheme.bigNumber)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: snapshot.symbolName)
                            .symbolRenderingMode(.multicolor)
                        Text(snapshot.conditionText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .font(BoardTheme.rowStrong)
                    detail("Feels \(settings.temperatureText(celsius: snapshot.feelsLikeCelsius))")
                    detail("Humidity \(Int((snapshot.humidity * 100).rounded()))%")
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 18) {
                Label("\(snapshot.windDirection) \(settings.speedText(metersPerSecond: snapshot.windMetersPerSecond))",
                      systemImage: "wind")
                if let sunrise = snapshot.sunrise {
                    Label(settings.timeText(sunrise), systemImage: "sunrise.fill")
                }
                if let sunset = snapshot.sunset {
                    Label(settings.timeText(sunset), systemImage: "sunset.fill")
                }
                Spacer(minLength: 0)
            }
            .font(BoardTheme.rowSecondary)
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.multicolor)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(BoardTheme.rowSecondary)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func hourly(_ snapshot: WeatherSnapshot) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(snapshot.hourly.enumerated()), id: \.element.id) { index, hour in
                VStack(spacing: 6) {
                    BoardLabel(text: index == 0 ? "Now" : settings.hourText(hour.date))
                    Image(systemName: hour.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 28))
                        .frame(height: 32)
                    Text(settings.temperatureText(celsius: hour.celsius))
                        .font(BoardTheme.rowStrong)
                        .monospacedDigit()
                    if snapshot.hourly.contains(where: { $0.precipitationChance >= 0.2 }) {
                        Text(hour.precipitationChance >= 0.2 ? "\(Int((hour.precipitationChance * 100).rounded()))%" : " ")
                            .font(BoardTheme.rowSecondary)
                            .foregroundStyle(.cyan)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func daily(_ snapshot: WeatherSnapshot) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(snapshot.daily.enumerated()), id: \.element.id) { index, day in
                VStack(spacing: 6) {
                    BoardLabel(text: index == 0 ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)))
                    Image(systemName: day.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 28))
                        .frame(height: 32)
                    Text(settings.temperatureText(celsius: day.highCelsius))
                        .font(BoardTheme.rowStrong)
                        .monospacedDigit()
                    Text(settings.temperatureText(celsius: day.lowCelsius))
                        .font(BoardTheme.rowSecondary)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var attribution: some View {
        HStack(spacing: 6) {
            Spacer()
            if let url = weather.attributionMarkURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(" Weather")
                }
                .frame(height: 18)
            } else {
                Text(" Weather")
            }
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(.secondary)
        .opacity(0.8)
    }
}
