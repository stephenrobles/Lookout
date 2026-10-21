import PhotosUI
import SwiftUI

/// Pick a photo or a built-in gradient, then dim and blur it until text on
/// the board reads well.
struct WallpaperView: View {
    @Bindable var config: BoardConfig
    @State private var pickerItem: PhotosPickerItem?
    @State private var isImporting = false
    @State private var importError: String?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        List {
            Section {
                BoardPreview(config: config)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Photo") {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    HStack {
                        Label(config.wallpaperImageData == nil ? "Choose photo" : "Change photo",
                              systemImage: "photo.on.rectangle")
                        Spacer()
                        if isImporting { ProgressView() }
                    }
                }
                if config.wallpaperImageData != nil {
                    Toggle("Use photo", isOn: Binding(
                        get: { config.wallpaperUsesPhoto },
                        set: { config.wallpaperUsesPhoto = $0; config.touch() }
                    ))
                    Button("Remove photo", role: .destructive) {
                        config.wallpaperImageData = nil
                        config.wallpaperUsesPhoto = false
                        config.touch()
                    }
                }
                if let importError {
                    Text(importError)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section("Gradient") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(WallpaperPreset.allCases) { preset in
                        Button {
                            config.wallpaperPreset = preset
                            config.wallpaperUsesPhoto = false
                        } label: {
                            VStack(spacing: 6) {
                                LinearGradient(colors: preset.stops.map { Color(hex: $0) },
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                                    .aspectRatio(16 / 9, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(isSelected(preset) ? Color.accentColor : .clear, lineWidth: 3)
                                    }
                                Text(preset.title)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Legibility") {
                VStack(alignment: .leading) {
                    LabeledContent("Dim", value: "\(Int(config.wallpaperDim * 100))%")
                    Slider(value: Binding(
                        get: { config.wallpaperDim },
                        set: { config.wallpaperDim = $0 }
                    ), in: 0...0.8, step: 0.05) { _ in config.touch() }
                }
                VStack(alignment: .leading) {
                    LabeledContent("Blur", value: config.wallpaperBlur == 0 ? "Off" : "\(Int(config.wallpaperBlur))")
                    Slider(value: Binding(
                        get: { config.wallpaperBlur },
                        set: { config.wallpaperBlur = $0 }
                    ), in: 0...40, step: 2) { _ in config.touch() }
                }
            }
        }
        .navigationTitle("Wallpaper")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            importPhoto(item)
        }
    }

    private func isSelected(_ preset: WallpaperPreset) -> Bool {
        !config.wallpaperUsesPhoto && config.wallpaperPreset == preset
    }

    private func importPhoto(_ item: PhotosPickerItem) {
        isImporting = true
        importError = nil
        Task {
            defer { isImporting = false; pickerItem = nil }
            do {
                guard let raw = try await item.loadTransferable(type: Data.self) else {
                    importError = "That photo could not be read."
                    return
                }
                let prepared = await Task.detached(priority: .userInitiated) {
                    WallpaperImporter.prepare(raw)
                }.value
                guard let prepared else {
                    importError = "That photo could not be converted."
                    return
                }
                config.wallpaperImageData = prepared
                config.wallpaperUsesPhoto = true
                config.touch()
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

/// A rough stand-in for the TV layout so dim and blur can be judged on the phone.
private struct BoardPreview: View {
    let config: BoardConfig

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 1920
            ZStack {
                WallpaperThumbnail(config: config)
                    .blur(radius: config.wallpaperBlur * unit * 2)
                    .clipped()
                HStack(spacing: 28 * unit) {
                    VStack(alignment: .leading, spacing: 20 * unit) {
                        Text("13:35")
                            .font(.system(size: 170 * unit, weight: .bold, design: .rounded))
                        Text("Wednesday, October 21")
                            .font(.system(size: 40 * unit, weight: .medium))
                        card(unit).frame(maxHeight: .infinity)
                    }
                    .frame(width: 560 * unit)
                    card(unit)
                    VStack(spacing: 24 * unit) {
                        card(unit)
                        card(unit)
                    }
                    .frame(width: 480 * unit)
                }
                .padding(.horizontal, 90 * unit)
                .padding(.vertical, 60 * unit)
                .foregroundStyle(.white)
            }
        }
    }

    private func card(_ unit: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 28 * unit)
            .fill(.white.opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: 28 * unit).strokeBorder(.white.opacity(0.1), lineWidth: 1))
    }
}
