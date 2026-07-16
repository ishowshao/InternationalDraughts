//
//  BoardView.swift
//  InternationalDraughts
//
//  Draws the 10x10 board, pieces and highlights with Core Graphics.
//  Ported from the web version (src/components/Board.tsx + App.css).
//

import UIKit

final class BoardView: UIView {

    static let borderWidth: CGFloat = 10

    var board: Board = Engine.initialBoard() { didSet { setNeedsDisplay() } }
    var selected: Int? { didSet { setNeedsDisplay() } }
    /// Squares the player can move to right now.
    var targets: Set<Int> = [] { didSet { setNeedsDisplay() } }
    /// Squares involved in the last move (for highlighting).
    var lastMove: Set<Int> = [] { didSet { setNeedsDisplay() } }
    /// Origin squares the player may pick up (have a legal move).
    var movable: Set<Int> = [] { didSet { setNeedsDisplay() } }
    /// Rotate the board 180° so Black sits at the bottom (nearby-match guest).
    var flipped = false { didSet { setNeedsDisplay() } }

    var onCellTap: ((Int) -> Void)?

    // Board colors are fixed (same in light and dark mode, like the web version).
    private let frameColor = UIColor(rgb: 0x4a3526)
    private let lightSquare = UIColor(rgb: 0xe9d3a8)
    private let darkSquare = UIColor(rgb: 0x9c6b43)
    private let selectionColor = UIColor(rgb: 0xffd54a)
    private let lastMoveOverlay = UIColor(rgb: 0xffdd57, alpha: 0.32)
    private let targetGreen = UIColor(red: 60 / 255, green: 180 / 255, blue: 90 / 255, alpha: 0.85)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityIdentifier = "board"
        accessibilityLabel = String(localized: "Draughts board")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var innerRect: CGRect {
        bounds.insetBy(dx: Self.borderWidth, dy: Self.borderWidth)
    }

