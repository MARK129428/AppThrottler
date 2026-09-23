import SwiftUI

// MARK: - Theme Option

enum ThemeOption: String, CaseIterable, Identifiable {
    case deepBlue = "deep-blue"
    case midnightPurple = "midnight-purple"
    case darkGreen = "dark-green"
    case system = "system"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .deepBlue: return "深蓝科技"
        case .midnightPurple: return "暗紫夜空"
        case .darkGreen: return "暗绿终端"
        case .system: return "跟随系统"
        }
    }

    var icon: String {
        switch self {
        case .deepBlue: return "moon.stars.fill"
        case .midnightPurple: return "sparkles"
        case .darkGreen: return "leaf.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }
}

// MARK: - App Theme

struct AppTheme: Equatable {
    let option: ThemeOption

    // Backgrounds
    let background: Color
    let surface: Color
    let surfaceElevated: Color
    let surfaceInset: Color

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textInverse: Color

    // Accent
    let accent: Color
    let accentSubtle: Color

    // Status
    let success: Color
    let warning: Color
    let error: Color
    let info: Color

    // Borders & Dividers
    let border: Color
    let divider: Color
    let shadow: Color

    // Charts
    let chartDownload: Color
    let chartUpload: Color

    // Code
    let codeBackground: Color

    // HTTP Methods
    let methodGET: Color
    let methodPOST: Color
    let methodPUT: Color
    let methodDELETE: Color
    let methodPATCH: Color

    // HTTP Status
    let statusSuccess: Color
    let statusRedirect: Color
    let statusClientError: Color
    let statusServerError: Color

    // Protocols
    let protoTCP: Color
    let protoUDP: Color
    let protoICMP: Color
    let protoDNS: Color

    // Resource types
    let typeDocument: Color
    let typeXHR: Color
    let typeCSS: Color
    let typeJS: Color
    let typeImage: Color
    let typeFont: Color
    let typeMedia: Color
    let typeWebSocket: Color
    let typeJSON: Color
    let typeXML: Color

    // Severity
    let severityHigh: Color
    let severityMedium: Color
    let severityLow: Color
    let severityNormal: Color

    // Glass effect
    let usesGlass: Bool
    let glassOpacity: Double
}

// MARK: - Glass Material Extension

extension AppTheme {
    // Material for card/panel backgrounds (frosted glass)
    var surfaceMaterial: Material {
        usesGlass ? .ultraThinMaterial : .regularMaterial
    }

    // Material for elevated elements (popovers, sheets)
    var elevatedMaterial: Material {
        usesGlass ? .thinMaterial : .regularMaterial
    }

    // Background for main window — semi-transparent when glass is on
    var windowBackground: some ShapeStyle {
        if usesGlass {
            return Color.black.opacity(glassOpacity)
        }
        return background
    }
}

// MARK: - Glass View Modifier

struct GlassCardModifier: ViewModifier {
    let theme: AppTheme

    func body(content: Content) -> some View {
        content
            .background(theme.usesGlass ? AnyShapeStyle(theme.surfaceMaterial) : AnyShapeStyle(theme.surface))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(theme.border.opacity(theme.usesGlass ? 0.3 : 0.6), lineWidth: 0.5)
            )
            .shadow(color: theme.usesGlass ? theme.shadow.opacity(0.2) : theme.shadow.opacity(0.4), radius: theme.usesGlass ? 8 : 4)
    }
}

struct GlassPanelModifier: ViewModifier {
    let theme: AppTheme

    func body(content: Content) -> some View {
        content
            .background(theme.usesGlass ? AnyShapeStyle(theme.elevatedMaterial) : AnyShapeStyle(theme.surface))
    }
}

extension View {
    func glassCard(_ theme: AppTheme) -> some View {
        modifier(GlassCardModifier(theme: theme))
    }

    func glassPanel(_ theme: AppTheme) -> some View {
        modifier(GlassPanelModifier(theme: theme))
    }
}

// MARK: - Predefined Themes

extension AppTheme {

