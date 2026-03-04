//
//  EmpyDesignSystem.swift
//  empy
//
//  Created by Aramius (Agent) on 2026-03-04.
//  Design system extracted from empyai/empy-trone
//

import SwiftUI

// MARK: - Colors

struct EmpyColors {
    // MARK: Emotion Palette (Light Mode)
    // Converted from OKLch color space using mathematical approximation
    
    /// em-happy: oklch(0.85 0.20 85) - Warm yellow/orange
    static let happy = Color(red: 0.98, green: 0.80, blue: 0.40)
    
    /// em-surprised: oklch(0.65 0.22 180) - Teal/cyan
    static let surprised = Color(red: 0.18, green: 0.68, blue: 0.68)
    
    /// em-sad: oklch(0.75 0.15 230) - Bright blue
    static let sad = Color(red: 0.45, green: 0.68, blue: 0.92)
    
    /// em-nervous: oklch(0.70 0.25 292.96) - Purple
    static let nervous = Color(red: 0.70, green: 0.48, blue: 0.85)
    
    /// em-neutral: oklch(0.68 0.22 28) - Red/orange
    static let neutral = Color(red: 0.88, green: 0.42, blue: 0.35)
    
    /// em-angry: oklch(0.60 0.25 25) - Deeper red
    static let angry = Color(red: 0.80, green: 0.30, blue: 0.28)
    
    // MARK: Semantic Colors
    
    static let primary = happy        // Yellow/Orange (main brand color)
    static let secondary = sad         // Blue (secondary actions)
    static let accent = surprised      // Teal (highlights)
    static let accentPurple = nervous  // Purple (alternative accent)
    static let destructive = neutral   // Red (warnings/errors)
    
    // MARK: Background Colors (Light Mode)
    
    /// Main background: oklch(0.98 0.00 228.78)
    static let background = Color(red: 0.98, green: 0.98, blue: 0.98)
    
    /// Lighter background: oklch(0.99 0.00 228.78)
    static let backgroundLighter = Color(red: 0.99, green: 0.99, blue: 0.99)
    
    /// Foreground text: oklch(0.32 0 0)
    static let foreground = Color(red: 0.32, green: 0.32, blue: 0.32)
    
    /// Card background: oklch(1.00 0 0)
    static let cardBackground = Color.white
    
    /// Border: oklch(0.87 0 0)
    static let border = Color(red: 0.87, green: 0.87, blue: 0.87)
    
    // MARK: Gradient Backgrounds
    
