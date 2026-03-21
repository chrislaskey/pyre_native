//
//  ToastMessage.swift
//  Reusable toast/snackbar component for temporary notifications
//

import SwiftUI

/// Toast message type
enum ToastType {
    case success
    case error
    case info
    case warning
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        case .warning: return .orange
        }
    }
}

/// Toast message data
struct ToastData: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let type: ToastType
    let duration: TimeInterval
    
    init(message: String, type: ToastType = .info, duration: TimeInterval = 3.0) {
        self.message = message
        self.type = type
        self.duration = duration
    }
    
    static func == (lhs: ToastData, rhs: ToastData) -> Bool {
        lhs.id == rhs.id
    }
}

/// Toast message view
struct ToastMessage: View {
    let data: ToastData
    @Binding var isPresented: Bool
    
    @State private var offset: CGFloat = -100
    @State private var opacity: Double = 0
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: data.type.icon)
                .font(.system(size: 20))
                .foregroundColor(data.type.color)
            
            Text(data.message)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .offset(y: offset)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                offset = 0
                opacity = 1
            }
            
            // Auto-dismiss after duration
            DispatchQueue.main.asyncAfter(deadline: .now() + data.duration) {
                dismiss()
            }
        }
    }
    
    private func dismiss() {
        withAnimation(.easeOut(duration: 0.3)) {
            offset = -100
            opacity = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isPresented = false
        }
    }
}

/// View modifier to show toast messages
struct ToastModifier: ViewModifier {
    @Binding var toast: ToastData?
    
    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            
            if let toast = toast {
                ToastMessage(
                    data: toast,
                    isPresented: Binding(
                        get: { self.toast != nil },
                        set: { if !$0 { self.toast = nil } }
                    )
                )
                .padding(.top, 60)
                .zIndex(999)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

extension View {
    /// Show a toast message
    func toast(_ toast: Binding<ToastData?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}
