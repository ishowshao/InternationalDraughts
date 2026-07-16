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

    private func makeApp(language: String = "zh-Hans", arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let locale: String
        switch language {
        case "zh-Hans": locale = "zh_CN"
        case "zh-Hant": locale = "zh_TW"
        case "fr": locale = "fr_FR"
        default: locale = "en_US"
        }
        app.launchArguments = arguments + [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
        ]
        return app
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

    // MARK: - Nearby match (MultipeerConnectivity, two simulators)
    // Run testNearbyMatchHost on one simulator and testNearbyMatchJoin on
    // another at the same time; they connect and play one move each.

    private func waitLabel(_ element: XCUIElement, _ text: String, timeout: TimeInterval,
                           contains: Bool = false) {
        let format = contains ? "label CONTAINS %@" : "label == %@"
        let predicate = NSPredicate(format: format, text)
        wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout)
    }

    /// Host (White): creates the room, plays (6,3)->(5,4), waits for Black's reply.
    func testNearbyMatchHost() throws {
        let app = makeApp(arguments: ["-mpAutoHost"])
        app.launch()

        let board = app.otherElements["board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        let peerStatus = app.staticTexts["peerStatus"]
        waitLabel(peerStatus, "已连接", timeout: 120, contains: true)
        waitLabel(peerStatus, "你执白", timeout: 10, contains: true)
        attach(app, "host-connected")

        let status = app.staticTexts["status"]
        waitLabel(status, "你的回合（白方）", timeout: 10)
        tapCell(board, 6, 3)
        tapCell(board, 5, 4)

        // Wait on the board's machine-readable state instead of the transient
        // "等待对方走子…" label — Black's reply can arrive within a second.
        let blackReplied = NSPredicate(format: "value CONTAINS %@", "last:34-45")
        wait(for: [expectation(for: blackReplied, evaluatedWith: board)], timeout: 90)
        waitLabel(status, "你的回合（白方）", timeout: 10)
        XCTAssertEqual(app.staticTexts["whiteCount"].label, "20")
        XCTAssertEqual(app.staticTexts["blackCount"].label, "20")
        attach(app, "host-after-black-move")

        // Keep the session alive briefly so the joiner finishes its asserts.
        Thread.sleep(forTimeInterval: 5)
    }

    /// Joiner (Black, flipped board): auto-joins, answers White's move.
    func testNearbyMatchJoin() throws {
        let app = makeApp(arguments: ["-mpAutoJoin"])
        app.launch()

        let board = app.otherElements["board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        let peerStatus = app.staticTexts["peerStatus"]
        waitLabel(peerStatus, "已连接", timeout: 120, contains: true)
        waitLabel(peerStatus, "你执黑", timeout: 10, contains: true)
        attach(app, "join-connected")

        // Wait for White's opening move, then reply. Board is flipped for
        // Black, so model (3,4)->(4,5) is display (6,5)->(5,4).
        let status = app.staticTexts["status"]
        waitLabel(status, "你的回合（黑方）", timeout: 90)
        attach(app, "join-white-moved")
        tapCell(board, 6, 5)
        tapCell(board, 5, 4)
        waitLabel(status, "等待对方走子…", timeout: 10)
        XCTAssertEqual(app.staticTexts["whiteCount"].label, "20")
        XCTAssertEqual(app.staticTexts["blackCount"].label, "20")
        attach(app, "join-after-reply")

        // Give the reliable send time to flush before the app dies.
        Thread.sleep(forTimeInterval: 5)
    }

    /// Landscape layout check (board left, panel right) — intended for iPad.
    func testLandscapeLayoutPlaysMove() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApp()
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
        let app = makeApp()
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

    func testEnglishLocalization() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = makeApp(language: "en")
        app.launch()

        XCTAssertTrue(app.staticTexts["International Draughts"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["status"].label, "Your turn (White)")
        XCTAssertTrue(app.buttons["New Game"].exists)
        XCTAssertTrue(app.buttons["Create Room"].exists)
        XCTAssertTrue(app.buttons["Find Room"].exists)
    }

    func testTraditionalChineseLocalization() throws {
        let app = makeApp(language: "zh-Hant")
        app.launch()

        XCTAssertTrue(app.staticTexts["國際跳棋"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["status"].label, "你的回合（白方）")
        XCTAssertTrue(app.buttons["新遊戲"].exists)
    }

    func testUnsupportedLanguageFallsBackToEnglish() throws {
        let app = makeApp(language: "fr")
        app.launch()

        XCTAssertTrue(app.staticTexts["International Draughts"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["status"].label, "Your turn (White)")
    }

    func testEnglishStoreScreenshots() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = makeApp(language: "en")
        app.launch()

        let board = app.otherElements["board"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        let status = app.staticTexts["status"]
        XCTAssertEqual(status.label, "Your turn (White)")
        Thread.sleep(forTimeInterval: 0.5)
        attach(app, "01-home")

        tapCell(board, 6, 3)
        Thread.sleep(forTimeInterval: 3)
        attach(app, "02-selected-move")

        app.buttons["Hard"].tap()
        Thread.sleep(forTimeInterval: 3)
        attach(app, "03-hard-difficulty")

        app.buttons["newGame"].tap()
        XCTAssertEqual(status.label, "Your turn (White)")
        Thread.sleep(forTimeInterval: 0.5)
        attach(app, "04-new-game")
    }
}
