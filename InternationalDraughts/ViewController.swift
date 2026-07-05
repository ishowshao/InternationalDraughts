//
//  ViewController.swift
//  InternationalDraughts
//
//  Game screen: board + side panel. Ported from the web version (src/App.tsx).
//  Layout adapts to orientation: portrait stacks the panel below the board,
//  landscape places it to the right.
//

import UIKit

class ViewController: UIViewController {

    // MARK: - Game state

    private var board: Board = Engine.initialBoard()
    private var turn: PieceColor = .white
    private var status: GameStatus = .playing
    private var difficulty: Difficulty = .medium

    // Current selection / in-progress capture sequence (path of squares).
    private var selected: Int?
    private var partialPath: [Int] = []
    private var lastMove: [Int] = []

    // Invalidates in-flight AI searches when a new game starts mid-think.
    private var aiGeneration = 0

    // It is the AI's turn to think whenever Black is to move during play.
    private var thinking: Bool { turn == .black && status == .playing }

    // Player is always White; AI is Black.
    private var playerMoves: [Move] {
        turn == .white && status == .playing ? Engine.legalMoves(board: board, color: .white) : []
    }

    private var movable: Set<Int> { Set(playerMoves.map { $0.from }) }

    // Moves consistent with the currently selected piece + in-progress path.
    private var activeMoves: [Move] {
        guard let selected else { return [] }
        return playerMoves.filter { m in
            m.from == selected && partialPath.enumerated().allSatisfy { k, sq in
                k < m.path.count && m.path[k] == sq
            }
        }
    }

    private var targets: Set<Int> {
        let step = partialPath.count // index of the next square in the path
        var s = Set<Int>()
        for m in activeMoves where m.path.count > step {
            s.insert(m.path[step])
        }
        return s
    }

    // MARK: - Views

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let boardView = BoardView()
    private let panelScroll = UIScrollView()
    private let panelStack = UIStackView()
    private let statusLabel = PaddedLabel()
    private let whiteCountLabel = UILabel()
    private let blackCountLabel = UILabel()
    private let difficultyControl = UISegmentedControl(items: Difficulty.allCases.map { $0.label })

