import Foundation

/// CPU-only engine. All mutable search state belongs to one invocation.
/// The UI's rules engine remains the authority for the returned full capture path.
enum StrongAI {
    struct Result {
        let move: Move?
        let completedDepth: Int
        let nodes: Int
    }

    static func chooseMove(board: Board, color: PieceColor,
                           maxDepth: Int = 32, timeLimit: Double? = 0.3) -> Result {
        let start = DispatchTime.now().uptimeNanoseconds
        let legal = Engine.legalMoves(board: board, color: color)
        guard let fallback = legal.first else { return Result(move: nil, completedDepth: 0, nodes: 0) }
        if legal.count == 1 { return Result(move: fallback, completedDepth: 0, nodes: 0) }
        if let timeLimit, timeLimit <= 0 { return Result(move: fallback, completedDepth: 0, nodes: 0) }
        let search = Search(start: start, seconds: timeLimit)
        let result = search.run(Position(board, color), maxDepth: maxDepth)
        let move = result.move.flatMap { chosen in
            legal.first { CompactMove($0) == chosen }
        } ?? fallback
        return Result(move: move, completedDepth: result.depth, nodes: search.nodes)
    }

    // Numbering is 0...49, corresponding to PDN 1...50. No sentinel bits.
    static func square(_ index: Int) -> Int { index / 10 * 5 + index % 10 / 2 }
    static func index(_ square: Int) -> Int { square / 5 * 10 + (square % 5) * 2 + (1 - square / 5 % 2) }
    private static func bit(_ square: Int) -> UInt64 { UInt64(1) << square }
    private static let neighbors: [[Int]] = (0..<50).map { s in
        let i = index(s), r = i / 10, c = i % 10
        return [(-1, -1), (-1, 1), (1, -1), (1, 1)].map { dr, dc in
            let nr = r + dr, nc = c + dc
            return (0..<10).contains(nr) && (0..<10).contains(nc) ? nr * 5 + nc / 2 : -1
        }
    }

    struct CompactMove: Equatable {
        let from: Int
        let to: Int
        let captured: UInt64
        init(from: Int, to: Int, captured: UInt64 = 0) {
            self.from = from; self.to = to; self.captured = captured
        }
        init(_ move: Move) {
            from = square(move.from); to = square(move.to)
            captured = move.captures.reduce(UInt64(0)) { $0 | bit(square($1)) }
        }
        var historyIndex: Int { from * 50 + to }
    }

    struct Position: Equatable {
        var white: UInt64 = 0
        var black: UInt64 = 0
        var kings: UInt64 = 0
        var blackTurn: Bool
        init(_ board: Board, _ color: PieceColor) {
            blackTurn = color == .black
            for s in 0..<50 {
                guard let p = board[index(s)] else { continue }
                if p.color == .white { white |= bit(s) } else { black |= bit(s) }
                if p.king { kings |= bit(s) }
            }
        }
        var own: UInt64 { blackTurn ? black : white }
        var enemy: UInt64 { blackTurn ? white : black }
        var occupied: UInt64 { white | black }
        // Exact board comparison protects TT lookups, even if hashes collide.
        var hash: UInt64 {
            var z = white &* 0x9e3779b97f4a7c15 ^ black &* 0xbf58476d1ce4e5b9
            z ^= kings &* 0x94d049bb133111eb
            z ^= blackTurn ? 0xd6e8feb86659fd93 : 0
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            return z ^ (z >> 27)
        }
        func applying(_ move: CompactMove) -> Position {
            var p = self
            let origin = bit(move.from), destination = bit(move.to)
            let crowned = kings & origin != 0 || (blackTurn ? move.to >= 45 : move.to < 5)
            if blackTurn {
                p.black = (black & ~origin) | destination
                p.white &= ~move.captured
            } else {
                p.white = (white & ~origin) | destination
                p.black &= ~move.captured
            }
            p.kings &= ~(origin | move.captured)
            if crowned { p.kings |= destination }
            p.blackTurn.toggle()
            return p
        }

        func moves() -> [CompactMove] {
            var result: [CompactMove] = []
            var maxCaptures = 0
            var pieces = own
            while pieces != 0 {
                let from = pieces.trailingZeroBitCount
                pieces &= pieces - 1
                let occupied = self.occupied & ~bit(from)
                capture(from: from, at: from, king: kings & bit(from) != 0,
                        occupied: occupied, captured: 0, count: 0,
                        maximum: &maxCaptures, result: &result)
            }
            if maxCaptures > 0 { return result }
            pieces = own
            while pieces != 0 {
                let from = pieces.trailingZeroBitCount
                pieces &= pieces - 1
                let king = kings & bit(from) != 0
                for direction in (king ? 0 : (blackTurn ? 2 : 0))..<(king ? 4 : (blackTurn ? 4 : 2)) {
                    var to = neighbors[from][direction]
                    while to >= 0 && occupied & bit(to) == 0 {
                        result.append(CompactMove(from: from, to: to))
                        if !king { break }
                        to = neighbors[to][direction]
                    }
                }
            }
            return result
        }

