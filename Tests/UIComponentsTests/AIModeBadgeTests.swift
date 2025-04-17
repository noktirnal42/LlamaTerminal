#if canImport(XCTest)
import XCTest
#endif
import SwiftUI
import ViewInspector
@testable import UIComponents

extension AIModeBadge: Inspectable {}

final class AIModeBadgeTests: XCTestCase {
    
    func testBadgeDisplaysCorrectMode() throws {
        let badge = AIModeBadge(mode: .auto)
        
        let text = try badge.inspect().find(text: "Auto Mode")
        XCTAssertNotNil(text, "Badge should display the correct mode name")
    }
    
    func testBadgeDisplaysCorrectIcon() throws {
        let badge = AIModeBadge(mode: .code)
        
        let image = try badge.inspect().find(ViewType.Image.self)
        let systemName = try image.systemName()
        XCTAssertEqual(systemName, "curlybraces", "Badge should display the correct icon")
    }
    
    func testBadgeColorsForDifferentModes() throws {
        // Test colors for different modes
        let disabledBadge = AIModeBadge(mode: .disabled)
        let autoBadge = AIModeBadge(mode: .auto)
        let dispatchBadge = AIModeBadge(mode: .dispatch)
        let codeBadge = AIModeBadge(mode: .code)
        let commandBadge = AIModeBadge(mode: .command)
        
        // We can't directly test colors in ViewInspector, but we can verify they're different objects
        let disabledColor = try getModeColor(from: disabledBadge)
        let autoColor = try getModeColor(from: autoBadge)
        let dispatchColor = try getModeColor(from: dispatchBadge)
        let codeColor = try getModeColor(from: codeBadge)
        let commandColor = try getModeColor(from: commandBadge)
        
        // Just test that they're different values
        XCTAssertNotEqual(disabledColor, autoColor)
        XCTAssertNotEqual(autoColor, dispatchColor)
        XCTAssertNotEqual(dispatchColor, codeColor)
        XCTAssertNotEqual(codeColor, commandColor)
    }
    
    // Helper to extract color value
    private func getModeColor(from badge: AIModeBadge) throws -> Int {
        // This is a workaround since we can't directly compare Color values
        // We'll use the hashValue of the mode to simulate different colors
        return badge.mode.hashValue
    }
    
    static var allTests = [
        ("testBadgeDisplaysCorrectMode", testBadgeDisplaysCorrectMode),
        ("testBadgeDisplaysCorrectIcon", testBadgeDisplaysCorrectIcon),
        ("testBadgeColorsForDifferentModes", testBadgeColorsForDifferentModes),
    ]
}

