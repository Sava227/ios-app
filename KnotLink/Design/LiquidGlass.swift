import SwiftUI

struct GlassCardModifier<S: Shape>: ViewModifier {
    var tint: Color?
    var shape: S
    var interactive: Bool

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.24), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 14)
            .liquidGlass(tint: tint, shape: shape, interactive: interactive)
    }
}

extension View {
    func glassCard<S: Shape>(
        tint: Color? = nil,
        in shape: S = RoundedRectangle(cornerRadius: 24, style: .continuous),
        interactive: Bool = false
    ) -> some View {
        modifier(GlassCardModifier(tint: tint, shape: shape, interactive: interactive))
    }

    @ViewBuilder
    func liquidGlass<S: Shape>(tint: Color? = nil, shape: S, interactive: Bool = false) -> some View {
        self
    }

    @ViewBuilder
    func prominentGlassButton() -> some View {
        self.buttonStyle(.borderedProminent)
    }
}

struct GlassStack<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
    }
}

extension Color {
    static let knotBlue = Color(red: 0.12, green: 0.27, blue: 0.68)
    static let knotSky = Color(red: 0.33, green: 0.63, blue: 0.95)
    static let knotInk = Color(red: 0.07, green: 0.11, blue: 0.22)
    static let knotLine = Color.white.opacity(0.22)
}

struct KnotBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.91, green: 0.95, blue: 1.0),
                    Color(red: 0.86, green: 0.95, blue: 0.98),
                    Color(red: 1.0, green: 0.94, blue: 0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(colors: [Color.knotSky.opacity(0.45), .clear], center: .topLeading, startRadius: 10, endRadius: 520)
            RadialGradient(colors: [Color.orange.opacity(0.20), .clear], center: .bottomTrailing, startRadius: 10, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}
