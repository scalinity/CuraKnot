import SwiftUI

// MARK: - Design Tokens

enum DesignTokens {
    // MARK: - Colors
    
    enum Colors {
        static let primary = Color.accentColor
        static let secondary = Color.secondary
        
        // Status colors
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue
        
        // Priority colors
        static let priorityHigh = Color.red
        static let priorityMed = Color.orange
        static let priorityLow = Color.green
        
        // Role colors
        static func roleColor(_ role: String) -> Color {
            switch role.uppercased() {
            case "OWNER": return .purple
            case "ADMIN": return .blue
            case "CONTRIBUTOR": return .green
            case "VIEWER": return .gray
            default: return .gray
            }
        }
        
        // Handoff type colors
        static func handoffTypeColor(_ type: String) -> Color {
            switch type.uppercased() {
            case "VISIT": return .blue
            case "CALL": return .green
            case "APPOINTMENT": return .purple
            case "FACILITY_UPDATE": return .orange
            default: return .gray
            }
        }
    }
    
    // MARK: - Typography
    
    enum Typography {
        static let largeTitle = Font.largeTitle
        static let title = Font.title
        static let title2 = Font.title2
        static let title3 = Font.title3
        static let headline = Font.headline
        static let body = Font.body
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let caption = Font.caption
        static let caption2 = Font.caption2
    }
    
    // MARK: - Spacing
    
    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }
    
    // MARK: - Corner Radius
    
    enum CornerRadius {
        static let small: CGFloat = 4
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let xLarge: CGFloat = 16
        static let full: CGFloat = 9999
    }
    
    // MARK: - Shadows
    
    enum Shadows {
        static let small = ShadowStyle(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        static let medium = ShadowStyle(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        static let large = ShadowStyle(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
    
    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

// MARK: - View Extensions

extension View {
    func cardStyle() -> some View {
        self
            .padding(DesignTokens.Spacing.md)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(DesignTokens.CornerRadius.large)
    }
    
    func shadow(_ style: DesignTokens.ShadowStyle) -> some View {
        self.shadow(
            color: style.color,
            radius: style.radius,
            x: style.x,
            y: style.y
        )
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Self.Configuration) -> some View {
        let fillColor: Color = isEnabled ? DesignTokens.Colors.primary : Color.gray
        return configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(fillColor, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.medium))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(DesignTokens.Colors.primary)
            .frame(maxWidth: .infinity)
            .padding()
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.medium)
                    .stroke(DesignTokens.Colors.primary, lineWidth: 2)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Loading View

struct LoadingOverlay: View {
    let message: String?
    
    init(_ message: String? = nil) {
        self.message = message
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: DesignTokens.Spacing.md) {
                ProgressView()
                    .scaleEffect(1.2)
                
                if let message = message {
                    Text(message)
                        .font(.subheadline)
                }
            }
            .padding(DesignTokens.Spacing.lg)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.large))
        }
    }
}

// MARK: - Toast View

struct ToastView: View {
    let message: String
    let type: ToastType
    
    enum ToastType {
        case success
        case error
        case info
        case warning
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .success: return DesignTokens.Colors.success
            case .error: return DesignTokens.Colors.error
            case .info: return DesignTokens.Colors.info
            case .warning: return DesignTokens.Colors.warning
            }
        }
    }
    
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: type.icon)
                .foregroundStyle(type.color)
            
            Text(message)
                .font(.subheadline)
        }
        .padding(DesignTokens.Spacing.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.large))
        .shadow(DesignTokens.Shadows.medium)
    }
}

// MARK: - Skeleton View

struct SkeletonView: View {
    @State private var isAnimating = false
    
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.gray.opacity(0.3),
                Color.gray.opacity(0.1),
                Color.gray.opacity(0.3)
            ]),
            startPoint: isAnimating ? .leading : .trailing,
            endPoint: isAnimating ? .trailing : .leading
        )
        .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}

struct SkeletonCell: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonView()
                .frame(height: 20)
                .cornerRadius(4)
            
            SkeletonView()
                .frame(width: 200, height: 16)
                .cornerRadius(4)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    VStack(spacing: 20) {
        Button("Primary Button") {}
            .buttonStyle(.primary)
        
        Button("Secondary Button") {}
            .buttonStyle(.secondary)
        
        ToastView(message: "Action completed", type: .success)
        ToastView(message: "Something went wrong", type: .error)
        
        SkeletonCell()
    }
    .padding()
}
