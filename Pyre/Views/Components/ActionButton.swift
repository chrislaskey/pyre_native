import SwiftUI

/// Button style types for ActionButton
enum ActionButtonType {
    case primary      // Solid background (default)
    case secondary    // Solid background with 80% opacity
    case tertiary     // Very light background (5% opacity)
}

/// A reusable action button component for consistent CTA styling across the app.
///
/// This component provides a unified button style with support for:
/// - Three button types: primary (solid), secondary (80% opacity), tertiary (light background)
/// - Loading states with spinner
/// - Custom background and foreground colors
/// - Optional icons
/// - Disabled states
/// - Consistent padding and sizing
///
/// Usage:
/// ```swift
/// // Primary button (solid background)
/// ActionButton(
///     title: "Sign In",
///     icon: "person.fill",
///     backgroundColor: .blue,
///     isLoading: viewModel.isSubmitting,
///     isDisabled: !viewModel.isValid
/// ) {
///     viewModel.submit()
/// }
///
/// // Secondary button (80% opacity)
/// ActionButton(
///     title: "Cancel",
///     type: .secondary,
///     backgroundColor: .blue
/// ) {
///     dismiss()
/// }
///
/// // Tertiary button (light background)
/// ActionButton(
///     title: "Sign Out",
///     type: .tertiary,
///     foregroundColor: .blue
/// ) {
///     signOut()
/// }
/// ```
struct ActionButton: View {
    let title: String
    let icon: String?
    let type: ActionButtonType
    let backgroundColor: Color
    let foregroundColor: Color
    let borderColor: Color?
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void
    
    init(
        title: String,
        icon: String? = nil,
        type: ActionButtonType = .primary,
        backgroundColor: Color = .blue,
        foregroundColor: Color? = nil,
        borderColor: Color? = nil,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.type = type
        self.backgroundColor = backgroundColor
        
        // Set foreground color based on type if not explicitly provided
        if let foregroundColor = foregroundColor {
            self.foregroundColor = foregroundColor
        } else {
            switch type {
            case .primary, .secondary:
                self.foregroundColor = .white
            case .tertiary:
                self.foregroundColor = .primary
            }
        }
        
        // Border color not used anymore, but keep for compatibility
        self.borderColor = borderColor ?? .clear
        
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            buttonContent
        }
        .buttonStyle(ActionButtonStyle(
            type: type,
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            borderColor: borderColor ?? foregroundColor.opacity(0.3)
        ))
        .disabled(isLoading || isDisabled)
    }
    
    @ViewBuilder
    private var buttonContent: some View {
        HStack(spacing: 12) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: foregroundColor))
            } else if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
            }
            
            Text(title)
                .fontWeight(type == .tertiary ? .medium : .semibold)
        }
    }
}

/// Custom button style that prevents the double-box issue
struct ActionButtonStyle: ButtonStyle {
    let type: ActionButtonType
    let backgroundColor: Color
    let foregroundColor: Color
    let borderColor: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundColor(foregroundColor)
            .background(backgroundForType)
            .cornerRadius(10)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
    
    @ViewBuilder
    private var backgroundForType: some View {
        switch type {
        case .primary:
            backgroundColor
        case .secondary:
            backgroundColor.opacity(0.6)
        case .tertiary:
            Color.primary.opacity(0.05)
        }
    }
}

