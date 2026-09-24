import SwiftUI

// MARK: - Toast Notification System

enum ToastType {
    case success
    case error
    case warning
    case info

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    func color(theme: AppTheme) -> Color {
        switch self {
        case .success: return theme.success
        case .error: return theme.error
        case .warning: return theme.warning
        case .info: return theme.info
        }
    }
}

struct ToastItem: Identifiable {
    let id = UUID()
    let type: ToastType
    let title: String
    let message: String?
    let duration: TimeInterval

    init(type: ToastType, title: String, message: String? = nil, duration: TimeInterval = 3.0) {
        self.type = type
        self.title = title
        self.message = message
        self.duration = duration
    }
}

@MainActor
class ToastManager: ObservableObject {
    @Published var toasts: [ToastItem] = []

    func show(_ toast: ToastItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            toasts.append(toast)
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(toast.duration * 1_000_000_000))
            dismiss(toast)
        }
    }

    func dismiss(_ toast: ToastItem) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toasts.removeAll { $0.id == toast.id }
        }
    }

    // Convenience methods
    func success(_ title: String, _ message: String? = nil) {
        show(ToastItem(type: .success, title: title, message: message))
    }

    func error(_ title: String, _ message: String? = nil) {
        show(ToastItem(type: .error, title: title, message: message, duration: 5.0))
    }

    func warning(_ title: String, _ message: String? = nil) {
        show(ToastItem(type: .warning, title: title, message: message, duration: 4.0))
    }

    func info(_ title: String, _ message: String? = nil) {
        show(ToastItem(type: .info, title: title, message: message))
    }
}

// MARK: - Toast Overlay View

struct ToastOverlay: View {
    @ObservedObject var toastManager: ToastManager
    let theme: AppTheme

    var body: some View {
        VStack(spacing: 8) {
            ForEach(toastManager.toasts) { toast in
                ToastView(toast: toast, theme: theme) {
                    toastManager.dismiss(toast)
                }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 0.95))
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
        .allowsHitTesting(!toastManager.toasts.isEmpty)
    }
}

struct ToastView: View {
    let toast: ToastItem
    let theme: AppTheme
    let onDismiss: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.type.icon)
                .font(.title3)
                .foregroundStyle(toast.type.color(theme: theme))
                .symbolEffect(.bounce, value: toast.id)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(theme.textPrimary)
                if let msg = toast.message {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 20, height: 20)
                    .background(theme.surface.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 400)
        .background(theme.usesGlass ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(theme.surfaceElevated))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(toast.type.color(theme: theme).opacity(0.3), lineWidth: 1)
        )
        .shadow(color: theme.shadow.opacity(0.3), radius: 8, y: 4)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Loading Spinner

struct ThrottleLoadingView: View {
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在应用限速...")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.accent.opacity(0.08))
        .clipShape(Capsule())
    }
}

// MARK: - Active Badge (animated)

struct ActiveBadge: View {
    let label: String
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.shield.fill")
                .font(.caption2)
                .symbolEffect(.pulse, isActive: true)
            Text(label)
                .font(.caption2.bold())
        }
        .foregroundStyle(theme.warning)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(theme.warning.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Hover Card Effect

struct HoverCardModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .shadow(color: .black.opacity(isHovered ? 0.15 : 0.05), radius: isHovered ? 8 : 2, y: isHovered ? 4 : 1)
            .animation(.easeOut(duration: 0.2), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    func hoverCard() -> some View {
        modifier(HoverCardModifier())
    }
}
