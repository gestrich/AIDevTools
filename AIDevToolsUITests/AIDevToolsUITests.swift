//
//  AIDevToolsUITests.swift
//  AIDevToolsUITests
//
//  Created by Bill Gestrich on 4/1/26.
//

import XCTest

final class AIDevToolsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15), "Main window should appear")
        sleep(3)
        return app
    }

    @MainActor
    private func saveScreenshot(_ app: XCUIApplication, name: String) {
        // Capture just the app window, not the full screen
        let screenshot = app.windows.firstMatch.screenshot()
        let data = screenshot.pngRepresentation

        // Save as XCTest attachment (embedded in .xcresult bundle)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("SCREENSHOT_ATTACHED: \(name) (\(data.count) bytes)")
    }

    @MainActor
    private func selectFirstRepository(_ app: XCUIApplication) {
        let sidebar = app.outlines.firstMatch
        if sidebar.waitForExistence(timeout: 5) {
            let firstCell = sidebar.cells.firstMatch
            if firstCell.waitForExistence(timeout: 3) {
                firstCell.tap()
                sleep(2)
            }
        }
    }

    @MainActor
    private func findTab(_ app: XCUIApplication, label: String) -> XCUIElement? {
        let button = app.buttons[label]
        if button.waitForExistence(timeout: 2) { return button }

        let radio = app.radioButtons[label]
        if radio.waitForExistence(timeout: 1) { return radio }

        let tabGroup = app.tabGroups.firstMatch
        if tabGroup.exists {
            let text = tabGroup.staticTexts[label]
            if text.exists { return text }
            let btn = tabGroup.buttons[label]
            if btn.exists { return btn }
        }

        let predicate = NSPredicate(format: "label == %@ OR title == %@", label, label)
        let match = app.descendants(matching: .any).matching(predicate).firstMatch
        if match.waitForExistence(timeout: 1) { return match }

        return nil
    }

    @MainActor
    private func tapTab(_ app: XCUIApplication, label: String) {
        if let tab = findTab(app, label: label) {
            tab.tap()
            sleep(2)
        }
    }

    // MARK: - Screenshot Tests

    @MainActor
    func testScreenshot01_EmptyState() throws {
        let app = launchApp()
        saveScreenshot(app, name: "01-empty-state")
    }

    @MainActor
    func testScreenshot02_RepositorySidebar() throws {
        let app = launchApp()
        selectFirstRepository(app)
        saveScreenshot(app, name: "02-repository-sidebar")
    }

    @MainActor
    func testScreenshot03_ChainsTab() throws {
        let app = launchApp()
        selectFirstRepository(app)
        tapTab(app, label: "Chains")
        saveScreenshot(app, name: "03-chains-tab")
    }

    @MainActor
    func testScreenshot04_ArchitectureTab() throws {
        let app = launchApp()
        selectFirstRepository(app)
        tapTab(app, label: "Architecture")
        saveScreenshot(app, name: "04-architecture-tab")
    }

    @MainActor
    func testScreenshot05_EvalsTab() throws {
        let app = launchApp()
        selectFirstRepository(app)
        tapTab(app, label: "Evals")
        saveScreenshot(app, name: "05-evals-tab")
    }

    @MainActor
    func testScreenshot06_PlansTab() throws {
        let app = launchApp()
        selectFirstRepository(app)
        tapTab(app, label: "Plans")
        saveScreenshot(app, name: "06-plans-tab")
    }

    @MainActor
    func testScreenshot07_PRRadarTab() throws {
        let app = launchApp()
        selectFirstRepository(app)
        tapTab(app, label: "PR Radar")
        saveScreenshot(app, name: "07-pr-radar-tab")
    }

    @MainActor
    func testScreenshot08_SkillsTab() throws {
        let app = launchApp()
        selectFirstRepository(app)
        tapTab(app, label: "Skills")
        saveScreenshot(app, name: "08-skills-tab")
    }

    @MainActor
    func testScreenshot09_Settings() throws {
        let app = launchApp()
        app.typeKey(",", modifierFlags: .command)
        sleep(2)
        saveScreenshot(app, name: "09-settings")
    }

    @MainActor
    func testScreenshot10_ChatPanelClosed() throws {
        let app = launchApp()
        selectFirstRepository(app)
        // Ensure the chat panel is closed. If the panel is already open (persisted
        // state from a prior run), click the toggle button once to close it.
        let toggleButton = app.buttons["Toggle Chat"]
        if toggleButton.waitForExistence(timeout: 5) {
            // Detect panel open state by looking for the panel's "Chat" header
            let chatHeader = app.staticTexts["Chat"]
            if chatHeader.exists {
                toggleButton.tap()
                sleep(2)
            }
        }
        saveScreenshot(app, name: "chat-panel-closed")
    }

    @MainActor
    func testScreenshot11_ChatPanelOpen() throws {
        let app = launchApp()
        selectFirstRepository(app)
        // Open the inspector panel by clicking the "Toggle Chat" toolbar button.
        // If the panel is already open, close it first then reopen to ensure
        // we capture a clean open state.
        let toggleButton = app.buttons["Toggle Chat"]
        if toggleButton.waitForExistence(timeout: 5) {
            let chatHeader = app.staticTexts["Chat"]
            if chatHeader.exists {
                // Already open — close then reopen for a clean capture
                toggleButton.tap()
                sleep(1)
            }
            toggleButton.tap()
            sleep(2)
        }
        saveScreenshot(app, name: "chat-panel-open")
    }
}