    /// Main gradient background used on Create and Recording screens
    static func gradientBackground(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            // from-zinc-800 to-zinc-900
            return LinearGradient(
                colors: [
                    Color(red: 39/255, green: 39/255, blue: 42/255),
                    Color(red: 24/255, green: 24/255, blue: 27/255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            // from-indigo-50 to-rose-50
            return LinearGradient(
                colors: [
                    Color(red: 238/255, green: 242/255, blue: 255/255),  // indigo-50
                    Color(red: 255/255, green: 241/255, blue: 242/255)   // rose-50
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    // MARK: Dark Mode Colors
    
    struct Dark {
        /// Background: oklch(0.23 0.01 264.29)
        static let background = Color(red: 0.23, green: 0.23, blue: 0.24)
        
        /// Background lighter: oklch(0.30 0.01 264.29)
        static let backgroundLighter = Color(red: 0.30, green: 0.30, blue: 0.31)
        
        /// Foreground: oklch(0.92 0 0)
        static let foreground = Color(red: 0.92, green: 0.92, blue: 0.92)
        
        /// Card: oklch(0.32 0.01 223.67)
        static let cardBackground = Color(red: 0.32, green: 0.32, blue: 0.33)
        
        /// Border: oklch(0.39 0 0)
        static let border = Color(red: 0.39, green: 0.39, blue: 0.39)
        
        // Emotion colors (adjusted lightness for dark mode)
        static let happy = Color(red: 0.95, green: 0.75, blue: 0.35)
        static let surprised = Color(red: 0.15, green: 0.63, blue: 0.63)
        static let sad = Color(red: 0.40, green: 0.63, blue: 0.87)
        static let nervous = Color(red: 0.65, green: 0.43, blue: 0.80)
        static let neutral = Color(red: 0.80, green: 0.37, blue: 0.30)
        static let angry = Color(red: 0.72, green: 0.25, blue: 0.23)
    }
}

// MARK: - Typography

struct EmpyFonts {
    /// Primary font family (Poppins)
    static let sans = "Poppins"
    
    /// Monospace font family (Roboto Mono)
    static let mono = "RobotoMono"
    
    // MARK: Font Styles
    
    /// Heading 1: 24px semibold
    static func h1() -> Font {
        .custom(sans, size: 24).weight(.semibold)
    }
    
    /// Heading 2: 20px semibold
    static func h2() -> Font {
        .custom(sans, size: 20).weight(.semibold)
    }
    
    /// Body text: 16px regular
    static func body() -> Font {
        .custom(sans, size: 16)
    }
    
    /// Body text: 16px medium
    static func bodyMedium() -> Font {
        .custom(sans, size: 16).weight(.medium)
    }
    
    /// Label text: 14px medium
    static func label() -> Font {
        .custom(sans, size: 14).weight(.medium)
    }
    
    /// Caption text: 12px regular
    static func caption() -> Font {
        .custom(sans, size: 12)
    }
    
    /// Tiny text: 11px medium
    static func tiny() -> Font {
        .custom(sans, size: 11).weight(.medium)
    }
    
    /// Monospace: 14px regular
    static func mono() -> Font {
        .custom(Self.mono, size: 14)
    }
}

// MARK: - Spacing

struct EmpySpacing {
    /// 4px
    static let xs: CGFloat = 4
    
    /// 8px
    static let sm: CGFloat = 8
    
    /// 12px
    static let md: CGFloat = 12
    
    /// 16px
    static let lg: CGFloat = 16
    
    /// 20px
    static let xl: CGFloat = 20
    
    /// 24px
    static let xxl: CGFloat = 24
    
    /// 32px
    static let xxxl: CGFloat = 32
    
    /// 40px
    static let xxxxl: CGFloat = 40
}

// MARK: - Border Radius

struct EmpyRadius {
    /// 4px (sm)
    static let sm: CGFloat = 4
    
    /// 6px (md)
    static let md: CGFloat = 6
    
    /// 8px (lg, base radius)
    static let lg: CGFloat = 8
    
    /// 12px (xl)
    static let xl: CGFloat = 12
    
    /// 16px (2xl, for cards)
    static let xxl: CGFloat = 16
    
    /// 9999px (full, for pills/badges)
    static let full: CGFloat = 9999
}

// MARK: - Shadows

struct EmpyShadow {
    /// Small shadow (cards)
    static let sm = Color.black.opacity(0.10)
    static let smRadius: CGFloat = 3
    static let smX: CGFloat = 0
    static let smY: CGFloat = 1
    
    /// Medium shadow (dropdowns)
    static let md = Color.black.opacity(0.10)
    static let mdRadius: CGFloat = 6
    static let mdX: CGFloat = 0
    static let mdY: CGFloat = 2
    
    /// Large shadow (modals)
    static let lg = Color.black.opacity(0.10)
    static let lgRadius: CGFloat = 10
    static let lgX: CGFloat = 0
    static let lgY: CGFloat = 4
    
    /// Extra large shadow (overlays)
    static let xl = Color.black.opacity(0.10)
    static let xlRadius: CGFloat = 15
    static let xlX: CGFloat = 0
    static let xlY: CGFloat = 8
}

// MARK: - View Modifiers

extension View {
    /// Apply Empy card styling
    func empyCard(colorScheme: ColorScheme = .light) -> some View {
        self
            .background(colorScheme == .dark ? EmpyColors.Dark.cardBackground : EmpyColors.cardBackground)
            .cornerRadius(EmpyRadius.xxl)
            .shadow(color: EmpyShadow.sm, radius: EmpyShadow.smRadius, x: EmpyShadow.smX, y: EmpyShadow.smY)
    }
    
    /// Apply Empy gradient background
    func empyGradientBackground(colorScheme: ColorScheme) -> some View {
        self.background(EmpyColors.gradientBackground(for: colorScheme))
    }
    
    /// Apply Empy button styling (primary)
    func empyPrimaryButton() -> some View {
        self
            .font(EmpyFonts.bodyMedium())
            .foregroundColor(.white)
            .padding(.horizontal, EmpySpacing.xxl)
            .padding(.vertical, EmpySpacing.md)
            .background(EmpyColors.primary)
            .cornerRadius(EmpyRadius.lg)
    }
    
    /// Apply Empy button styling (secondary)
    func empySecondaryButton(colorScheme: ColorScheme = .light) -> some View {
        self
            .font(EmpyFonts.bodyMedium())
            .foregroundColor(colorScheme == .dark ? EmpyColors.Dark.foreground : EmpyColors.foreground)
            .padding(.horizontal, EmpySpacing.xxl)
            .padding(.vertical, EmpySpacing.md)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: EmpyRadius.lg)
                    .stroke(colorScheme == .dark ? EmpyColors.Dark.border : EmpyColors.border, lineWidth: 1)
            )
    }
    
    /// Apply frosted glass header effect
    func empyFrostedHeader() -> some View {
        self
            .background(.ultraThinMaterial)
            .shadow(color: EmpyShadow.sm, radius: EmpyShadow.smRadius, x: EmpyShadow.smX, y: EmpyShadow.smY)
    }
}

// MARK: - Preview Helpers

#if DEBUG
struct EmpyDesignSystem_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: EmpySpacing.xl) {
            // Color palette
            HStack(spacing: EmpySpacing.md) {
                Circle().fill(EmpyColors.happy).frame(width: 40, height: 40)
                Circle().fill(EmpyColors.surprised).frame(width: 40, height: 40)
                Circle().fill(EmpyColors.sad).frame(width: 40, height: 40)
                Circle().fill(EmpyColors.nervous).frame(width: 40, height: 40)
                Circle().fill(EmpyColors.neutral).frame(width: 40, height: 40)
                Circle().fill(EmpyColors.angry).frame(width: 40, height: 40)
            }
            
            // Typography
            VStack(alignment: .leading, spacing: EmpySpacing.sm) {
                Text("Heading 1").font(EmpyFonts.h1())
                Text("Heading 2").font(EmpyFonts.h2())
                Text("Body text").font(EmpyFonts.body())
                Text("Label text").font(EmpyFonts.label())
                Text("Caption text").font(EmpyFonts.caption())
            }
            
            // Card example
            VStack(spacing: EmpySpacing.md) {
                Text("Example Card")
                    .font(EmpyFonts.bodyMedium())
                Text("This is a card with Empy styling")
                    .font(EmpyFonts.caption())
                    .foregroundColor(EmpyColors.foreground.opacity(0.7))
            }
            .padding(EmpySpacing.lg)
            .empyCard()
            
            // Buttons
            HStack(spacing: EmpySpacing.md) {
                Text("Primary").empyPrimaryButton()
                Text("Secondary").empySecondaryButton()
            }
        }
        .padding(EmpySpacing.xl)
        .empyGradientBackground(colorScheme: .light)
    }
}
#endif
