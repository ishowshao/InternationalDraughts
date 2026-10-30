#!/usr/bin/env python3
"""Summarize JSONL matches and conservatively audit special king endings.

The historical match runner omits FMJD Annex 1 articles 6.3/6.4. For a lower
bound on candidate score, turn ANY candidate win that entered those material
classes into a draw, even if it actually won before the move limit. Keep losses.
This deliberately does not claim to implement the complete FMJD adjudicator.
"""
import argparse
import collections
import json
import statistics


def initial_board():
    return {r * 10 + c: (1 if r < 4 else -1)
            for r in range(10) for c in range(10)
            if (r + c) % 2 and (r < 4 or r >= 6)}


def apply(board, path):
    piece = board.pop(path[0])
    captured = set()
    for start, end in zip(path, path[1:]):
        r, c = divmod(start, 10)
        er, ec = divmod(end, 10)
        assert abs(er - r) == abs(ec - c) and er != r
        dr, dc = (1 if er > r else -1), (1 if ec > c else -1)
        r += dr
        c += dc
        while (r, c) != (er, ec):
            i = r * 10 + c
            if i in board:
                assert board[i] * piece < 0 and i not in captured
                captured.add(i)
            r += dr
            c += dc
    for i in captured:
        del board[i]
    if abs(piece) == 1 and path[-1] // 10 == (9 if piece > 0 else 0):
        piece *= 2
    board[path[-1]] = piece


def special_ending(board):
    for sign in [-1, 1]:
        own = [p for p in board.values() if p * sign > 0]
        other = [p for p in board.values() if p * sign < 0]
        if len(own) == 1 and abs(own[0]) == 2 and 1 <= len(other) <= 3:
            if any(abs(p) == 2 for p in other):
                return True
    return False


def audit(game):
    board = initial_board()
    for path in game['openingPaths']:
        apply(board, path)
    encountered = special_ending(board)
    for path in game['moves']:
        apply(board, path)
        encountered |= special_ending(board)
    outcome = game['outcome']
    conservative = 'draw' if encountered and outcome == 'win' else outcome
    return conservative, encountered


def summarize(games):
    raw = collections.Counter(g['outcome'] for g in games)
    audited = collections.Counter(audit(g)[0] for g in games)
    output = {'games': len(games), 'raw': dict(raw), 'conservative': dict(audited),
              'scorePercent': 100 * (raw['win'] + raw['draw'] / 2) / len(games),
              'conservativeScorePercent': 100 * (audited['win'] + audited['draw'] / 2) / len(games),
              'specialEndingGames': sum(audit(g)[1] for g in games)}
    for candidate, name in [(True, 'strong'), (False, 'opponent')]:
        decisions = [d for g in games for d in g['decisions'] if d['candidate'] == candidate]
        nonforced = [d for d in decisions if d['legalMoves'] > 1]
        output[name] = {
            'meanMilliseconds': 1000 * statistics.mean(d['seconds'] for d in decisions),
            'maxMilliseconds': 1000 * max(d['seconds'] for d in decisions),
            'medianNonforcedDepth': statistics.median(d['depth'] for d in nonforced),
            'nodesPerSecond': sum(d['nodes'] for d in decisions) / sum(d['seconds'] for d in decisions)}
    output['byColor'] = {c: dict(collections.Counter(g['outcome'] for g in games if g['newColor'] == c))
                         for c in ['white', 'black']}
    output['details'] = [{'opening': g['opening'], 'color': g['newColor'], 'outcome': g['outcome'],
                          'conservative': audit(g)[0], 'specialEnding': audit(g)[1]} for g in games]
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', nargs='+')
    args = parser.parse_args()
    games = [json.loads(line) for file in args.files for line in open(file) if line.strip()]
    print(json.dumps(summarize(games), indent=2))
