import Testing
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
