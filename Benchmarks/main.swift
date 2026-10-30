import Foundation

struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
func position(_ board: Board, _ turn: PieceColor) -> String {
    (turn == .white ? "w" : "b") + board.map { p in
        guard let p else { return "." }
        return p.color == .white ? (p.king ? "W" : "w") : (p.king ? "B" : "b")
    }.joined()
}
func signature(_ moves: [Move]) -> [String] {
    moves.map { "\($0.path):\($0.captures)" }.sorted()
}
func verify() {
    var rng = SeededRandom(state: 5721)
    var board = Engine.initialBoard()
    var color = PieceColor.white
    for _ in 0..<300 {
        let legal = Engine.legalMoves(board: board, color: color)
        precondition(signature(legal) == signature(LegacyEngine.legalMoves(board: board, color: color)))
        if let move = legal.randomElement(using: &rng) {
            precondition(Engine.applyMove(board: board, move: move) == LegacyEngine.applyMove(board: board, move: move))
            board = Engine.applyMove(board: board, move: move)
            color = color.opponent
        } else { board = Engine.initialBoard(); color = .white }
    }
    for color in [PieceColor.white, .black] {
        precondition(AdvancedAI.chooseMove(board: Array(repeating: nil, count: 100), color: color).move == nil)
        var b: Board = Array(repeating: nil, count: 100)
        b[color == .black ? 32 : 67] = Piece(color: color, king: false)
        b[color == .black ? 54 : 45] = Piece(color: color.opponent, king: false)
        let move = AdvancedAI.chooseMove(board: b, color: color, maxDepth: 1, timeLimit: nil).move!
        precondition(move.to == (color == .black ? 41 : 58))
    }
    let fallback = AdvancedAI.chooseMove(board: Engine.initialBoard(), color: .white, timeLimit: 0)
    precondition(fallback.completedDepth == 0 && fallback.move != nil)
}
verify()
verifyStrong()
if CommandLine.arguments.contains("--verify-only") { print("Verification passed"); exit(0) }
let fixed = CommandLine.arguments.contains("--fixed")
let environment = ProcessInfo.processInfo.environment
let candidateSeconds = Double(environment["CANDIDATE_SECONDS"] ?? "0.3")!
let strongCandidate = environment["CANDIDATE"] == "strong"
let candidateDepth = Int(environment["CANDIDATE_DEPTH"] ?? (strongCandidate ? "32" : "12"))!
let advancedOpponent = environment["OPPONENT"] == "advanced"
let opponentSeconds = Double(environment["OPPONENT_SECONDS"] ?? "0.3")!
precondition(candidateSeconds > 0 && candidateSeconds.isFinite && candidateDepth > 0)
precondition(opponentSeconds > 0 && opponentSeconds.isFinite)
precondition(!fixed || !advancedOpponent, "--fixed is the original legacy comparison")
let count = Int(ProcessInfo.processInfo.environment["PAIRS"] ?? "6")!
let startPair = Int(ProcessInfo.processInfo.environment["START_PAIR"] ?? "0")!
let openingPlies = Int(environment["OPENING_PLIES"] ?? "6")!
precondition(count > 0 && startPair >= 0 && openingPlies >= 0)
var games: [[String: Any]] = []
for opening in startPair..<(startPair + count) {
    var initial = Engine.initialBoard()
    var turn = PieceColor.white
    var openingRNG = SeededRandom(state: UInt64(7000 + opening))
    var openingPaths: [[Int]] = []
    // Pair 0 uses the standard initial position. Others use seeded legal openings.
    for _ in 0..<(opening == 0 ? 0 : openingPlies) {
        guard let move = Engine.legalMoves(board: initial, color: turn).randomElement(using: &openingRNG) else { preconditionFailure("Opening ended before requested length") }
        openingPaths.append(move.path)
        initial = Engine.applyMove(board: initial, move: move)
        turn = turn.opponent
    }
    for newColor in [PieceColor.white, .black] {
        var board = initial, side = turn
        var random = SeededRandom(state: UInt64(9000 + opening))
        var seen = [position(board, side): 1]
        var quietKings = 0
        var newSeconds = 0.0, oldSeconds = 0.0
        var newMax = 0.0, oldMax = 0.0
        var newCount = 0, oldCount = 0
        var depths: [Int] = [], paths: [[Int]] = []
        var decisions: [[String: Any]] = []
        var outcome = "capped", reason = "240-ply limit"
        for _ in 0..<240 {
            let legal = Engine.legalMoves(board: board, color: side)
            precondition(signature(legal) == signature(LegacyEngine.legalMoves(board: board, color: side)))
            if legal.isEmpty {
                outcome = side == newColor ? "loss" : "win"; reason = "no legal moves"; break
            }
            let start = DispatchTime.now().uptimeNanoseconds
            let move: Move
            if side == newColor {
                let result: StrongAI.Result
                if strongCandidate {
                    result = StrongAI.chooseMove(board: board, color: side, maxDepth: fixed ? 6 : candidateDepth,
                                                 timeLimit: fixed ? nil : candidateSeconds)
                } else {
                    let original = AdvancedAI.chooseMove(board: board, color: side, maxDepth: fixed ? 6 : candidateDepth,
                                                         timeLimit: fixed ? nil : candidateSeconds)
                    result = StrongAI.Result(move: original.move, completedDepth: original.completedDepth, nodes: original.nodes)
                }
                move = result.move!
                let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
                newSeconds += seconds; newMax = max(newMax, seconds); newCount += 1
                if legal.count > 1 { depths.append(result.completedDepth) }
                decisions.append(["candidate": true, "legalMoves": legal.count,
                    "depth": result.completedDepth, "nodes": result.nodes, "seconds": seconds])
            } else {
                var opponentDepth = 0, opponentNodes = 0
                if advancedOpponent {
                    let result = AdvancedAI.chooseMove(board: board, color: side, maxDepth: 12,
                                                       timeLimit: opponentSeconds)
                    move = result.move!
                    opponentDepth = result.completedDepth; opponentNodes = result.nodes
                } else {
                    move = LegacyEngine.chooseAIMove(board: board, difficulty: .hard, color: side, random: &random)!
                }
                let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
                oldSeconds += seconds; oldMax = max(oldMax, seconds); oldCount += 1
                decisions.append(["candidate": false, "legalMoves": legal.count,
                    "depth": opponentDepth, "nodes": opponentNodes, "seconds": seconds])
            }
            precondition(legal.contains { $0.path == move.path && $0.captures == move.captures })
            quietKings = board[move.from]!.king && move.captures.isEmpty ? quietKings + 1 : 0
            paths.append(move.path)
            board = Engine.applyMove(board: board, move: move); side = side.opponent
            if Engine.legalMoves(board: board, color: side).isEmpty {
                outcome = side == newColor ? "loss" : "win"; reason = "no legal moves"; break
            }
            let key = position(board, side); seen[key, default: 0] += 1
            if seen[key]! >= 3 { outcome = "draw"; reason = "threefold repetition"; break }
            if quietKings >= 50 { outcome = "draw"; reason = "25 king-only moves each without capture"; break }
        }
        let game: [String: Any] = [
            "candidate": strongCandidate ? "strong" : "advanced",
            "candidateBudgetSeconds": fixed ? -1 : candidateSeconds,
            "candidateMaxDepth": fixed ? 6 : candidateDepth,
            "opponent": advancedOpponent ? "advanced" : "legacy",
            "opponentBudgetSeconds": advancedOpponent ? opponentSeconds : -1,
            "opponentMaxDepth": advancedOpponent ? 12 : 6,
            "openingPlies": openingPlies, "decisions": decisions, "opening": opening, "openingPaths": openingPaths,
            "newColor": newColor == .white ? "white" : "black", "outcome": outcome,
            "reason": reason, "plies": paths.count, "moves": paths,
            "newSeconds": newSeconds, "oldSeconds": oldSeconds, "newMoves": newCount, "oldMoves": oldCount,
            "newMaxSeconds": newMax, "oldMaxSeconds": oldMax, "completedDepths": depths]
        games.append(game)
        let data = try! JSONSerialization.data(withJSONObject: game, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!); fflush(stdout)
    }
}


