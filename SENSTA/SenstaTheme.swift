import SwiftUI
import UIKit

enum SenstaTheme {
  static let backgroundUIColor = dynamic(light: 0xF8F3EB, dark: 0x1C1612)
  static let surfaceUIColor = dynamic(light: 0xFDFBF6, dark: 0x261F1A)
  static let surfaceLowUIColor = dynamic(light: 0xFBF7F1, dark: 0x221B17)
  static let containerUIColor = dynamic(light: 0xF2ECE3, dark: 0x2D241F)
  static let containerHighUIColor = dynamic(light: 0xEDE5D9, dark: 0x322924)
  static let containerHighestUIColor = dynamic(light: 0xE5DDD3, dark: 0x403630)
  static let foregroundUIColor = dynamic(light: 0x2A211B, dark: 0xEBE5DE)
  static let secondaryUIColor = dynamic(light: 0x73645A, dark: 0xA2988E)
  static let outlineUIColor = dynamic(light: 0x9A8C80, dark: 0x887A70)
  static let outlineVariantUIColor = dynamic(light: 0xDAD1C6, dark: 0x453B34)
  static let primaryUIColor = dynamic(light: 0xB2583A, dark: 0xDB8F6C)
  static let onPrimaryUIColor = dynamic(light: 0xFFF8F2, dark: 0x30170F)
  static let primaryContainerUIColor = dynamic(light: 0xEFDECD, dark: 0x5B3022)
  static let onPrimaryContainerUIColor = dynamic(light: 0x3F1E14, dark: 0xFFDBCA)
  static let errorUIColor = dynamic(light: 0xB3261E, dark: 0xFFB4AB)

  static let background = Color(uiColor: backgroundUIColor)
  static let surface = Color(uiColor: surfaceUIColor)
  static let surfaceLow = Color(uiColor: surfaceLowUIColor)
  static let container = Color(uiColor: containerUIColor)
  static let containerHigh = Color(uiColor: containerHighUIColor)
  static let containerHighest = Color(uiColor: containerHighestUIColor)
  static let foreground = Color(uiColor: foregroundUIColor)
  static let secondary = Color(uiColor: secondaryUIColor)
  static let outline = Color(uiColor: outlineUIColor)
  static let outlineVariant = Color(uiColor: outlineVariantUIColor)
  static let primary = Color(uiColor: primaryUIColor)
  static let onPrimary = Color(uiColor: onPrimaryUIColor)
  static let primaryContainer = Color(uiColor: primaryContainerUIColor)
  static let onPrimaryContainer = Color(uiColor: onPrimaryContainerUIColor)
  static let error = Color(uiColor: errorUIColor)

  private static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
    UIColor { traits in color(traits.userInterfaceStyle == .dark ? dark : light) }
  }

  private static func color(_ rgb: UInt32) -> UIColor {
    UIColor(
      red: CGFloat((rgb >> 16) & 0xFF) / 255,
      green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255,
      alpha: 1)
  }
}

private struct SenstaScreenStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .scrollContentBackground(.hidden)
      .background(SenstaTheme.background.ignoresSafeArea())
      .foregroundStyle(SenstaTheme.foreground)
      .tint(SenstaTheme.primary)
      .toolbarBackground(SenstaTheme.background, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
  }
}

extension View {
  func senstaScreenStyle() -> some View {
    modifier(SenstaScreenStyle())
  }
}