        private func capture(from: Int, at: Int, king: Bool, occupied: UInt64,
                             captured: UInt64, count: Int,
                             maximum: inout Int, result: inout [CompactMove]) {
            var extended = false
            for d in 0..<4 {
                var target = neighbors[at][d]
                if king {
                    while target >= 0 && occupied & bit(target) == 0 { target = neighbors[target][d] }
                }
                guard target >= 0, enemy & bit(target) != 0, captured & bit(target) == 0 else { continue }
                var landing = neighbors[target][d]
                while landing >= 0 && occupied & bit(landing) == 0 {
                    extended = true
                    // Captured pieces remain blockers until the entire move ends.
                    // A man never becomes a flying king in the middle of a capture.
                    capture(from: from, at: landing, king: king, occupied: occupied,
                            captured: captured | bit(target), count: count + 1,
                            maximum: &maximum, result: &result)
                    if !king { break }
                    landing = neighbors[landing][d]
                }
            }
            if !extended && count > 0 && count >= maximum {
                if count > maximum { maximum = count; result.removeAll(keepingCapacity: true) }
                result.append(CompactMove(from: from, to: at, captured: captured))
            }
        }

        func evaluation() -> Int {
            if kings == 0, let learned = PatternEvaluation.evaluate(white: white, black: black) {
                return blackTurn ? -learned : learned
            }
            var score = 0
            for isBlack in [false, true] {
                let pieces = isBlack ? black : white
                var remaining = pieces
                var value = 0
                while remaining != 0 {
                    let s = remaining.trailingZeroBitCount
                    remaining &= remaining - 1
                    let r = s / 5, c = index(s) % 10
                    let advance = isBlack ? r : 9 - r
                    if kings & bit(s) != 0 {
                        value += 6200 + 15 * (18 - abs(2 * r - 9) - abs(2 * c - 9))
                        for d in 0..<4 {
                            var to = neighbors[s][d]
                            while to >= 0 && occupied & bit(to) == 0 {
                                value += 12
                                to = neighbors[to][d]
                            }
                        }
                    } else {
                        value += 2000 + advance * 60 + 10 * (9 - abs(2 * c - 9))
                        let back = isBlack ? 0 : 2
                        for d in back..<(back + 2) {
                            let to = neighbors[s][d]
                            if to >= 0 && pieces & bit(to) != 0 { value += 100 }
                        }
                        let forward = isBlack ? 2 : 0
                        for d in forward..<(forward + 2) {
                            let to = neighbors[s][d]
                            if to >= 0 && occupied & bit(to) == 0 { value += 40 }
                        }
                        if advance >= 7 { value += (advance - 6) * 140 }
                    }
                }
                score += isBlack ? value : -value
            }
            return blackTurn ? score : -score
        }
    }