    static let deepBlue = AppTheme(
        option: .deepBlue,
        background: Color(red: 0.051, green: 0.067, blue: 0.090),
        surface: Color(red: 0.086, green: 0.106, blue: 0.133),
        surfaceElevated: Color(red: 0.110, green: 0.133, blue: 0.173),
        surfaceInset: Color(red: 0.039, green: 0.051, blue: 0.071),
        textPrimary: Color(red: 0.922, green: 0.937, blue: 0.969),
        textSecondary: Color(red: 0.580, green: 0.639, blue: 0.729),
        textTertiary: Color(red: 0.388, green: 0.439, blue: 0.529),
        textInverse: Color.white,
        accent: Color(red: 0.345, green: 0.647, blue: 1.000),
        accentSubtle: Color(red: 0.345, green: 0.647, blue: 1.000).opacity(0.12),
        success: Color(red: 0.247, green: 0.725, blue: 0.314),
        warning: Color(red: 0.824, green: 0.600, blue: 0.133),
        error: Color(red: 0.973, green: 0.318, blue: 0.286),
        info: Color(red: 0.345, green: 0.647, blue: 1.000),
        border: Color(red: 0.188, green: 0.216, blue: 0.275),
        divider: Color(red: 0.165, green: 0.188, blue: 0.239),
        shadow: Color.black.opacity(0.4),
        chartDownload: Color(red: 0.345, green: 0.647, blue: 1.000),
        chartUpload: Color(red: 0.247, green: 0.725, blue: 0.314),
        codeBackground: Color(red: 0.035, green: 0.047, blue: 0.063),
        methodGET: Color(red: 0.345, green: 0.647, blue: 1.000),
        methodPOST: Color(red: 0.247, green: 0.725, blue: 0.314),
        methodPUT: Color(red: 1.000, green: 0.596, blue: 0.000),
        methodDELETE: Color(red: 0.973, green: 0.318, blue: 0.286),
        methodPATCH: Color(red: 0.725, green: 0.549, blue: 1.000),
        statusSuccess: Color(red: 0.247, green: 0.725, blue: 0.314),
        statusRedirect: Color(red: 1.000, green: 0.596, blue: 0.000),
        statusClientError: Color(red: 0.973, green: 0.318, blue: 0.286),
        statusServerError: Color(red: 0.973, green: 0.318, blue: 0.286),
        protoTCP: Color(red: 0.345, green: 0.647, blue: 1.000),
        protoUDP: Color(red: 0.247, green: 0.725, blue: 0.314),
        protoICMP: Color(red: 1.000, green: 0.596, blue: 0.000),
        protoDNS: Color(red: 0.725, green: 0.549, blue: 1.000),
        typeDocument: Color(red: 0.345, green: 0.647, blue: 1.000),
        typeXHR: Color(red: 0.725, green: 0.549, blue: 1.000),
        typeCSS: Color(red: 0.000, green: 0.737, blue: 0.831),
        typeJS: Color(red: 0.945, green: 0.804, blue: 0.000),
        typeImage: Color(red: 0.247, green: 0.725, blue: 0.314),
        typeFont: Color(red: 1.000, green: 0.596, blue: 0.000),
        typeMedia: Color(red: 1.000, green: 0.431, blue: 0.710),
        typeWebSocket: Color(red: 0.000, green: 0.737, blue: 0.831),
        typeJSON: Color(red: 0.431, green: 0.463, blue: 0.867),
        typeXML: Color(red: 0.000, green: 0.588, blue: 0.533),
        severityHigh: Color(red: 0.973, green: 0.318, blue: 0.286),
        severityMedium: Color(red: 1.000, green: 0.596, blue: 0.000),
        severityLow: Color(red: 0.945, green: 0.804, blue: 0.000),
        severityNormal: Color(red: 0.247, green: 0.725, blue: 0.314),
        usesGlass: true,
        glassOpacity: 0.65
    )