// Differential tests deliberately include synthetic king-heavy positions, not only openings.
func verifyStrong() {
    precondition(PatternEvaluation.isAvailable, "Missing learned evaluation resource")
    func check(_ board: Board, _ color: PieceColor) {
        let p = StrongAI.Position(board, color)
        let expected = Engine.legalMoves(board: board, color: color)
        let actual = p.moves()
        func key(_ m: StrongAI.CompactMove) -> String { "\(m.from):\(m.to):\(m.captured)" }
        precondition(Set(actual.map(key)) == Set(expected.map { key(StrongAI.CompactMove($0)) }), "move generation mismatch")
        for m in expected {
            precondition(p.applying(StrongAI.CompactMove(m)) == StrongAI.Position(Engine.applyMove(board: board, move: m), color.opponent), "board update mismatch")
        }
    }
    var rng = SeededRandom(state: 0x51a7)
    var board = Engine.initialBoard(), color = PieceColor.white
    for _ in 0..<1500 {
        check(board, color)
        let legal = Engine.legalMoves(board: board, color: color)
        if let move = legal.randomElement(using: &rng) {
            board = Engine.applyMove(board: board, move: move); color = color.opponent
        } else { board = Engine.initialBoard(); color = .white }
    }
    for _ in 0..<2500 {
        var b: Board = Array(repeating: nil, count: 100)
        let squares = Array(0..<50).shuffled(using: &rng)
        let count = Int(rng.next() % 16) + 2
        for s in squares.prefix(count) {
            let i = StrongAI.index(s)
            let color: PieceColor = rng.next() & 1 == 0 ? .white : .black
            b[i] = Piece(color: color, king: rng.next() % 3 == 0 || i / 10 == (color == .white ? 0 : 9))
        }
        check(b, .white); check(b, .black)
    }
    // Exhaustive minimax is independent of PVS, ordering and TT bounds.
    func reference(_ p: StrongAI.Position, _ depth: Int, _ ply: Int, _ ancestors: [StrongAI.Position] = []) -> Int {
        if p.kings != 0 && ancestors.contains(p) { return 0 }
        let moves = p.moves()
        if moves.isEmpty { return -1_000_000 + ply }
        if (depth <= 0 && moves[0].captured == 0) || ply >= 120 { return p.evaluation() }
        return moves.map { -reference(p.applying($0), max(0, depth - (moves.count == 1 ? 0 : 1)), ply + 1, ancestors + [p]) }.max()!
    }
    for trial in 0..<24 {
        var b: Board = Array(repeating: nil, count: 100)
        for s in Array(5..<45).shuffled(using: &rng).prefix(6) {
            b[StrongAI.index(s)] = Piece(color: rng.next() & 1 == 0 ? .white : .black,
                                        king: trial % 3 == 0)
        }
        let c: PieceColor = trial & 1 == 0 ? .white : .black
        let p = StrongAI.Position(b, c), depth = trial % 3 == 0 ? 2 : 3
        let legal = p.moves()
        guard !legal.isEmpty else { continue }
        let best = legal.map { -reference(p.applying($0), depth - 1, 1, [p]) }.max()!
        let move = StrongAI.chooseMove(board: b, color: c, maxDepth: depth, timeLimit: nil).move!
        precondition(-reference(p.applying(StrongAI.CompactMove(move)), depth - 1, 1, [p]) == best, "PVS disagrees with minimax")
    }
    for c in [PieceColor.white, .black] {
        precondition(StrongAI.chooseMove(board: Array(repeating: nil, count: 100), color: c).move == nil)
        var b: Board = Array(repeating: nil, count: 100)
        b[c == .black ? 32 : 67] = Piece(color: c, king: false)
        b[c == .black ? 54 : 45] = Piece(color: c.opponent, king: false)
        let move = StrongAI.chooseMove(board: b, color: c, maxDepth: 1, timeLimit: nil).move!
        precondition(move.to == (c == .black ? 41 : 58))
    }
    let timeout = StrongAI.chooseMove(board: Engine.initialBoard(), color: .white, timeLimit: 0)
    precondition(timeout.move != nil && timeout.completedDepth == 0)
}
