#!/usr/bin/env bash
# A/B benchmark: decode + prefill tok/s at 450W vs 575W on gpu-box.
# Run ONLY when the GPU is idle (no inference session).
# llama-bench: pp512 = prompt processing (prefill), tg128 = token generation (decode).
set -uo pipefail
BENCH=/home/yashar/projects/llama.cpp/build/bin/llama-bench
MODEL=/home/yashar/models/Qwen3.8-27B-UD-Q4_K_M.gguf
OUT=/home/yashar/models/bench_450_vs_575.txt

echo "=== GPU power A/B bench $(date -Is) ===" > "$OUT"
if ! pgrep -f 'llama-server|ninfer-serve' >/dev/null 2>&1; then :; else
  echo "ABORT: an inference server is still resident — GPU not idle" | tee -a "$OUT"
  exit 1
fi

nvidia-smi -pm 1 >/dev/null
nvidia-smi -pl 450 >/dev/null
echo "--- 450W ---" >> "$OUT"
"$BENCH" -m "$MODEL" -p 512 -n 128 -r 3 2>/dev/null | tee -a "$OUT"

nvidia-smi -pl 575 >/dev/null
echo "--- 575W ---" >> "$OUT"
"$BENCH" -m "$MODEL" -p 512 -n 128 -r 3 2>/dev/null | tee -a "$OUT"

nvidia-smi -pl 450 >/dev/null   # restore the crash-safety cap
echo "--- restored 450W: $(nvidia-smi --query-gpu=power.limit --format=csv,noheader) ---" >> "$OUT"
echo DONE >> "$OUT"
cat "$OUT"