    // MARK: - Touch

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let point = touches.first?.location(in: self) else { return }
        let inner = innerRect
        guard inner.contains(point), inner.width > 0 else { return }
        let cell = inner.width / CGFloat(Engine.size)
        let c = min(Engine.size - 1, max(0, Int((point.x - inner.minX) / cell)))
        let r = min(Engine.size - 1, max(0, Int((point.y - inner.minY) / cell)))
        let index = modelIndex(forDisplayIndex: r * Engine.size + c)
        if Engine.isPlayable(index) {
            onCellTap?(index)
        }
    }

    /// 180° rotation maps display cell i to board cell 99 - i (and vice versa).
    private func modelIndex(forDisplayIndex i: Int) -> Int {
        flipped ? Engine.size * Engine.size - 1 - i : i
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Wooden frame with rounded corners.
        let framePath = UIBezierPath(roundedRect: bounds, cornerRadius: 8)
        frameColor.setFill()
        framePath.fill()

        let inner = innerRect
        let cell = inner.width / CGFloat(Engine.size)

        for d in 0..<(Engine.size * Engine.size) {
            let r = Engine.rowOf(d)
            let c = Engine.colOf(d)
            let i = modelIndex(forDisplayIndex: d)
            let cellRect = CGRect(
                x: inner.minX + CGFloat(c) * cell,
                y: inner.minY + CGFloat(r) * cell,
                width: cell,
                height: cell
            )

            (Engine.isPlayable(i) ? darkSquare : lightSquare).setFill()
            ctx.fill(cellRect)

            if lastMove.contains(i) {
                lastMoveOverlay.setFill()
                ctx.fill(cellRect)
            }

            drawCoordinates(
                displayRow: r, displayCol: c,
                modelRow: Engine.rowOf(i), modelCol: Engine.colOf(i),
                in: cellRect, dark: Engine.isPlayable(i)
            )

            if let piece = board[i] {
                drawPiece(ctx, piece: piece, in: cellRect)
            } else if targets.contains(i) {
                drawTargetDot(ctx, in: cellRect)
            }

            if selected == i {
                let strokeWidth = max(3, cell * 0.09)
                let path = UIBezierPath(rect: cellRect.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2))
                path.lineWidth = strokeWidth
                selectionColor.setStroke()
                path.stroke()
            }
        }
    }

    private func drawCoordinates(
        displayRow: Int, displayCol: Int, modelRow: Int, modelCol: Int,
        in cellRect: CGRect, dark: Bool
    ) {
        let color = dark
            ? UIColor.white.withAlphaComponent(0.5)
            : UIColor.black.withAlphaComponent(0.4)
        let font = UIFont.systemFont(ofSize: max(8, cellRect.width * 0.2), weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]

        // Labels stay on the left/bottom edges of the screen but always name
        // the square's true rank/file, so they follow the flip.
        if displayCol == 0 {
            let text = "\(Engine.size - modelRow)" as NSString
            text.draw(at: CGPoint(x: cellRect.minX + 3, y: cellRect.minY + 2), withAttributes: attributes)
        }
        if displayRow == Engine.size - 1 {
            let text = String(UnicodeScalar(UInt8(65 + modelCol))) as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: cellRect.maxX - size.width - 3, y: cellRect.maxY - size.height - 2),
                withAttributes: attributes
            )
        }
    }

    private func drawPiece(_ ctx: CGContext, piece: Piece, in cellRect: CGRect) {
        let diameter = cellRect.width * 0.78
        let pieceRect = CGRect(
            x: cellRect.midX - diameter / 2,
            y: cellRect.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        let circle = UIBezierPath(ovalIn: pieceRect)

        // Drop shadow under the piece.
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: diameter * 0.06),
            blur: diameter * 0.1,
            color: UIColor.black.withAlphaComponent(0.5).cgColor
        )
        (piece.color == .white ? UIColor(rgb: 0xc9cdd6) : UIColor(rgb: 0x23262e)).setFill()
        circle.fill()
        ctx.restoreGState()

        // Radial gradient highlight, light source at upper-left (35%, 30%).
        ctx.saveGState()
        circle.addClip()
        let stops: [UInt32] = piece.color == .white
            ? [0xffffff, 0xc9cdd6, 0xaeb4c0]
            : [0x5a5f6b, 0x23262e, 0x14161b]
        let colors = stops.map { UIColor(rgb: $0).cgColor } as CFArray
        let locations: [CGFloat] = [0, 0.7, 1]
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations
        ) {
            let center = CGPoint(
                x: pieceRect.minX + pieceRect.width * 0.35,
                y: pieceRect.minY + pieceRect.height * 0.3
            )
            ctx.drawRadialGradient(
                gradient,
                startCenter: center, startRadius: 0,
                endCenter: center, endRadius: diameter * 0.9,
                options: .drawsAfterEndLocation
            )
        }
        ctx.restoreGState()

        // Subtle rim to lift the piece off the square.
        ctx.saveGState()
        let rim = UIBezierPath(ovalIn: pieceRect.insetBy(dx: 0.5, dy: 0.5))
        rim.lineWidth = 1
        UIColor.black.withAlphaComponent(0.25).setStroke()
        rim.stroke()
        ctx.restoreGState()

        if piece.king {
            let crown = "♛" as NSString
            let font = UIFont.systemFont(ofSize: cellRect.width * 0.4)
            let color = piece.color == .white ? UIColor(rgb: 0xb8860b) : UIColor(rgb: 0xffd54a)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = crown.size(withAttributes: attributes)
            crown.draw(
                at: CGPoint(x: cellRect.midX - size.width / 2, y: cellRect.midY - size.height / 2),
                withAttributes: attributes
            )
        }
    }

    private func drawTargetDot(_ ctx: CGContext, in cellRect: CGRect) {
        let diameter = cellRect.width * 0.26
        let dotRect = CGRect(
            x: cellRect.midX - diameter / 2,
            y: cellRect.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        // Soft outer ring.
        let ringWidth = max(2, cellRect.width * 0.06)
        let ring = UIBezierPath(ovalIn: dotRect.insetBy(dx: -ringWidth / 2, dy: -ringWidth / 2))
        ring.lineWidth = ringWidth
        targetGreen.withAlphaComponent(0.3).setStroke()
        ring.stroke()

        targetGreen.setFill()
        UIBezierPath(ovalIn: dotRect).fill()
    }
}