    static let midnightPurple = AppTheme(
        option: .midnightPurple,
        background: Color(red: 0.075, green: 0.043, blue: 0.118),
        surface: Color(red: 0.102, green: 0.063, blue: 0.157),
        surfaceElevated: Color(red: 0.133, green: 0.090, blue: 0.200),
        surfaceInset: Color(red: 0.055, green: 0.031, blue: 0.090),
        textPrimary: Color(red: 0.929, green: 0.910, blue: 0.969),
        textSecondary: Color(red: 0.639, green: 0.580, blue: 0.729),
        textTertiary: Color(red: 0.439, green: 0.388, blue: 0.529),
        textInverse: Color.white,
        accent: Color(red: 0.737, green: 0.549, blue: 1.000),
        accentSubtle: Color(red: 0.737, green: 0.549, blue: 1.000).opacity(0.12),
        success: Color(red: 0.247, green: 0.725, blue: 0.314),
        warning: Color(red: 0.824, green: 0.600, blue: 0.133),
        error: Color(red: 0.973, green: 0.318, blue: 0.286),
        info: Color(red: 0.737, green: 0.549, blue: 1.000),
        border: Color(red: 0.239, green: 0.188, blue: 0.314),
        divider: Color(red: 0.200, green: 0.165, blue: 0.275),
        shadow: Color.black.opacity(0.5),
        chartDownload: Color(red: 0.737, green: 0.549, blue: 1.000),
        chartUpload: Color(red: 0.247, green: 0.725, blue: 0.314),
        codeBackground: Color(red: 0.051, green: 0.027, blue: 0.082),
        methodGET: Color(red: 0.737, green: 0.549, blue: 1.000),
        methodPOST: Color(red: 0.247, green: 0.725, blue: 0.314),
        methodPUT: Color(red: 1.000, green: 0.596, blue: 0.000),
        methodDELETE: Color(red: 0.973, green: 0.318, blue: 0.286),
        methodPATCH: Color(red: 0.737, green: 0.549, blue: 1.000),
        statusSuccess: Color(red: 0.247, green: 0.725, blue: 0.314),
        statusRedirect: Color(red: 1.000, green: 0.596, blue: 0.000),
        statusClientError: Color(red: 0.973, green: 0.318, blue: 0.286),
        statusServerError: Color(red: 0.973, green: 0.318, blue: 0.286),
        protoTCP: Color(red: 0.737, green: 0.549, blue: 1.000),
        protoUDP: Color(red: 0.247, green: 0.725, blue: 0.314),
        protoICMP: Color(red: 1.000, green: 0.596, blue: 0.000),
        protoDNS: Color(red: 0.737, green: 0.549, blue: 1.000),
        typeDocument: Color(red: 0.737, green: 0.549, blue: 1.000),
        typeXHR: Color(red: 0.906, green: 0.549, blue: 1.000),
        typeCSS: Color(red: 0.000, green: 0.737, blue: 0.831),
        typeJS: Color(red: 0.945, green: 0.804, blue: 0.000),
        typeImage: Color(red: 0.247, green: 0.725, blue: 0.314),
        typeFont: Color(red: 1.000, green: 0.596, blue: 0.000),
        typeMedia: Color(red: 1.000, green: 0.431, blue: 0.710),
        typeWebSocket: Color(red: 0.000, green: 0.737, blue: 0.831),
        typeJSON: Color(red: 0.431, green: 0.463, blue: 0.867),
        typeXML: Color(red: 0.000, green: 0.588, blue: 0.533),
        severityHigh: Color(red: 0.973, green: 0.318, blue: 0.286),
        severityMedium: Color(red: 1.000, green: 0.596, blue: 0.000),
        severityLow: Color(red: 0.945, green: 0.804, blue: 0.000),
        severityNormal: Color(red: 0.247, green: 0.725, blue: 0.314),
        usesGlass: true,
        glassOpacity: 0.60
    )

    static let darkGreen = AppTheme(
        option: .darkGreen,
        background: Color(red: 0.039, green: 0.102, blue: 0.059),
        surface: Color(red: 0.059, green: 0.141, blue: 0.082),
        surfaceElevated: Color(red: 0.078, green: 0.180, blue: 0.106),
        surfaceInset: Color(red: 0.027, green: 0.078, blue: 0.043),
        textPrimary: Color(red: 0.878, green: 0.949, blue: 0.890),
        textSecondary: Color(red: 0.549, green: 0.710, blue: 0.580),
        textTertiary: Color(red: 0.380, green: 0.510, blue: 0.408),
        textInverse: Color.white,
        accent: Color(red: 0.247, green: 0.725, blue: 0.314),
        accentSubtle: Color(red: 0.247, green: 0.725, blue: 0.314).opacity(0.12),
        success: Color(red: 0.247, green: 0.725, blue: 0.314),
        warning: Color(red: 0.824, green: 0.600, blue: 0.133),
        error: Color(red: 0.973, green: 0.318, blue: 0.286),
        info: Color(red: 0.345, green: 0.647, blue: 1.000),
        border: Color(red: 0.133, green: 0.267, blue: 0.165),
        divider: Color(red: 0.110, green: 0.220, blue: 0.137),
        shadow: Color.black.opacity(0.4),
        chartDownload: Color(red: 0.345, green: 0.647, blue: 1.000),
        chartUpload: Color(red: 0.247, green: 0.725, blue: 0.314),
        codeBackground: Color(red: 0.024, green: 0.063, blue: 0.035),
        methodGET: Color(red: 0.345, green: 0.647, blue: 1.000),
        methodPOST: Color(red: 0.247, green: 0.725, blue: 0.314),
        methodPUT: Color(red: 1.000, green: 0.596, blue: 0.000),
        methodDELETE: Color(red: 0.973, green: 0.318, blue: 0.286),
        methodPATCH: Color(red: 0.725, green: 0.549, blue: 1.000),
        statusSuccess: Color(red: 0.247, green: 0.725, blue: 0.314),
        statusRedirect: Color(red: 1.000, green: 0.596, blue: 0.000),
        statusClientError: Color(red: 0.973, green: 0.318, blue: 0.286),
        statusServerError: Color(red: 0.973, green: 0.318, blue: 0.286),
        protoTCP: Color(red: 0.345, green: 0.647, blue: 1.000),
        protoUDP: Color(red: 0.247, green: 0.725, blue: 0.314),
        protoICMP: Color(red: 1.000, green: 0.596, blue: 0.000),
        protoDNS: Color(red: 0.725, green: 0.549, blue: 1.000),
        typeDocument: Color(red: 0.345, green: 0.647, blue: 1.000),
        typeXHR: Color(red: 0.725, green: 0.549, blue: 1.000),
        typeCSS: Color(red: 0.000, green: 0.737, blue: 0.831),
        typeJS: Color(red: 0.945, green: 0.804, blue: 0.000),
        typeImage: Color(red: 0.247, green: 0.725, blue: 0.314),
        typeFont: Color(red: 1.000, green: 0.596, blue: 0.000),
        typeMedia: Color(red: 1.000, green: 0.431, blue: 0.710),
        typeWebSocket: Color(red: 0.000, green: 0.737, blue: 0.831),
        typeJSON: Color(red: 0.431, green: 0.463, blue: 0.867),
        typeXML: Color(red: 0.000, green: 0.588, blue: 0.533),
        severityHigh: Color(red: 0.973, green: 0.318, blue: 0.286),
        severityMedium: Color(red: 1.000, green: 0.596, blue: 0.000),
        severityLow: Color(red: 0.945, green: 0.804, blue: 0.000),
        severityNormal: Color(red: 0.247, green: 0.725, blue: 0.314),
        usesGlass: true,
        glassOpacity: 0.70
    )

