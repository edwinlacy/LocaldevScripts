#!/usr/bin/env bash
set -euo pipefail

TS=$(date -Iseconds | tr ':' '_')
OUT="$HOME/studio/debug_workflow_${TS}.log"
mkdir -p "$HOME/studio"

{
  echo "=== TIME ==="
  date -Iseconds
  echo

  echo "=== UNAME ==="
  uname -a
  echo

  echo "=== RAM ==="
  free -h
  echo

  echo "=== GPU (nvidia-smi) ==="
  nvidia-smi || echo "nvidia-smi failed"
  echo

  echo "=== DMESG (tail) ==="
  dmesg -T | tail -n 80
  echo

  echo "=== DMESG (nvidia/gpu/oom) ==="
  dmesg -T | grep -Ei "nvidia|nvrm|gpu|oom|fault" | tail -n 80 || true
  echo

  echo "=== comfyui-gpu0 logs ==="
  journalctl -u comfyui-gpu0.service -n 40 --no-pager || true
  echo

  echo "=== comfyui-gpu1 logs ==="
  journalctl -u comfyui-gpu1.service -n 40 --no-pager || true
  echo

  echo "=== comfyui-control logs ==="
  journalctl -u comfyui-control.service -n 40 --no-pager || true
} > "$OUT" 2>&1

echo "Saved debug snapshot -> $OUT"
