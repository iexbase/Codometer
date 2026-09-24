import CodometerCore
import CoreGraphics
import Foundation
import Testing

@Suite("Notch geometry")
struct NotchGeometryTests {
    @Test("14-inch MacBook Pro: 197 pt notch between 657.5 pt auxiliary areas, 32 pt menu bar")
    func fourteenInch() throws {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let notch = try #require(NotchGeometry.make(
            screen: screen,
            safeTop: 32,
            auxLeft: CGRect(x: 0, y: 950, width: 657.5, height: 32),
            auxRight: CGRect(x: 854.5, y: 950, width: 657.5, height: 32)
        ))
        #expect(notch.rect == CGRect(x: 657.5, y: 950, width: 197, height: 32))
        #expect(notch.menuBarHeight == 32)
        #expect(notch.leftAuxiliaryWidth == 657.5)
        #expect(notch.rightAuxiliaryWidth == 657.5)
    }

    @Test("16-inch MacBook Pro on a secondary origin: 38 pt menu bar")
    func sixteenInch() throws {
        let screen = CGRect(x: 1920, y: -120, width: 1728, height: 1117)
        let notch = try #require(NotchGeometry.make(
            screen: screen,
            safeTop: 38,
            auxLeft: CGRect(x: 1920, y: 959, width: 765.5, height: 38),
            auxRight: CGRect(x: 2882.5, y: 959, width: 765.5, height: 38)
        ))
        #expect(notch.rect == CGRect(x: 2685.5, y: 959, width: 197, height: 38))
    }

    @Test("Scaled \"More Space\" resolution keeps the notch proportional")
    func scaled() throws {
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let notch = try #require(NotchGeometry.make(
            screen: screen,
            safeTop: 38,
            auxLeft: CGRect(x: 0, y: 1131, width: 782, height: 38),
            auxRight: CGRect(x: 1018, y: 1131, width: 782, height: 38)
        ))
        #expect(notch.rect.width == 236)
        #expect(notch.rect.minY == 1131)
    }

    @Test("No notch: missing, inconsistent, too narrow, too wide or nonsensical values")
    func rejected() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let left = CGRect(x: 0, y: 950, width: 657.5, height: 32)
        let right = CGRect(x: 854.5, y: 950, width: 657.5, height: 32)
        #expect(NotchGeometry.make(screen: screen, safeTop: 32, auxLeft: nil, auxRight: right) == nil)
        #expect(NotchGeometry.make(screen: screen, safeTop: 32, auxLeft: left, auxRight: nil) == nil)
        #expect(NotchGeometry.make(screen: screen, safeTop: 32, auxLeft: right, auxRight: left) == nil)
        #expect(NotchGeometry.make(screen: screen, safeTop: 32, auxLeft: CGRect(x: 0, y: 950, width: 730, height: 32), auxRight: CGRect(x: 780, y: 950, width: 732, height: 32)) == nil)
        #expect(NotchGeometry.make(screen: screen, safeTop: 32, auxLeft: CGRect(x: 0, y: 950, width: 300, height: 32), auxRight: CGRect(x: 1000, y: 950, width: 512, height: 32)) == nil)
        #expect(NotchGeometry.make(screen: screen, safeTop: 0, auxLeft: left, auxRight: right) == nil)
        #expect(NotchGeometry.make(screen: screen, safeTop: 1000, auxLeft: left, auxRight: right) == nil)
        #expect(NotchGeometry.make(screen: screen, safeTop: .nan, auxLeft: left, auxRight: right) == nil)
        #expect(NotchGeometry.make(screen: screen, safeTop: 32, auxLeft: .null, auxRight: right) == nil)
    }
}
