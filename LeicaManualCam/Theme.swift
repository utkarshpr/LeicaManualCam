import SwiftUI

/// Matte-black, soft-shadow "neumorphic" design system with champagne-gold accents.
enum Theme {
    static let champagne = Color(red: 0.93, green: 0.84, blue: 0.67)
    static let champagneLight = Color(red: 0.98, green: 0.94, blue: 0.85)
    static let muted = Color(white: 0.55)

    static let gold = LinearGradient(
        colors: [Color(red: 0.98, green: 0.92, blue: 0.78), Color(red: 0.85, green: 0.72, blue: 0.48)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let raised = LinearGradient(
        colors: [Color(red: 0.16, green: 0.16, blue: 0.17), Color(red: 0.085, green: 0.085, blue: 0.09)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let inset = LinearGradient(
        colors: [Color(red: 0.03, green: 0.03, blue: 0.035), Color(red: 0.075, green: 0.075, blue: 0.08)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let bevel = LinearGradient(
        colors: [.white.opacity(0.2), .white.opacity(0.03), .black.opacity(0.5)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let insetBevel = LinearGradient(
        colors: [.black.opacity(0.7), .white.opacity(0.0), .white.opacity(0.09)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let backdrop = LinearGradient(
        colors: [Color(red: 0.10, green: 0.10, blue: 0.11), Color(red: 0.02, green: 0.02, blue: 0.025)],
        startPoint: .top, endPoint: .bottom)
}

private struct Raised<S: Shape>: ViewModifier {
    let shape: S
    var depth: CGFloat = 1
    func body(content: Content) -> some View {
        content.background {
            shape.fill(Theme.raised)
                .overlay(shape.stroke(Theme.bevel, lineWidth: 1))
                .shadow(color: .black.opacity(0.7), radius: 6 * depth, x: 3 * depth, y: 4 * depth)
        }
    }
}

private struct Inset<S: Shape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        content.background {
            shape.fill(Theme.inset).overlay(shape.stroke(Theme.insetBevel, lineWidth: 1.2))
        }
    }
}

extension View {
    /// Large raised card (drawer panels).
    func neuCard(_ radius: CGFloat = 22) -> some View { modifier(Raised(shape: RoundedRectangle(cornerRadius: radius, style: .continuous))) }
    func neuRaisedCircle() -> some View { modifier(Raised(shape: Circle(), depth: 0.8)) }
    func neuPill() -> some View { modifier(Raised(shape: Capsule(), depth: 0.7)) }
    /// Recessed capsule: sliders' tracks, segmented controls, readouts.
    func neuTrack() -> some View { modifier(Inset(shape: Capsule())) }
    func neuInsetCapsule() -> some View { modifier(Inset(shape: Capsule())) }
    /// Toggle chip: gold when on, raised when off.
    @ViewBuilder func neuToggle(_ on: Bool) -> some View {
        if on {
            self.background(Capsule().fill(Theme.gold).shadow(color: Theme.champagne.opacity(0.25), radius: 8, y: 2))
        } else {
            self.modifier(Raised(shape: Capsule(), depth: 0.6))
        }
    }
}