    private struct Entry {
        var position: Position?
        var move: CompactMove?
        var score = 0
        var depth = -1
        var bound = 0 // 0 exact, -1 upper, +1 lower
        var generation = 0
    }
    private struct Timeout: Error {}
    private final class Search {
        let deadline: UInt64?
        var nodes = 0
        private var table = [Entry](repeating: Entry(), count: 1 << 16)
        private var history = [Int](repeating: 0, count: 5000)
        private var killers = [CompactMove?](repeating: nil, count: 128)
        private var ancestors: [Position] = []
        private var generation = 0
        private let win = 1_000_000
        init(start: UInt64, seconds: Double?) {
            deadline = seconds.map { start + UInt64(min(86400, max(0, $0)) * 1e9) }
        }
        private func checkTime() throws {
            if let deadline, DispatchTime.now().uptimeNanoseconds >= deadline { throw Timeout() }
        }
        func run(_ position: Position, maxDepth: Int) -> (move: CompactMove?, depth: Int) {
            let moves = position.moves()
            var best = moves.first
            var completed = 0
            for depth in 1...max(1, min(64, maxDepth)) {
                generation = depth
                do {
                    try checkTime()
                    var alpha = -win - 1
                    var iterationBest = best
                    ancestors = [position]
                    let sorted = ordered(moves, position, preferred: best, ply: 0)
                    for (i, move) in sorted.enumerated() {
                        try checkTime()
                        let child = position.applying(move)
                        var score: Int
                        if i == 0 {
                            score = try -search(child, depth - 1, -win - 1, -alpha, ply: 1)
                        } else {
                            score = try -search(child, depth - 1, -alpha - 1, -alpha, ply: 1)
                            if score > alpha { score = try -search(child, depth - 1, -win - 1, -alpha, ply: 1) }
                        }
                        if score > alpha { alpha = score; iterationBest = move }
                    }
                    best = iterationBest; completed = depth
                    if alpha > win - 128 { break }
                } catch { break }
            }
            return (best, completed)
        }
        private func search(_ p: Position, _ depth: Int, _ inputAlpha: Int, _ beta: Int, ply: Int) throws -> Int {
            nodes += 1
            if nodes & 255 == 0 { try checkTime() }
            if p.own == 0 { return -win + ply }
            // A repeated search-path position is treated as a draw to avoid cycles.
            // Scores are not cached in king positions: repetition depends on history.
            if p.kings != 0 && ancestors.contains(p) { return 0 }
            let slot = Int(p.hash & UInt64(table.count - 1))
            let cached = table[slot]
            let hit = cached.position == p
            let cacheScore = p.kings == 0
            if hit && cacheScore && cached.depth >= depth {
                let score = cached.score > win - 128 ? cached.score - ply :
                    (cached.score < -win + 128 ? cached.score + ply : cached.score)
                if cached.bound == 0 || (cached.bound > 0 && score >= beta) || (cached.bound < 0 && score <= inputAlpha) { return score }
            }
            let moves = p.moves()
            if moves.isEmpty { return -win + ply }
            let capture = moves[0].captured != 0
            if (depth <= 0 && !capture) || ply >= 120 { return p.evaluation() }
            ancestors.append(p)
            defer { ancestors.removeLast() }
            let sorted = ordered(moves, p, preferred: hit ? cached.move : nil, ply: ply)
            var alpha = inputAlpha
            var best = -win - 1
            var bestMove: CompactMove?
            for (i, move) in sorted.enumerated() {
                let child = p.applying(move)
                // A forced reply does not consume a decision ply. The absolute ply
                // guard and repetition check still bound king cycles.
                let nextDepth = max(0, depth - (moves.count == 1 ? 0 : 1))
                var score: Int
                if i == 0 {
                    score = try -search(child, nextDepth, -beta, -alpha, ply: ply + 1)
                } else {
                    // Only late quiet moves are reduced. Any improvement is verified
                    // at full depth; captures and promotions are never reduced.
                    let reduce = depth >= 4 && i >= 4 && !capture && child.kings == p.kings && beta == inputAlpha + 1
                    score = try -search(child, max(0, nextDepth - (reduce ? 1 : 0)), -alpha - 1, -alpha, ply: ply + 1)
                    if reduce && score > alpha { score = try -search(child, nextDepth, -alpha - 1, -alpha, ply: ply + 1) }
                    if score > alpha && score < beta { score = try -search(child, nextDepth, -beta, -alpha, ply: ply + 1) }
                }
                if score > best { best = score; bestMove = move }
                if score > alpha { alpha = score }
                if alpha >= beta {
                    if !capture {
                        killers[ply] = move
                        let h = (p.blackTurn ? 2500 : 0) + move.historyIndex
                        history[h] = min(100_000, history[h] + max(1, depth * depth))
                    }
                    break
                }
            }
            if !hit || depth >= cached.depth || cached.generation != generation {
                let stored = best > win - 128 ? best + ply : (best < -win + 128 ? best - ply : best)
                table[slot] = Entry(position: p, move: bestMove, score: stored, depth: depth,
                                    bound: best <= inputAlpha ? -1 : (best >= beta ? 1 : 0), generation: generation)
            }
            return best
        }
        private func ordered(_ moves: [CompactMove], _ p: Position, preferred: CompactMove?, ply: Int) -> [CompactMove] {
            if moves.count < 2 { return moves }
            let ranked = moves.enumerated().map { i, move -> (Int, Int, CompactMove) in
                var value = history[(p.blackTurn ? 2500 : 0) + move.historyIndex]
                if move == preferred { value += 10_000_000 }
                if move == killers[ply] { value += 200_000 }
                value += (move.captured & p.kings).nonzeroBitCount * 500_000
                if p.kings & bit(move.from) == 0 && (p.blackTurn ? move.to >= 45 : move.to < 5) { value += 300_000 }
                return (value, i, move)
            }
            return ranked.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 > $1.0 }.map { $0.2 }
        }
    }
}
