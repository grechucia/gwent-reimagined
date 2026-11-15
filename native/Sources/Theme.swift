// Named colors of the game's visual style.

/// Colour palette shared by every screen.
enum Theme {
    /// Warm orange-gold used for glows and hover highlights.
    static let glow = RGBA(r: 1, g: 0.75, b: 0.3, a: 1)
    /// Bright gold for focus frames and selection.
    static let highlightGold = RGBA(r: 1, g: 0.85, b: 0.4, a: 1)
    /// Pale gold for numbers and light accents.
    static let paleGold = RGBA(r: 1, g: 0.9, b: 0.65, a: 1)
    /// Very light warm white.
    static let cream = RGBA(r: 1, g: 0.95, b: 0.85, a: 1)
    /// Gold used for titles and important labels.
    static let textGold = RGBA(r: 0.96, g: 0.85, b: 0.56, a: 1)
    /// Saturated amber for icons and strong accents.
    static let amber = RGBA(r: 0.93, g: 0.72, b: 0.2, a: 1)
    /// Dark bronze for secondary frames.
    static let bronze = RGBA(r: 0.79, g: 0.59, b: 0.18, a: 1)
    /// Warm off-white for body text on dark panels.
    static let parchmentText = RGBA(r: 0.92, g: 0.87, b: 0.76, a: 1)
    /// Light parchment background of large cards.
    static let parchment = RGBA(r: 0.95, g: 0.91, b: 0.82, a: 1)
    /// Darker parchment for gradients.
    static let parchmentShade = RGBA(r: 0.84, g: 0.77, b: 0.63, a: 1)
    /// Dark brown text on parchment.
    static let ink = RGBA(r: 0.22, g: 0.15, b: 0.06, a: 1)
    /// Near-black brown used for panels and overlays.
    static let panelDark = RGBA(r: 0.06, g: 0.05, b: 0.03, a: 1)
    /// Mid brown for wooden details and dividers.
    static let woodBrown = RGBA(r: 0.55, g: 0.4, b: 0.12, a: 1)
    /// Light blue for links.
    static let linkBlue = RGBA(r: 0.55, g: 0.78, b: 1, a: 1)
    /// Icy blue for frost effects.
    static let frostBlue = RGBA(r: 0.8, g: 0.92, b: 1, a: 1)
    /// Green for boosted values.
    static let positive = RGBA(r: 0.5, g: 0.9, b: 0.5, a: 1)
    /// Red for weakened values.
    static let negative = RGBA(r: 1, g: 0.55, b: 0.45, a: 1)
    /// Orange-red for burn effects.
    static let fire = RGBA(r: 1, g: 0.45, b: 0.1, a: 1)
}
