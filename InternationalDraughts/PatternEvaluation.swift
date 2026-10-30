import Foundation

/// Immutable, locally trained 4x4 pattern tables. No inference service is used.
enum PatternEvaluation {
    private static let configurations = 6561 // 3^8: empty, white man, black man
    private static let patches: [[Int]] = {
        var result: [[Int]] = []
        for row in stride(from: 0, through: 6, by: 2) {
            for col in stride(from: 0, through: 6, by: 2) {
                var squares: [Int] = []
                for r in row..<(row + 4) {
                    for c in col..<(col + 4) where (r + c) % 2 == 1 { squares.append(r * 5 + c / 2) }
                }
                result.append(squares)
            }
        }
        return result
    }()
    private static let weights: [Int16]? = {
        guard let url = Bundle.main.url(forResource: "DraughtsPatterns", withExtension: "bin"),
              let data = try? Data(contentsOf: url), data.count == 16 * configurations * 2 else { return nil }
        // Explicit little-endian decoding avoids alignment and platform assumptions.
        return stride(from: 0, to: data.count, by: 2).map {
            Int16(bitPattern: UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8)
        }
    }()

    static var isAvailable: Bool { weights != nil }

    /// White-relative, with the same 2000-per-man scale as the fallback evaluator.
    /// Color swap plus 180-degree rotation negates the value exactly.
    static func evaluate(white: UInt64, black: UInt64) -> Int? {
        guard let weights else { return nil }
        var value = 2000 * (white.nonzeroBitCount - black.nonzeroBitCount)
        for (patch, squares) in patches.enumerated() {
            var forward = 0, reverse = 0, power = 1
            for square in squares {
                let mask = UInt64(1) << square
                let flipped = UInt64(1) << (49 - square)
                let a = white & mask != 0 ? 1 : (black & mask != 0 ? 2 : 0)
                let b = black & flipped != 0 ? 1 : (white & flipped != 0 ? 2 : 0)
                forward += a * power
                reverse += b * power
                power *= 3
            }
            value += Int(weights[patch * configurations + forward]) - Int(weights[patch * configurations + reverse])
        }
        return value
    }
}
