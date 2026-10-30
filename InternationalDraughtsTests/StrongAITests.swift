import Testing
@testable import InternationalDraughts

@MainActor
struct StrongAITests {
    @Test func learnedEvaluationIsBundledAndColorSymmetric() throws {
        #expect(PatternEvaluation.isAvailable)
        let white: UInt64 = (1 << 31) | (1 << 36) | (1 << 42)
        let black: UInt64 = (1 << 3) | (1 << 11) | (1 << 18)
        func rotate(_ bits: UInt64) -> UInt64 {
            (0..<50).reduce(UInt64(0)) { result, s in
                result | (bits & (UInt64(1) << s) != 0 ? UInt64(1) << (49 - s) : 0)
            }
        }
        let value = try #require(PatternEvaluation.evaluate(white: white, black: black))
        #expect(value == 220) // Independently decoded and evaluated by the Python trainer.
        #expect(PatternEvaluation.evaluate(white: rotate(black), black: rotate(white)) == -value)
    }

    @Test func compulsoryRecaptureIsSearchedAtDepthOne() throws {
        for color in [PieceColor.white, .black] {
            var board: Board = Array(repeating: nil, count: 100)
            board[color == .black ? 32 : 67] = Piece(color: color, king: false)
            board[color == .black ? 54 : 45] = Piece(color: color.opponent, king: false)
            let result = StrongAI.chooseMove(board: board, color: color, maxDepth: 1, timeLimit: nil)
            #expect(try #require(result.move).to == (color == .black ? 41 : 58))
            #expect(result.completedDepth == 1)
        }
    }

    @Test func timeoutAndForcedPromotion() throws {
        let initial = Engine.initialBoard()
        let timeout = StrongAI.chooseMove(board: initial, color: .white, timeLimit: 0)
        #expect(timeout.completedDepth == 0)
        #expect(Engine.legalMoves(board: initial, color: .white).contains { $0.path == timeout.move?.path })
        var board: Board = Array(repeating: nil, count: 100)
        #expect(StrongAI.chooseMove(board: board, color: .white).move == nil)
        board[80] = Piece(color: .black, king: false)
        let move = try #require(StrongAI.chooseMove(board: board, color: .black).move)
        #expect(move.to == 91)
        #expect(Engine.applyMove(board: board, move: move)[91]?.king == true)
    }

    @Test func compactRulesMatchFullPathsAndPromotion() {
        // King-rich positions exercise flying capture landings, captured-piece
        // blockers, loops back through the vacated origin and majority capture.
        let fixtures: [[Int: Piece]] = [
            [54: Piece(color: .white, king: true), 43: Piece(color: .black, king: false),
             21: Piece(color: .black, king: true), 45: Piece(color: .black, king: false),
             67: Piece(color: .black, king: false), 65: Piece(color: .black, king: true)],
            [21: Piece(color: .white, king: false), 12: Piece(color: .black, king: false),
             14: Piece(color: .black, king: false), 36: Piece(color: .black, king: true)]
        ]
        for fixture in fixtures {
            var board: Board = Array(repeating: nil, count: 100)
            for (i, piece) in fixture { board[i] = piece }
            for color in [PieceColor.white, .black] {
                let compact = StrongAI.Position(board, color)
                let legal = Engine.legalMoves(board: board, color: color)
                let generated = compact.moves()
                #expect(generated.allSatisfy { m in legal.contains { StrongAI.CompactMove($0) == m } })
                for move in legal {
                    #expect(generated.contains(StrongAI.CompactMove(move)))
                    #expect(compact.applying(StrongAI.CompactMove(move)) == StrongAI.Position(Engine.applyMove(board: board, move: move), color.opponent))
                }
            }
        }
    }
}
