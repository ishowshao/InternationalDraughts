import Testing
import UIKit
@testable import InternationalDraughts

struct InternationalDraughtsTests {
    @Test func aiPlaysEitherColor() throws {
        let board = Engine.initialBoard()
        for color in [PieceColor.white, .black] {
            for difficulty in Difficulty.allCases {
                let move = try #require(Engine.chooseAIMove(board: board, difficulty: difficulty, color: color))
                #expect(board[move.from]?.color == color)
                #expect(Engine.legalMoves(board: board, color: color).contains { $0.path == move.path })
            }
        }
    }

    @Test func aiAvoidsLosingItsLastPieceForEitherColor() throws {
        for color in [PieceColor.black, .white] {
            var board: Board = Array(repeating: nil, count: 100)
            let origin = color == .black ? 32 : 67
            let opponent = color == .black ? 54 : 45
            let safeDestination = color == .black ? 41 : 58
            board[origin] = Piece(color: color, king: false)
            board[opponent] = Piece(color: color.opponent, king: false)
            let move = try #require(Engine.chooseAIMove(board: board, difficulty: .easy, color: color))
            #expect(move.to == safeDestination)
        }
    }

    @Test func aiReturnsNilWithoutLegalMoves() {
        let board: Board = Array(repeating: nil, count: 100)
        for color in [PieceColor.white, .black] {
            #expect(Engine.chooseAIMove(board: board, difficulty: .easy, color: color) == nil)
        }
    }
}

@MainActor
struct GameScreenLayoutTests {
    @Test func resizingKeepsBoardSquareAndControlsWithinSafeArea() {
        for size in [CGSize(width: 320, height: 600), CGSize(width: 400, height: 740),
                     CGSize(width: 740, height: 400), CGSize(width: 570, height: 430), CGSize(width: 700, height: 900),
                     CGSize(width: 900, height: 700), CGSize(width: 1024, height: 1300)] {
            let safe = CGRect(origin: CGPoint(x: 48, y: 24), size: size)
            let layout = GameScreenLayout(safeArea: safe)
            #expect(layout.board.width == layout.board.height)
            #expect(layout.board.width > 0)
            #expect(safe.contains(layout.board))
            #expect(safe.contains(layout.panel))
            #expect(!layout.board.intersects(layout.panel))
            #expect(layout.panel.height >= 100)
            #expect(layout.panel.width >= 240)
        }
    }

    @Test func wideCoverDisplayUsesSidePanel() {
        let layout = GameScreenLayout(safeArea: CGRect(x: 0, y: 0, width: 570, height: 430))
        #expect(layout.panel.minX > layout.board.maxX)
        #expect(layout.board.width > 260)
    }

    @Test func foldedBoardAndControlsAvoidHinge() {
        let safe = CGRect(x: 40, y: 20, width: 800, height: 700)
        for fold in [CGRect(x: 420, y: 0, width: 32, height: 800),
                     CGRect(x: 0, y: 350, width: 900, height: 32)] {
            let layout = GameScreenLayout(safeArea: safe, divisions: [fold])
            #expect(safe.contains(layout.board))
            #expect(safe.contains(layout.panel))
            #expect(!layout.board.intersects(fold))
            #expect(!layout.panel.intersects(fold))
            #expect(layout.board.width == layout.board.height)
        }
    }
}
