#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build
swiftc -O InternationalDraughts/Engine.swift InternationalDraughts/AdvancedAI.swift InternationalDraughts/StrongAI.swift InternationalDraughts/PatternEvaluation.swift \
  Benchmarks/LegacyEngine.swift Benchmarks/main.swift -o build/ai-benchmark
cp InternationalDraughts/DraughtsPatterns.bin build/DraughtsPatterns.bin
build/ai-benchmark "$@"
