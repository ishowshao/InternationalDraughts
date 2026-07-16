//
//  Engine.swift
//  InternationalDraughts
//
//  International Draughts (10x10) rules engine and AI.
//  Ported from the web version (src/game/engine.ts).
//

import Foundation

enum PieceColor {
    case white
    case black

    var opponent: PieceColor { self == .white ? .black : .white }
}

struct Piece: Equatable {
    var color: PieceColor
    var king: Bool
}

/// Board is a flat array of 100 cells (10x10). nil = empty / non-playable.
typealias Board = [Piece?]

/// A single move (simple step or full capture sequence).
/// `path` lists the squares the moving piece visits, starting with `from`.
/// For a simple move it is `[from, to]`; for a capture of N pieces it has
/// N + 1 entries (one landing per jump).
struct Move {
    var from: Int
    var to: Int
    var captures: [Int]
    var path: [Int]
}

enum GameStatus {
    case playing
    case whiteWin
    case blackWin
    case draw
}

enum Difficulty: Int, CaseIterable {
    case easy
    case medium
    case hard

    var searchDepth: Int {
        switch self {
        case .easy: return 2
        case .medium: return 4
        case .hard: return 6
        }
    }

    var label: String {
        switch self {
        case .easy: return String(localized: "Easy")
        case .medium: return String(localized: "Medium")
        case .hard: return String(localized: "Hard")
        }
    }
}

enum Engine {

    static let size = 10

    private static let dirs: [(dr: Int, dc: Int)] = [(-1, -1), (-1, 1), (1, -1), (1, 1)]

    // MARK: - Coordinate helpers

    static func rowOf(_ i: Int) -> Int { i / size }
    static func colOf(_ i: Int) -> Int { i % size }
    private static func idx(_ r: Int, _ c: Int) -> Int { r * size + c }
    private static func inBounds(_ r: Int, _ c: Int) -> Bool {
        r >= 0 && r < size && c >= 0 && c < size
    }

    /// A playable square is a dark square: (row + col) is odd.
    static func isPlayable(_ i: Int) -> Bool { (rowOf(i) + colOf(i)) % 2 == 1 }

    // MARK: - Board setup

    /// Black occupies the top four rows, White the bottom four. 20 pieces each.
    static func initialBoard() -> Board {
        var board = Board(repeating: nil, count: size * size)
        for i in board.indices where isPlayable(i) {
            let r = rowOf(i)
            if r <= 3 {
                board[i] = Piece(color: .black, king: false)
            } else if r >= 6 {
                board[i] = Piece(color: .white, king: false)
            }
        }
        return board
    }

    // MARK: - Move generation

    /// All capture sequences available to the piece at `from` (may be empty).
    private static func captureSequences(board: Board, from: Int) -> [Move] {
        guard let piece = board[from] else { return [] }

        var results: [Move] = []
        // The moving piece "leaves" its origin, so that square is free for the
        // rest of the sequence (relevant for flying kings that loop back over it).
        var board = board
        board[from] = nil

        func search(_ cur: Int, _ captured: [Int], _ path: [Int]) {
            let r = rowOf(cur)
            let c = colOf(cur)
            var extended = false

            for (dr, dc) in dirs {
                if piece.king {
                    // Slide to the first occupied square in this direction.
                    var tr = r + dr
                    var tc = c + dc
                    while inBounds(tr, tc) && board[idx(tr, tc)] == nil {
                        tr += dr
                        tc += dc
                    }
                    guard inBounds(tr, tc) else { continue }
                    let target = idx(tr, tc)
                    // Must be an enemy piece not already captured this sequence.
                    guard let tp = board[target], tp.color != piece.color,
                          !captured.contains(target) else { continue }
                    // Any empty square beyond the captured piece is a valid landing.
                    var lr = tr + dr
                    var lc = tc + dc
                    while inBounds(lr, lc) && board[idx(lr, lc)] == nil {
                        extended = true
                        let landing = idx(lr, lc)
                        search(landing, captured + [target], path + [landing])
                        lr += dr
                        lc += dc
                    }
                } else {
                    // Men capture in all four diagonal directions (forward and backward).
                    let lr = r + 2 * dr
                    let lc = c + 2 * dc
                    guard inBounds(lr, lc) else { continue }
                    let mid = idx(r + dr, c + dc)
                    let landing = idx(lr, lc)
                    guard let mp = board[mid], mp.color != piece.color,
                          !captured.contains(mid) else { continue }
                    guard board[landing] == nil else { continue }
                    extended = true
                    search(landing, captured + [mid], path + [landing])
                }
            }

            // A dead end with at least one capture is a complete (maximal) sequence.
            if !extended && !captured.isEmpty {
                results.append(Move(from: from, to: cur, captures: captured, path: path))
            }
        }

        search(from, [], [from])
        return results
    }

