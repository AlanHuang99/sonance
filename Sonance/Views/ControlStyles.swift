import SwiftUI

/// Shared sizing for tappable icon controls. SwiftUI's default borderless icon button renders a
/// ~13 pt glyph with a hit area barely larger than the glyph, which reads as cramped and is
/// fiddly to click. These metrics give comfortable, consistent targets across transport bars,
/// toolbars, and rows.
enum ControlMetrics {
    /// Standard icon-button hit target (shuffle, repeat, favourite, skip…).
    static let iconHitTarget: CGFloat = 34
    /// Standard icon glyph point size.
    static let iconGlyph: CGFloat = 17
    /// Primary transport control (play / pause in the mini-player).
    static let primaryHitTarget: CGFloat = 42
    static let primaryGlyph: CGFloat = 25
}

/// Borderless icon button with a generous, consistent hit area and a subtle hover/press
/// highlight, so small glyph controls are easy to see and easy to click. The glyph size is set
/// here, so call sites should not also apply a `.font` to the icon (set `.foregroundStyle` for
/// active-state tints as usual).
struct IconControlButtonStyle: ButtonStyle {
    var hitTarget: CGFloat = ControlMetrics.iconHitTarget
    var glyph: CGFloat = ControlMetrics.iconGlyph
    var weight: Font.Weight = .medium

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, hitTarget: hitTarget, glyph: glyph, weight: weight)
    }

    struct Content: View {
        let configuration: ButtonStyle.Configuration
        let hitTarget: CGFloat
        let glyph: CGFloat
        let weight: Font.Weight
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.system(size: glyph, weight: weight))
                .frame(width: hitTarget, height: hitTarget)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : (isHovering ? 0.09 : 0)))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(configuration.isPressed ? 0.9 : 1)
                .onHover { isHovering = isEnabled && $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
        }
    }
}

extension ButtonStyle where Self == IconControlButtonStyle {
    /// Standard icon control (34 pt target, 17 pt glyph).
    static var iconControl: IconControlButtonStyle { .init() }

    static func iconControl(hitTarget: CGFloat = ControlMetrics.iconHitTarget,
                            glyph: CGFloat = ControlMetrics.iconGlyph,
                            weight: Font.Weight = .medium) -> IconControlButtonStyle {
        .init(hitTarget: hitTarget, glyph: glyph, weight: weight)
    }

    /// Larger primary transport control (play / pause).
    static var primaryIconControl: IconControlButtonStyle {
        .init(hitTarget: ControlMetrics.primaryHitTarget, glyph: ControlMetrics.primaryGlyph, weight: .semibold)
    }
}
