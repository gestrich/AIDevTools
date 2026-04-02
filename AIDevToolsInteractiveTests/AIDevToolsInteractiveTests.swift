//
//  AIDevToolsInteractiveTests.swift
//  AIDevToolsInteractiveTests
//
//  Created by Bill Gestrich on 4/1/26.
//

import XCTest
import XCUITestControl

final class InteractiveControlTests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testInteractiveControl() throws {
        let app = XCUIApplication()
        app.launch()
        InteractiveControlLoop().run(app: app)
    }
}