    private var portraitConstraints: [NSLayoutConstraint] = []
    private var landscapeConstraints: [NSLayoutConstraint] = []
    private var isLandscapeLayout: Bool?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .appBackground
        buildViews()
        buildConstraints()
        boardView.onCellTap = { [weak self] index in self?.handleCellTap(index) }
        updateUI()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let landscape = view.bounds.width > view.bounds.height
        guard landscape != isLandscapeLayout else { return }
        isLandscapeLayout = landscape
        NSLayoutConstraint.deactivate(landscape ? portraitConstraints : landscapeConstraints)
        NSLayoutConstraint.activate(landscape ? landscapeConstraints : portraitConstraints)
    }

    // MARK: - View construction

    private func buildViews() {
        titleLabel.text = "国际跳棋"
        titleLabel.font = .systemFont(ofSize: 32, weight: .bold)
        titleLabel.textColor = .appHeading
        titleLabel.textAlignment = .center

        subtitleLabel.text = "International Draughts · 人机对战"
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .appText
        subtitleLabel.textAlignment = .center

        statusLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        statusLabel.textColor = .appHeading
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.backgroundColor = .accentBackground
        statusLabel.layer.cornerRadius = 10
        statusLabel.layer.borderWidth = 1
        statusLabel.layer.masksToBounds = true
        statusLabel.accessibilityIdentifier = "status"

        difficultyControl.selectedSegmentIndex = difficulty.rawValue
        difficultyControl.addTarget(self, action: #selector(difficultyChanged), for: .valueChanged)

        var newGameConfig = UIButton.Configuration.filled()
        newGameConfig.title = "新游戏"
        newGameConfig.baseBackgroundColor = .accent
        newGameConfig.baseForegroundColor = .white
        newGameConfig.cornerStyle = .medium
        newGameConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        let newGameButton = UIButton(configuration: newGameConfig)
        newGameButton.addTarget(self, action: #selector(newGameTapped), for: .touchUpInside)
        newGameButton.accessibilityIdentifier = "newGame"

        panelStack.axis = .vertical
        panelStack.spacing = 14
        panelStack.addArrangedSubview(statusLabel)
        panelStack.addArrangedSubview(scoreRow(color: .white, label: "你（白）", countLabel: whiteCountLabel))
        panelStack.addArrangedSubview(scoreRow(color: .black, label: "电脑（黑）", countLabel: blackCountLabel))
        panelStack.addArrangedSubview(labeledControl(title: "难度", control: difficultyControl))
        panelStack.addArrangedSubview(newGameButton)
        panelStack.addArrangedSubview(rulesCard())

        for v in [titleLabel, subtitleLabel, boardView, panelScroll, panelStack] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        panelScroll.addSubview(panelStack)
        for v in [titleLabel, subtitleLabel, boardView, panelScroll] {
            view.addSubview(v)
        }
    }

    private func scoreRow(color: PieceColor, label: String, countLabel: UILabel) -> UIView {
        let row = UIView()
        row.layer.cornerRadius = 10
        row.layer.borderWidth = 1
        row.layer.borderColor = UIColor.appBorder.cgColor

        let chip = ChipView(color: color)
        let nameLabel = UILabel()
        nameLabel.text = label
        nameLabel.font = .systemFont(ofSize: 15)
        nameLabel.textColor = .appText

        countLabel.font = .systemFont(ofSize: 18, weight: .bold)
        countLabel.textColor = .appHeading
        countLabel.accessibilityIdentifier = color == .white ? "whiteCount" : "blackCount"

        let stack = UIStackView(arrangedSubviews: [chip, nameLabel, countLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(stack)
        NSLayoutConstraint.activate([
            chip.widthAnchor.constraint(equalToConstant: 20),
            chip.heightAnchor.constraint(equalToConstant: 20),
            stack.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
        ])
        return row
    }

    private func labeledControl(title: String, control: UIView) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 14)
        label.textColor = .appText
        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func rulesCard() -> UIView {
        let card = UIView()
        card.layer.cornerRadius = 10
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.appBorder.cgColor

        let heading = UILabel()
        heading.text = "规则"
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        heading.textColor = .appHeading

        let body = UILabel()
        body.numberOfLines = 0
        let rules = [
            "10×10 棋盘，每方 20 子，只走深色格。",
            "普通子斜向前进一格；可向任意斜向跳吃。",
            "跳吃为强制，且必须选择吃子最多的走法。",
            "普通子到达底线升变为「王」，可远距离滑行与跳吃。",
            "无棋可走的一方判负。",
        ]
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 4
        body.attributedText = NSAttributedString(
            string: rules.map { "• \($0)" }.joined(separator: "\n"),
            attributes: [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: UIColor.appText,
                .paragraphStyle: paragraphStyle,
            ]
        )

        let stack = UIStackView(arrangedSubviews: [heading, body])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
        return card
    }

    private func buildConstraints() {
        let safe = view.safeAreaLayoutGuide

        // Shared: header on top, panel stack fills the scroll view.
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            titleLabel.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.centerXAnchor.constraint(equalTo: safe.centerXAnchor),

            panelStack.topAnchor.constraint(equalTo: panelScroll.contentLayoutGuide.topAnchor, constant: 4),
            panelStack.bottomAnchor.constraint(equalTo: panelScroll.contentLayoutGuide.bottomAnchor, constant: -16),
            panelStack.leadingAnchor.constraint(equalTo: panelScroll.contentLayoutGuide.leadingAnchor),
            panelStack.trailingAnchor.constraint(equalTo: panelScroll.contentLayoutGuide.trailingAnchor),
            panelStack.widthAnchor.constraint(equalTo: panelScroll.frameLayoutGuide.widthAnchor),

            boardView.widthAnchor.constraint(equalTo: boardView.heightAnchor),
        ])

        // Portrait: board under the header, panel scrolls below it.
        let portraitBoardWidth = boardView.widthAnchor.constraint(
            equalTo: safe.widthAnchor, constant: -32)
        portraitBoardWidth.priority = .defaultHigh
        portraitConstraints = [
            boardView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            boardView.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            portraitBoardWidth,
            boardView.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
            panelScroll.topAnchor.constraint(equalTo: boardView.bottomAnchor, constant: 16),
            panelScroll.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            panelScroll.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            panelScroll.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            panelScroll.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
        ]

        // Landscape: panel on the right, board centered in the remaining space.
        let boardArea = UILayoutGuide()
        view.addLayoutGuide(boardArea)
        let landscapeBoardHeight = boardView.heightAnchor.constraint(
            equalTo: boardArea.heightAnchor)
        landscapeBoardHeight.priority = .defaultHigh
        landscapeConstraints = [
            panelScroll.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            panelScroll.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            panelScroll.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            panelScroll.widthAnchor.constraint(equalToConstant: 300),
            boardArea.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            boardArea.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -12),
            boardArea.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            boardArea.trailingAnchor.constraint(equalTo: panelScroll.leadingAnchor, constant: -16),
            boardView.centerXAnchor.constraint(equalTo: boardArea.centerXAnchor),
            boardView.centerYAnchor.constraint(equalTo: boardArea.centerYAnchor),
            landscapeBoardHeight,
            boardView.heightAnchor.constraint(lessThanOrEqualTo: boardArea.heightAnchor),
            boardView.widthAnchor.constraint(lessThanOrEqualTo: boardArea.widthAnchor),
        ]
    }

    // MARK: - Interaction

    private func handleCellTap(_ i: Int) {
        guard turn == .white, status == .playing else { return }

        // Nothing selected yet: pick up a movable piece.
        guard selected != nil else {
            if movable.contains(i) {
                selected = i
                partialPath = [i]
                updateUI()
            }
            return
        }

        // Tap a highlighted target: advance the move / sequence.
        if targets.contains(i) {
            let newPath = partialPath + [i]
            let matching = activeMoves.filter { $0.path[partialPath.count] == i }
            // Under the maximum-capture rule all matching moves share a length, so
            // a path that reaches that length is a complete move.
            if let complete = matching.first(where: { $0.path.count == newPath.count }) {
                commit(complete)
            } else {
                partialPath = newPath
                updateUI()
            }
            return
        }

        // Otherwise: re-select another piece, or cancel (only at sequence start).
        if movable.contains(i) && partialPath.count <= 1 {
            selected = i
            partialPath = [i]
            updateUI()
        } else if partialPath.count <= 1 {
            selected = nil
            partialPath = []
            updateUI()
        }
    }

    private func commit(_ move: Move) {
        guard let mover = board[move.from]?.color else { return }
        let next = Engine.applyMove(board: board, move: move)
        let nextTurn = mover.opponent

        board = next
        lastMove = move.path
        selected = nil
        partialPath = []

        if Engine.legalMoves(board: next, color: nextTurn).isEmpty {
            status = mover == .white ? .whiteWin : .blackWin
        }
        turn = nextTurn
        updateUI()
        scheduleAIMoveIfNeeded()
    }

    /// Drive the AI when it is Black's turn. The search runs off the main thread;
    /// the short delay mirrors the web version and lets the move land naturally.
    private func scheduleAIMoveIfNeeded() {
        guard thinking else { return }
        aiGeneration += 1
        let generation = aiGeneration
        let snapshot = board
        let level = difficulty
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.35) { [weak self] in
            let move = Engine.chooseAIMove(board: snapshot, difficulty: level)
            DispatchQueue.main.async {
                guard let self, generation == self.aiGeneration,
                      self.turn == .black, self.status == .playing else { return }
                if let move { self.commit(move) }
            }
        }
    }

    @objc private func difficultyChanged() {
        difficulty = Difficulty(rawValue: difficultyControl.selectedSegmentIndex) ?? .medium
    }

    @objc private func newGameTapped() {
        aiGeneration += 1 // discard any in-flight AI search
        board = Engine.initialBoard()
        turn = .white
        status = .playing
        selected = nil
        partialPath = []
        lastMove = []
        updateUI()
    }

    // MARK: - UI refresh

    private func updateUI() {
        boardView.board = board
        boardView.selected = selected
        boardView.targets = targets
        boardView.lastMove = Set(lastMove)
        boardView.movable = movable

        whiteCountLabel.text = "\(Engine.countPieces(board: board, color: .white))"
        blackCountLabel.text = "\(Engine.countPieces(board: board, color: .black))"

        statusLabel.layer.borderColor = UIColor.accentBorder.cgColor
        switch status {
        case .whiteWin: statusLabel.text = "🎉 你赢了！"
        case .blackWin: statusLabel.text = "💻 电脑获胜"
        case .draw: statusLabel.text = "平局"
        case .playing: statusLabel.text = turn == .black ? "电脑思考中…" : "你的回合（白方）"
        }
        statusLabel.font = status == .playing
            ? .systemFont(ofSize: 16, weight: .semibold)
            : .systemFont(ofSize: 20, weight: .semibold)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // CGColor-based borders don't track dynamic colors automatically.
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            statusLabel.layer.borderColor = UIColor.accentBorder.cgColor
            for row in panelStack.arrangedSubviews where row.layer.borderWidth > 0 && row != statusLabel {
                row.layer.borderColor = UIColor.appBorder.cgColor
            }
        }
    }
}

// MARK: - Small helper views

/// Label with the web version's status-box padding.
final class PaddedLabel: UILabel {
    private let insets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + insets.left + insets.right,
            height: size.height + insets.top + insets.bottom
        )
    }
}

/// A small round chip matching the piece colors, for the scoreboard.
final class ChipView: UIView {
    private let pieceColor: PieceColor

    init(color: PieceColor) {
        self.pieceColor = color
        super.init(frame: .zero)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let circle = UIBezierPath(ovalIn: bounds)
        ctx.saveGState()
        circle.addClip()
        let stops: [UInt32] = pieceColor == .white
            ? [0xffffff, 0xc9cdd6, 0xaeb4c0]
            : [0x5a5f6b, 0x23262e, 0x14161b]
        let colors = stops.map { UIColor(rgb: $0).cgColor } as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.7, 1]
        ) {
            let center = CGPoint(x: bounds.width * 0.35, y: bounds.height * 0.3)
            ctx.drawRadialGradient(
                gradient,
                startCenter: center, startRadius: 0,
                endCenter: center, endRadius: bounds.width * 0.9,
                options: .drawsAfterEndLocation
            )
        }
        ctx.restoreGState()
    }
}