    // System theme uses native macOS colors
    static let system = AppTheme(
        option: .system,
        background: Color(nsColor: .windowBackgroundColor),
        surface: Color(nsColor: .controlBackgroundColor),
        surfaceElevated: Color(nsColor: .controlBackgroundColor),
        surfaceInset: Color(nsColor: .textBackgroundColor),
        textPrimary: Color(nsColor: .labelColor),
        textSecondary: Color(nsColor: .secondaryLabelColor),
        textTertiary: Color(nsColor: .tertiaryLabelColor),
        textInverse: Color.white,
        accent: Color.accentColor,
        accentSubtle: Color.accentColor.opacity(0.12),
        success: .green,
        warning: .orange,
        error: .red,
        info: .blue,
        border: Color(nsColor: .separatorColor),
        divider: Color(nsColor: .separatorColor),
        shadow: Color.black.opacity(0.2),
        chartDownload: .blue,
        chartUpload: .green,
        codeBackground: Color(nsColor: .textBackgroundColor),
        methodGET: .blue,
        methodPOST: .green,
        methodPUT: .orange,
        methodDELETE: .red,
        methodPATCH: .purple,
        statusSuccess: .green,
        statusRedirect: .orange,
        statusClientError: .red,
        statusServerError: .red,
        protoTCP: .blue,
        protoUDP: .green,
        protoICMP: .orange,
        protoDNS: .purple,
        typeDocument: .blue,
        typeXHR: .purple,
        typeCSS: .cyan,
        typeJS: .yellow,
        typeImage: .green,
        typeFont: .orange,
        typeMedia: .pink,
        typeWebSocket: .mint,
        typeJSON: .indigo,
        typeXML: .teal,
        severityHigh: .red,
        severityMedium: .orange,
        severityLow: .yellow,
        severityNormal: .green,
        usesGlass: false,
        glassOpacity: 1.0
    )

    static let allThemes: [AppTheme] = [.deepBlue, .midnightPurple, .darkGreen, .system]
}

// MARK: - Theme Manager

@MainActor
class ThemeManager: ObservableObject {
    @Published var currentTheme: AppTheme = .deepBlue
    @Published var option: ThemeOption = .deepBlue

    static let shared = ThemeManager()

    private let defaultsKey = "AppThrottler.ThemeOption"

    init() {
        loadSavedTheme()
    }

    func select(_ option: ThemeOption) {
        self.option = option
        let theme = AppTheme.allThemes.first(where: { $0.option == option })
        self.currentTheme = theme ?? AppTheme.deepBlue
        UserDefaults.standard.set(option.rawValue, forKey: defaultsKey)
    }

    private func loadSavedTheme() {
        let saved = UserDefaults.standard.string(forKey: defaultsKey) ?? ThemeOption.deepBlue.rawValue
        let opt = ThemeOption(rawValue: saved) ?? .deepBlue
        select(opt)
    }

    var isCustomDark: Bool {
        option != .system
    }
}
