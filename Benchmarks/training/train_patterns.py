#!/usr/bin/env python3
"""Fit our own 4x4 pattern tables to position scores emitted by Scan.

No Scan source or parameter file is copied into the output. Requires numpy/scipy.
Input lines: 51-character Hub position, then a white-relative static score.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.sparse import csr_matrix
from scipy.sparse.linalg import lsmr

parser = argparse.ArgumentParser()
parser.add_argument('samples')
parser.add_argument('output')
args = parser.parse_args()
boards, targets = [], []
for line in Path(args.samples).read_text().splitlines():
    fields = line.split()
    if len(fields) != 2 or len(fields[0]) != 51:
        continue
    text, score = fields
    if 'W' in text[1:] or 'B' in text[1:]:
        continue
    boards.append([{'e': 0, 'w': 1, 'b': 2}[c] for c in text[1:]])
    targets.append(float(score))
boards = np.array(boards, dtype=np.uint8)
targets = np.array(targets, dtype=np.float32)
boards, unique = np.unique(boards, axis=0, return_index=True)
targets = targets[unique]
patterns = []
for row in range(0, 7, 2):
    for col in range(0, 7, 2):
        patterns.append([r * 5 + c // 2 for r in range(row, row + 4)
                         for c in range(col, col + 4) if (r + c) % 2])
patterns = np.array(patterns)
powers = (3 ** np.arange(8)).astype(np.int32)
normal = (boards[:, patterns].astype(np.int32) * powers).sum(axis=2)
rotated = boards[:, ::-1].copy()
rotated = np.array([0, 2, 1], dtype=np.uint8)[rotated]
reverse = (rotated[:, patterns].astype(np.int32) * powers).sum(axis=2)
offsets = np.arange(16) * 6561
indices = np.concatenate([normal + offsets, reverse + offsets], axis=1).astype(np.int32)
values = np.tile(np.array([1] * 16 + [-1] * 16, dtype=np.float32), len(boards))
matrix = csr_matrix((values, indices.ravel(), np.arange(len(boards) + 1, dtype=np.int64) * 32),
                    shape=(len(boards), 16 * 6561))
material = 100 * ((boards == 1).sum(axis=1) - (boards == 2).sum(axis=1))
residual = targets - material
rng = np.random.default_rng(90210)
validation = rng.random(len(boards)) < 0.1
print(f'Unique positions {len(boards)}, train {(~validation).sum()}, held-out {validation.sum()}', flush=True)
fit = lsmr(matrix[~validation], residual[~validation], damp=5, atol=1e-5, btol=1e-5, maxiter=120, show=True)
weights = fit[0]
prediction = matrix[validation] @ weights + material[validation]
error = prediction - targets[validation]
# Integer inference uses the search engine's existing scale: one man = 2000.
quantized = np.rint(weights * 20).clip(-32768, 32767).astype('<i2')
Path(args.output).write_bytes(quantized.tobytes())
report = {'samples': len(targets), 'trainingPositions': int((~validation).sum()),
          'validationPositions': int(validation.sum()), 'validationRMSE': float(np.sqrt(np.mean(error ** 2))),
          'validationMAE': float(np.mean(abs(error))), 'oneManUnits': 100,
          'materialOnlyRMSE': float(np.sqrt(np.mean(residual[validation] ** 2))),
          'parameters': len(weights), 'bytes': len(quantized.tobytes()), 'ridgeDamping': 5,
          'iterations': int(fit[2]), 'sourceSamplesSHA256': hashlib.sha256(Path(args.samples).read_bytes()).hexdigest(),
          'modelSHA256': hashlib.sha256(quantized.tobytes()).hexdigest(), 'patterns': patterns.tolist()}
Path(args.output + '.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({k: v for k, v in report.items() if k != 'patterns'}, indent=2), flush=True)
