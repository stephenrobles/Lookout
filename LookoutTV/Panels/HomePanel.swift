import SwiftUI

/// Locks, doors, garage, sensors and temperatures as a grid of chips.
struct HomePanel: View {
    let items: [HomeStatusItem]
    let isReady: Bool
    let isDenied: Bool
    let settings: TVSettings

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        BoardCard(title: "Home", symbolName: "house.fill") {
            if isDenied {
                message("HomeKit access is off for Lookout. Allow it in Settings › Apps › Lookout.")
            } else if !isReady {
                message("Connecting to your home…")
            } else if items.isEmpty {
                message("No locks, doors or sensors in this home.")
            } else {
                Color.clear.overlay(alignment: .topLeading) {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(items) { item in
                            chip(item)
                        }
                    }
                }
                .clipped()
                .bottomFade()
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(BoardTheme.row)
            .foregroundStyle(.secondary)
    }

    private func chip(_ item: HomeStatusItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbolName)
                .font(.system(size: 26, weight: .semibold))
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(BoardTheme.chipTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(stateText(item))
                    .font(BoardTheme.chipState)
                    .lineLimit(1)
                    .opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .foregroundStyle(item.isAlert ? .black : (item.isReachable ? .primary : .secondary))
        .background(
            item.isAlert ? AnyShapeStyle(BoardTheme.alert) : AnyShapeStyle(.white.opacity(0.08)),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func stateText(_ item: HomeStatusItem) -> String {
        if let celsius = item.celsius, item.isReachable {
            return settings.temperatureText(celsius: celsius)
        }
        return item.stateText
    }
}
