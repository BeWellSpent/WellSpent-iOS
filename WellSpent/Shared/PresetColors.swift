/// Shared hex color palette offered wherever the app lets a user pick an
/// optional display color (people, categories, payment methods) — a fixed
/// preset list rather than a full color picker, matching the "no
/// `Color(hex:)` parser needed" simplification used throughout.
nonisolated enum PresetColors {
    static let all = [
        "#EF5350", "#AB47BC", "#5C6BC0", "#29B6F6",
        "#26A69A", "#9CCC65", "#FFCA28", "#8D6E63",
    ]
}
