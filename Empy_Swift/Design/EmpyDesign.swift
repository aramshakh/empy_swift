//
//  EmpyDesign.swift
//  Empy_Swift
//
//  Empy design system extracted from empy-trone
//  Reference: empyai/empy-trone/src/renderer/styles/index.css
//

import SwiftUI

// MARK: - Colors

extension Color {
    // Primary & Accent
    static let empyPrimary = Color(red: 0.902, green: 0.204, blue: 0.384) // oklch(0.67 0.29 341.41) → rose/pink
    static let empyAccent = Color(red: 0.396, green: 0.400, blue: 0.945)  // indigo-500 (#6366F1)
    static let empySuccess = Color(red: 0.063, green: 0.725, blue: 0.506) // emerald-500 (#10b981)
    
    // Backgrounds (Light Mode)
    static let empyBackgroundLight = Color(red: 0.980, green: 0.980, blue: 0.980) // oklch(0.98) → #FAFAFA
    static let empyCardLight = Color.white
    static let empySecondaryLight = Color(red: 0.960, green: 0.960, blue: 0.960) // light gray
    
    // Backgrounds (Dark Mode)
    static let empyBackgroundDark = Color(red: 0.160, green: 0.160, blue: 0.180) // dark purple-gray
    static let empyCardDark = Color(red: 0.200, green: 0.200, blue: 0.220)
    
    // Foregrounds
    static let empyForegroundLight = Color(red: 0.100, green: 0.100, blue: 0.100) // near-black
    static let empyForegroundDark = Color(red: 0.950, green: 0.950, blue: 0.950)  // off-white
    
    // Borders
    static let empyBorderLight = Color(red: 0.920, green: 0.920, blue: 0.920)
    static let empyBorderDark = Color(red: 0.250, green: 0.250, blue: 0.280)
    
    // Semantic
    static let empySecondaryText = Color(red: 0.620, green: 0.620, blue: 0.640) // gray-500
    
    // Gradient (Background)
    static let empyGradientLight = LinearGradient(
        colors: [
            Color(red: 0.878, green: 0.878, blue: 1.0),    // indigo-50
            Color(red: 1.0, green: 0.894, blue: 0.894)     // rose-50
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let empyGradientDark = LinearGradient(
        colors: [
            Color(red: 0.157, green: 0.157, blue: 0.180),  // zinc-800
            Color(red: 0.113, green: 0.113, blue: 0.122)   // zinc-900
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Typography

extension Font {
    // Titles
    static let empyTitle = Font.system(size: 24, weight: .semibold) // text-2xl font-semibold
    
    // Body
    static let empyBody = Font.system(size: 16, weight: .regular)      // text-base
    static let empyBodyMedium = Font.system(size: 16, weight: .medium)
    
    // Labels
    static let empyLabel = Font.system(size: 14, weight: .medium)   // text-sm font-medium
    static let empyLabelRegular = Font.system(size: 14, weight: .regular)
    
    // Captions
    static let empyCaption = Font.system(size: 12, weight: .regular) // text-xs
    static let empyCaptionMedium = Font.system(size: 12, weight: .medium)
    static let empyCaptionSemibold = Font.system(size: 12, weight: .semibold)
    
    // Small
    static let empySmall = Font.system(size: 11, weight: .regular)
    static let empyTiny = Font.system(size: 10, weight: .semibold)
}

// MARK: - Spacing

struct EmpySpacing {
    static let xxs: CGFloat = 4   // 4px
    static let xs: CGFloat = 8    // 8px
    static let sm: CGFloat = 12   // 12px (p-3, space-y-3)
    static let md: CGFloat = 16   // 16px (p-4, space-y-4)
    static let lg: CGFloat = 20   // 20px
    static let xl: CGFloat = 24   // 24px
    static let xxl: CGFloat = 32  // 32px
}

// MARK: - Border Radius

struct EmpyRadius {
    static let sm: CGFloat = 6    // rounded-md
    static let md: CGFloat = 8    // rounded-lg
    static let lg: CGFloat = 12   // rounded-xl
    static let xl: CGFloat = 16   // rounded-2xl
    static let full: CGFloat = 9999 // rounded-full
}

// MARK: - Shadows

extension View {
    func empyShadowSm() -> some View {
        self.shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 2)
    }
    
    func empyShadowMd() -> some View {
        self.shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 4)
    }
    
    func empyShadowXl() -> some View {
        self.shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 8)
    }
}

// MARK: - Styled Components

struct EmpyCard<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(EmpySpacing.sm)
            .background(colorScheme == .dark ? Color.empyCardDark : Color.empyCardLight)
            .cornerRadius(EmpyRadius.xl)
            .empyShadowSm()
    }
}

struct EmpyButton: View {
    let title: String
    let action: () -> Void
    var style: ButtonStyle = .primary
    
    enum ButtonStyle {
        case primary
        case secondary
    }
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.empyBodyMedium)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, EmpySpacing.sm)
                .background(style == .primary ? Color.empyAccent : Color.empySecondaryText)
                .cornerRadius(EmpyRadius.md)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Layout Constants

struct EmpyLayout {
    static let maxWidth: CGFloat = 576    // max-w-xl
    static let pagePadding: CGFloat = 16  // px-4
}
