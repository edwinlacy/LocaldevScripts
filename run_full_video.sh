#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./run_full_video.sh "My story idea..." 8
#
# Args:
#   $1 = high-level story prompt for LM Studio
#   $2 = number of scenes (default 8)

STORY_PROMPT="${1:-Write an 8-scene, 60-second vertical video story about a character discovering an AI-powered creative studio. Return ONLY a JSON array of 8 scene descriptions.}"
NUM_SCENES="${2:-8}"

# Where to save final output
OUT_ROOT="$HOME/studio/videos"
TS=$(date +"%Y%m%d_%H%M%S")
OUT_DIR="$OUT_ROOT/run_$TS"

mkdir -p "$OUT_DIR"

# Activate comfy venv
source "$HOME/studio/venv_comfy/bin/activate"

python "$HOME/studio/tools/orchestrator.py" \
  --story-prompt "$STORY_PROMPT" \
  --num-scenes "$NUM_SCENES" \
  --workflow-json "$HOME/studio/tools/wan2.2_animate_api.json" \
  --comfy-url "http://127.0.0.1:8188" \
  --comfy-output-dir "$HOME/studio/ComfyUI/output" \
  --output-dir "$OUT_DIR"

