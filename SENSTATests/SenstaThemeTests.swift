import Testing
import UIKit

@testable import SENSTA

struct SenstaThemeTests {
  @Test func sharedWarmPaletteResolvesForLightAndDarkMode() {
    #expect(hex(SenstaTheme.backgroundUIColor, style: .light) == 0xF8F3EB)
    #expect(hex(SenstaTheme.backgroundUIColor, style: .dark) == 0x1C1612)
    #expect(hex(SenstaTheme.surfaceUIColor, style: .light) == 0xFDFBF6)
    #expect(hex(SenstaTheme.surfaceUIColor, style: .dark) == 0x261F1A)
    #expect(hex(SenstaTheme.primaryUIColor, style: .light) == 0xB2583A)
    #expect(hex(SenstaTheme.primaryUIColor, style: .dark) == 0xDB8F6C)
    #expect(hex(SenstaTheme.containerUIColor, style: .light) == 0xF2ECE3)
    #expect(hex(SenstaTheme.containerUIColor, style: .dark) == 0x2D241F)
  }

  private func hex(_ color: UIColor, style: UIUserInterfaceStyle) -> UInt32 {
    let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return UInt32((red * 255).rounded()) << 16
      | UInt32((green * 255).rounded()) << 8
      | UInt32((blue * 255).rounded())
  }
}
