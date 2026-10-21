import SwiftUI

/// Spacing, radii and type sizes for the board. Sizes are in tvOS points on a
/// 1920×1080 canvas; the layout is fixed-width by design.
enum BoardTheme {
    static let cardRadius: CGFloat = 28
    static let gutter: CGFloat = 28
    static let cardPadding: CGFloat = 30
    static let leftWidth: CGFloat = 540
    static let rightWidth: CGFloat = 500

    static let clock = Font.system(size: 156, weight: .bold, design: .rounded)
    static let clockPeriod = Font.system(size: 40, weight: .semibold, design: .rounded)
    static let date = Font.system(size: 36, weight: .medium)
    static let subtitle = Font.system(size: 27, weight: .regular)

    static let cardTitle = Font.system(size: 30, weight: .semibold)
    static let row = Font.system(size: 28, weight: .regular)
    static let rowStrong = Font.system(size: 28, weight: .semibold)
    static let rowSecondary = Font.system(size: 23, weight: .regular)
    static let label = Font.system(size: 22, weight: .semibold)
    static let bigNumber = Font.system(size: 100, weight: .bold, design: .rounded)
    static let chipTitle = Font.system(size: 24, weight: .semibold)
    static let chipState = Font.system(size: 22, weight: .regular)

    static let alert = Color(hex: "#FF9F0A")
    static let overdue = Color(hex: "#FF453A")
}

/// A glass card with an optional header row, as every panel uses.
struct BoardCard<Content: View, Trailing: View>: View {
    var title: String?
    var symbolName: String?
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    init(title: String? = nil, symbolName: String? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.symbolName = symbolName
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if title != nil || symbolName != nil {
                HStack(spacing: 12) {
                    if let symbolName {
                        Image(systemName: symbolName)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.tint)
                    }
                    if let title {
                        Text(title)
                            .font(BoardTheme.cardTitle)
                    }
                    Spacer(minLength: 0)
                    trailing()
                }
            }
            content()
        }
        .padding(BoardTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: BoardTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BoardTheme.cardRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

extension BoardCard where Trailing == EmptyView {
    init(title: String? = nil, symbolName: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, symbolName: symbolName, trailing: { EmptyView() }, content: content)
    }
}

/// Small uppercase label used for day headers and forecast columns.
struct BoardLabel: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text.uppercased())
            .font(BoardTheme.label)
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

/// Fades the bottom of overflowing content instead of cutting it off.
struct BottomFade: ViewModifier {
    func body(content: Content) -> some View {
        content
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 70)
                }
            }
    }
}

extension View {
    func bottomFade() -> some View { modifier(BottomFade()) }
}

/// A circular glass button that brightens and grows when focused.
struct GlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassIconButtonLabel(configuration: configuration)
    }
}

private struct GlassIconButtonLabel: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(isFocused ? .black : .white)
            .frame(width: 64, height: 64)
            .background(isFocused ? AnyShapeStyle(.white) : AnyShapeStyle(.regularMaterial), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(isFocused ? 0 : 0.12), lineWidth: 1))
            .scaleEffect(isFocused ? 1.12 : 1)
            .opacity(configuration.isPressed ? 0.7 : (isFocused ? 1 : 0.55))
            .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

/// The wallpaper behind the board: the iPhone photo or a gradient, dimmed
/// and optionally blurred for legibility.
struct BoardWallpaper: View {
    let snapshot: BoardSnapshot
    let override: WallpaperPreset?
    @State private var image: UIImage?

    private var usesPhoto: Bool {
        override == nil && snapshot.wallpaperUsesPhoto && snapshot.wallpaperImageData != nil
    }

    private var preset: WallpaperPreset { override ?? snapshot.wallpaperPreset }

    var body: some View {
        ZStack {
            if usesPhoto, let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: snapshot.wallpaperBlur)
                    .scaleEffect(1 + snapshot.wallpaperBlur / 300)
            } else {
                LinearGradient(colors: preset.stops.map { Color(hex: $0) },
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // A soft highlight so gradients do not read as flat.
                RadialGradient(colors: [.white.opacity(0.10), .clear], center: .topLeading,
                               startRadius: 0, endRadius: 1400)
            }
            Color.black.opacity(usesPhoto ? snapshot.wallpaperDim : min(snapshot.wallpaperDim, 0.2))
        }
        .ignoresSafeArea()
        .task(id: snapshot.wallpaperImageData?.count ?? -1) {
            guard let data = snapshot.wallpaperImageData else { image = nil; return }
            image = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
        }
        .animation(.easeInOut(duration: 0.6), value: usesPhoto)
    }
}
