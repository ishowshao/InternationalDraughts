import Foundation

/// Local, per-search state: concurrent games/searches never share mutable caches.
enum AdvancedAI {
    struct Result {
        let move: Move?
        let completedDepth: Int
        let nodes: Int
    }

    static func chooseMove(board: Board, color: PieceColor,
                           maxDepth: Int = 12, timeLimit: Double? = 0.3) -> Result {
        Search(timeLimit: timeLimit).run(board: board, color: color, maxDepth: maxDepth)
    }

    // Three collision-free words encode 50 playable squares (3 bits per square).
    private struct Position: Hashable {
        var a: UInt64 = 0
        var b: UInt64 = 0
        var c: UInt64 = 0
        let blackToMove: Bool
        init(_ board: Board, _ color: PieceColor) {
            blackToMove = color == .black
            var square = 0
            for i in board.indices where Engine.isPlayable(i) {
                let piece = board[i]
                let code: UInt64 = piece.map { ($0.color == .white ? 1 : 3) + ($0.king ? 1 : 0) } ?? 0
                let bits = code << ((square % 21) * 3)
                switch square / 21 {
                case 0: a |= bits
                case 1: b |= bits
                default: c |= bits
                }
                square += 1
            }
        }
    }

    private enum Bound { case exact, lower, upper }
    private struct Entry {
        let depth: Int
        let score: Double
        let bound: Bound
        let move: Move?
    }
    private struct Timeout: Error {}

    private final class Search {
        private let deadline: UInt64?
        private var table: [Position: Entry] = [:]
        private var nodes = 0
        private let win = 1_000_000.0

        init(timeLimit: Double?) {
            deadline = timeLimit.map { DispatchTime.now().uptimeNanoseconds + UInt64(max(0, $0) * 1_000_000_000) }
        }

        func run(board: Board, color: PieceColor, maxDepth: Int) -> Result {
            let moves = Engine.legalMoves(board: board, color: color)
            guard let fallback = moves.first else {
                return Result(move: nil, completedDepth: 0, nodes: 0)
            }
            if moves.count == 1 { return Result(move: fallback, completedDepth: 0, nodes: 0) }
            var best = fallback
            var completed = 0
            for depth in 1...max(1, maxDepth) {
                do {
                    try checkTime()
                    var alpha = -Double.infinity
                    var iterationBest = best
                    for move in ordered(moves, board: board, preferred: best) {
                        try checkTime()
                        let score = try -negamax(Engine.applyMove(board: board, move: move),
                                                 color.opponent, depth - 1, -Double.infinity, -alpha)
                        if score > alpha { alpha = score; iterationBest = move }
                    }
                    best = iterationBest
                    completed = depth
                    if alpha >= win { break }
                } catch { break } // Only publish a fully completed iteration.
            }
            return Result(move: best, completedDepth: completed, nodes: nodes)
        }

        private func checkTime() throws {
            if let deadline, DispatchTime.now().uptimeNanoseconds >= deadline { throw Timeout() }
        }

        private func negamax(_ board: Board, _ color: PieceColor, _ depth: Int,
                             _ inputAlpha: Double, _ beta: Double) throws -> Double {
            nodes += 1
            if nodes % 128 == 0 { try checkTime() }
            let key = Position(board, color)
            let cached = table[key]
            if let cached, cached.depth >= depth {
                switch cached.bound {
                case .exact: return cached.score
                case .lower: if cached.score >= beta { return cached.score }
                case .upper: if cached.score <= inputAlpha { return cached.score }
                }
            }
            let moves = Engine.legalMoves(board: board, color: color)
            if moves.isEmpty { return -win }
            // No stand-pat is allowed with compulsory captures. At nominal depth
            // zero, finish all forced exchanges before evaluating. Each capture
            // reduces material, so this extension terminates without an arbitrary cap.
            if depth <= 0 && moves[0].captures.isEmpty {
                return evaluate(board, color)
            }
            var alpha = inputAlpha
            var best = -Double.infinity
            var bestMove: Move?
            for move in ordered(moves, board: board, preferred: cached?.move) {
                let score = try -negamax(Engine.applyMove(board: board, move: move),
                                         color.opponent, max(0, depth - 1), -beta, -alpha)
                if score > best { best = score; bestMove = move }
                alpha = max(alpha, score)
                if alpha >= beta { break }
            }
            let bound: Bound = best <= inputAlpha ? .upper : (best >= beta ? .lower : .exact)
            // Bound memory per move. Clearing only costs speed, never correctness.
            if table.count >= 100_000 { table.removeAll(keepingCapacity: true) }
            table[key] = Entry(depth: depth, score: best, bound: bound, move: bestMove)
            return best
        }

        private func ordered(_ moves: [Move], board: Board, preferred: Move?) -> [Move] {
            func priority(_ move: Move) -> Int {
                if move.path == preferred?.path { return 1_000_000 }
                var score = move.captures.reduce(0) { $0 + (board[$1]?.king == true ? 280 : 100) }
                if let piece = board[move.from], !piece.king {
                    let row = Engine.rowOf(move.to)
                    if row == (piece.color == .white ? 0 : 9) { score += 250 }
                }
                return score
            }
            var ranked: [(index: Int, move: Move, score: Int)] = []
            for (index, move) in moves.enumerated() {
                ranked.append((index, move, priority(move)))
            }
            ranked.sort { lhs, rhs in
                lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score > rhs.score
            }
            return ranked.map { $0.move }
        }

        /// Material dominates. Reward connected men, safe advancement, mobility,
        /// and central kings; keep these positional terms smaller than a man.
        private func evaluate(_ board: Board, _ color: PieceColor) -> Double {
            var total = 0.0
            for i in board.indices {
                guard let piece = board[i] else { continue }
                let r = Engine.rowOf(i), c = Engine.colOf(i)
                let advance = piece.color == .black ? r : 9 - r
                var value = piece.king ? 310.0 : 100.0
                if piece.king {
                    value += 1.5 * (9 - abs(Double(r) - 4.5) - abs(Double(c) - 4.5))
                    for (dr, dc) in [(-1, -1), (-1, 1), (1, -1), (1, 1)] {
                        var nr = r + dr, nc = c + dc
                        while (0..<10).contains(nr) && (0..<10).contains(nc) && board[nr * 10 + nc] == nil {
                            value += 0.6
                            nr += dr; nc += dc
                        }
                    }
                } else {
                    value += Double(advance) * 3
                    value += 4.5 - abs(Double(c) - 4.5)
                    let back = piece.color == .black ? -1 : 1
                    for dc in [-1, 1] {
                        let nr = r + back, nc = c + dc
                        if (0..<10).contains(nr) && (0..<10).contains(nc),
                           let friend = board[nr * 10 + nc], friend.color == piece.color {
                            value += 5
                        }
                        let fr = r - back
                        if (0..<10).contains(fr) && (0..<10).contains(nc), board[fr * 10 + nc] == nil {
                            value += 2
                        }
                    }
                    if advance >= 7 { value += Double(advance - 6) * 7 }
                }
                total += piece.color == color ? value : -value
            }
            return total
        }
    }
}
