//
//  InternationalDraughtsUITests.swift
//  InternationalDraughtsUITests
//
//  Created by cyberoldman on 2026/7/4.
//

import XCTest

final class InternationalDraughtsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Taps the center of board cell (row, col), accounting for the 10pt frame.
    private func tapCell(_ board: XCUIElement, _ r: Int, _ c: Int) {
        let border: CGFloat = 10
        let w = board.frame.width
        let h = board.frame.height
        let cell = (w - 2 * border) / 10
        let dx = (border + (CGFloat(c) + 0.5) * cell) / w
        let dy = (border + (CGFloat(r) + 0.5) * cell) / h
        board.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Landscape layout check (board left, panel right) — intended for iPad.
    func testLandscapeLayoutPlaysMove() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launch()

        let board = app.otherElements["board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        attach(app, "landscape-initial")

        // The panel sits to the right of the board in landscape.
        let status = app.staticTexts["status"]
        XCTAssertGreaterThan(status.frame.minX, board.frame.maxX)

        tapCell(board, 6, 3)
        attach(app, "landscape-selected")
        tapCell(board, 5, 4)
        let myTurn = NSPredicate(format: "label == %@", "你的回合（白方）")
        wait(for: [expectation(for: myTurn, evaluatedWith: status)], timeout: 10)
        attach(app, "landscape-after-ai-reply")
    }

    func testPlayMoveAndAIReplies() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()

        let board = app.otherElements["board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))

        let status = app.staticTexts["status"]
        XCTAssertEqual(status.label, "你的回合（白方）")
        XCTAssertEqual(app.staticTexts["whiteCount"].label, "20")
        XCTAssertEqual(app.staticTexts["blackCount"].label, "20")
        attach(app, "initial")

        // Pick up the white man at (6,3) and check the selection renders.
        tapCell(board, 6, 3)
        attach(app, "selected")

        // Move it forward to (5,4). Black (AI) should reply within a few seconds.
        tapCell(board, 5, 4)
        let myTurn = NSPredicate(format: "label == %@", "你的回合（白方）")
        let backToPlayer = expectation(for: myTurn, evaluatedWith: status)
        wait(for: [backToPlayer], timeout: 10)
        attach(app, "after-ai-reply")

        // Opening simple moves capture nothing.
        XCTAssertEqual(app.staticTexts["whiteCount"].label, "20")
        XCTAssertEqual(app.staticTexts["blackCount"].label, "20")

        // New game resets the board and gives the turn back to the player.
        app.buttons["newGame"].tap()
        XCTAssertEqual(status.label, "你的回合（白方）")
        attach(app, "new-game")
    }
}
