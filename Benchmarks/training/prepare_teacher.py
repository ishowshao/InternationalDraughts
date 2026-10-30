#!/usr/bin/env python3
"""Add the training-only sample command to a fresh, pinned Scan checkout."""
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
revision = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
assert revision == '7aae17e7b7bfc47744601afb1ee7655e18983ce5', 'Unexpected teacher revision'
main = root / 'src/main.cpp'
source = main.read_text()
assert 'arg == "samples"' not in source, 'Already prepared; use a fresh checkout'
anchor = '   if (arg.empty()) { // terminal'
assert source.count(anchor) == 1
adapter = Path(__file__).with_name('scan_samples.inc').read_text()
source = source.replace('#include <cmath>', '#include <cmath>\n#include <random>\n#include <functional>')
main.write_text(source.replace(anchor, adapter + '\n' + anchor))