    /// Non-capturing moves for the piece at `from`.
    private static func simpleMoves(board: Board, from: Int) -> [Move] {
        guard let piece = board[from] else { return [] }
        let r = rowOf(from)
        let c = colOf(from)
        var moves: [Move] = []

        if piece.king {
            for (dr, dc) in dirs {
                var tr = r + dr
                var tc = c + dc
                while inBounds(tr, tc) && board[idx(tr, tc)] == nil {
                    let to = idx(tr, tc)
                    moves.append(Move(from: from, to: to, captures: [], path: [from, to]))
                    tr += dr
                    tc += dc
                }
            }
        } else {
            let forward = piece.color == .white ? -1 : 1
            for dc in [-1, 1] {
                let tr = r + forward
                let tc = c + dc
                if inBounds(tr, tc) && board[idx(tr, tc)] == nil {
                    let to = idx(tr, tc)
                    moves.append(Move(from: from, to: to, captures: [], path: [from, to]))
                }
            }
        }
        return moves
    }

    /// All legal moves for `color`. Captures are mandatory, and when captures are
    /// available only those capturing the maximum number of pieces are legal.
    static func legalMoves(board: Board, color: PieceColor) -> [Move] {
        var captures: [Move] = []
        for i in board.indices where board[i]?.color == color {
            captures.append(contentsOf: captureSequences(board: board, from: i))
        }

        if !captures.isEmpty {
            let max = captures.map { $0.captures.count }.max() ?? 0
            return captures.filter { $0.captures.count == max }
        }

        var moves: [Move] = []
        for i in board.indices where board[i]?.color == color {
            moves.append(contentsOf: simpleMoves(board: board, from: i))
        }
        return moves
    }

    /// Apply a move, returning a new board (promotion handled at the landing).
    static func applyMove(board: Board, move: Move) -> Board {
        var next = board
        guard let piece = next[move.from] else { return next }
        next[move.from] = nil
        for c in move.captures { next[c] = nil }

        var placed = piece
        let r = rowOf(move.to)
        if !piece.king && ((piece.color == .white && r == 0) || (piece.color == .black && r == size - 1)) {
            placed = Piece(color: piece.color, king: true)
        }
        next[move.to] = placed
        return next
    }

    static func countPieces(board: Board, color: PieceColor) -> Int {
        board.reduce(0) { $0 + ($1?.color == color ? 1 : 0) }
    }

    // MARK: - AI: minimax with alpha-beta pruning

    private static let manValue = 100.0
    private static let kingValue = 280.0
    private static let winScore = 1_000_000.0

    /// Static evaluation. Positive favors Black (the AI).
    private static func evaluate(board: Board) -> Double {
        var score = 0.0
        for i in board.indices {
            guard let p = board[i] else { continue }
            var value = p.king ? kingValue : manValue
            if !p.king {
                // Reward advancement toward promotion and central control.
                let advance = p.color == .black ? rowOf(i) : size - 1 - rowOf(i)
                value += Double(advance) * 5
                let c = Double(colOf(i))
                value += 4 - abs(c - 4.5) + 0.5 // mild center bonus
            }
            score += p.color == .black ? value : -value
        }
        return score
    }

    private static func minimax(
        board: Board, depth: Int, alpha: Double, beta: Double, color: PieceColor
    ) -> Double {
        let moves = legalMoves(board: board, color: color)
        if moves.isEmpty {
            // The side to move has no moves and loses.
            return color == .black ? -winScore - Double(depth) : winScore + Double(depth)
        }
        if depth == 0 { return evaluate(board: board) }

        var alpha = alpha
        var beta = beta
        if color == .black {
            var best = -Double.infinity
            for m in moves {
                let v = minimax(board: applyMove(board: board, move: m),
                                depth: depth - 1, alpha: alpha, beta: beta, color: .white)
                if v > best { best = v }
                if v > alpha { alpha = v }
                if beta <= alpha { break }
            }
            return best
        } else {
            var best = Double.infinity
            for m in moves {
                let v = minimax(board: applyMove(board: board, move: m),
                                depth: depth - 1, alpha: alpha, beta: beta, color: .black)
                if v < best { best = v }
                if v < beta { beta = v }
                if beta <= alpha { break }
            }
            return best
        }
    }

    /// Choose the AI's move (Black). Returns nil if no move is available.
    static func chooseAIMove(board: Board, difficulty: Difficulty) -> Move? {
        let moves = legalMoves(board: board, color: .black)
        if moves.isEmpty { return nil }
        if moves.count == 1 { return moves[0] }

        let depth = difficulty.searchDepth
        var best = -Double.infinity
        var bestMoves: [Move] = []
        for m in moves {
            let v = minimax(board: applyMove(board: board, move: m),
                            depth: depth - 1, alpha: -.infinity, beta: .infinity, color: .white)
            if v > best {
                best = v
                bestMoves = [m]
            } else if v == best {
                bestMoves.append(m)
            }
        }
        // Random tie-break keeps games from being identical.
        return bestMoves.randomElement()
    }
}
