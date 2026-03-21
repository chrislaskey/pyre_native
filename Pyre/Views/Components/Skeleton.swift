import SwiftUI

// MARK: - Skeleton View

/// A standalone skeleton loading placeholder with shimmer animation
///
/// Usage:
/// ```swift
/// Skeleton()
///     .frame(height: 44)
///
/// Skeleton(cornerRadius: 12)
///     .frame(width: 200, height: 60)
/// ```
struct Skeleton: View {
    var cornerRadius: CGFloat = 8
    var backgroundColor: Color = Color.gray.opacity(0.1)
    var shimmerColor: Color = Color.gray.opacity(0.2)
    
    @State private var shimmerOffset: CGFloat = -1.5
    
    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)
                .overlay(
                    shimmerGradient(width: geometry.size.width)
                        .offset(x: shimmerOffset * geometry.size.width)
                        .mask(RoundedRectangle(cornerRadius: cornerRadius))
                )
                .clipped()
        }
        .onAppear {
            withAnimation(
                Animation
                    .linear(duration: 1.2)
                    .repeatForever(autoreverses: false)
            ) {
                shimmerOffset = 1.5
            }
        }
    }
    
    private func shimmerGradient(width: CGFloat) -> some View {
        LinearGradient(
            gradient: Gradient(colors: [
                backgroundColor.opacity(0),
                shimmerColor.opacity(0.4),
                backgroundColor.opacity(0)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: width * 1.0)  // Shimmer band is 100% of the skeleton width
    }
}

// MARK: - Skeleton Modifier

/// View modifier that overlays a skeleton when loading
struct SkeletonModifier: ViewModifier {
    let isLoading: Bool
    let height: CGFloat?
    let width: CGFloat?
    let cornerRadius: CGFloat
    let backgroundColor: Color
    let shimmerColor: Color
    let fadeInDuration: Double
    
    @State private var opacity: Double = 0
    
    func body(content: Content) -> some View {
        if isLoading {
            content
                .hidden()
                .overlay(
                    Skeleton(
                        cornerRadius: cornerRadius,
                        backgroundColor: backgroundColor,
                        shimmerColor: shimmerColor
                    )
                    .frame(width: width, height: height)
                    .opacity(opacity)
                    .onAppear {
                        withAnimation(.easeIn(duration: fadeInDuration)) {
                            opacity = 1.0
                        }
                    }
                )
        } else {
            content
        }
    }
}

// MARK: - View Extension

extension View {
    /// Applies a skeleton loading overlay when `isLoading` is true
    ///
    /// The skeleton will match the size of the underlying view by default,
    /// or use explicit dimensions if provided.
    ///
    /// ## Basic Usage:
    /// ```swift
    /// Text("Hello World")
    ///     .skeleton(with: isLoading)
    /// ```
    ///
    /// ## With Custom Dimensions:
    /// ```swift
    /// Text("Hello World")
    ///     .skeleton(with: isLoading, height: 44)
    /// ```
    ///
    /// ## With Custom Corner Radius:
    /// ```swift
    /// Button("Submit") { }
    ///     .skeleton(with: isLoading, cornerRadius: 12)
    /// ```
    ///
    /// ## Fully Customized:
    /// ```swift
    /// Text("Content")
    ///     .skeleton(
    ///         with: isLoading,
    ///         height: 60,
    ///         width: 200,
    ///         cornerRadius: 16,
    ///         backgroundColor: Color.gray.opacity(0.2),
    ///         shimmerColor: Color.gray.opacity(0.4),
    ///         fadeInDuration: 0.3
    ///     )
    /// ```
    ///
    /// - Parameters:
    ///   - isLoading: Whether to show the skeleton overlay
    ///   - height: Optional fixed height for the skeleton (uses view's height if nil)
    ///   - width: Optional fixed width for the skeleton (uses view's width if nil)
    ///   - cornerRadius: Corner radius of the skeleton (default: 8)
    ///   - backgroundColor: Background color of the skeleton
    ///   - shimmerColor: Color of the shimmer highlight
    ///   - fadeInDuration: Duration of the fade-in animation in seconds (default: 0.2)
    /// - Returns: A view with skeleton overlay when loading
    func skeleton(
        with isLoading: Bool,
        height: CGFloat? = nil,
        width: CGFloat? = nil,
        cornerRadius: CGFloat = 8,
        backgroundColor: Color = Color.gray.opacity(0.1),
        shimmerColor: Color = Color.gray.opacity(0.2),
        fadeInDuration: Double = 0.2
    ) -> some View {
        modifier(SkeletonModifier(
            isLoading: isLoading,
            height: height,
            width: width,
            cornerRadius: cornerRadius,
            backgroundColor: backgroundColor,
            shimmerColor: shimmerColor,
            fadeInDuration: fadeInDuration
        ))
    }
}

// MARK: - Preview

#if DEBUG
struct Skeleton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Basic skeleton
            Text("Hello World")
                .font(.headline)
                .frame(height: 24)
                .skeleton(with: true)
            
            // With custom corner radius
            Text("Rounded Button")
                .padding()
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .skeleton(with: true, cornerRadius: 12)
            
            // Circle-like (high corner radius)
            Circle()
                .frame(width: 80, height: 80)
                .skeleton(with: true, cornerRadius: 40)
            
            // Larger content block
            VStack {
                Text("Card Title")
                Text("Card description goes here")
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 120)
            .skeleton(with: true, cornerRadius: 16)
            
            Spacer()
        }
        .padding()
    }
}
#endif

