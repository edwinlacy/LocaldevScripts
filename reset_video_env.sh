#!/bin/bash
set -e

echo "🔥 Resetting Comfy + Orchestrator environment…"

##########################################
# 1. Kill any running Comfy/Orchestrator
##########################################
echo "🛑 Killing leftover Python/Comfy processes…"
pkill -f "main.py" || true
pkill -f "comfy" || true
pkill -f "orchestrator" || true
pkill -f "python .*main.py" || true
sleep 1

##########################################
# 2. Clean Comfy output folder
##########################################
COMFY_OUT="$HOME/studio/ComfyUI/output"
echo "🧹 Cleaning Comfy output: $COMFY_OUT"

rm -rf "$COMFY_OUT"/*.mp4 2>/dev/null || true
rm -rf "$COMFY_OUT"/video/* 2>/dev/null || true
rm -rf "$COMFY_OUT"/images/* 2>/dev/null || true

mkdir -p "$COMFY_OUT/video"

##########################################
# 3. Clean Orchestrator output folder
##########################################
ORCH_OUT="$HOME/studio/outputs/dual4090_test"
echo "🧹 Cleaning orchestrator output: $ORCH_OUT"

rm -rf "$ORCH_OUT"/* 2>/dev/null || true
mkdir -p "$ORCH_OUT"

##########################################
# 4. OPTIONAL: clear WAN / diffusion caches
##########################################
echo "🧼 Cleaning WAN / model caches (optional)…"
rm -rf ~/.cache/comfyui/* 2>/dev/null || true
rm -rf ~/.cache/huggingface/* 2>/dev/null || true

##########################################
# 5. Report
##########################################
echo "✅ Environment reset complete!"
echo "You can now restart both Comfy instances and run orchestrator."
echo
echo "Start GPU 0:"
echo "  CUDA_VISIBLE_DEVICES=0 PYTORCH_ALLOC_CONF=backend:native \\"
echo "    python main.py --listen 0.0.0.0 --port 8188"
echo
echo "Start GPU 1:"
echo "  CUDA_VISIBLE_DEVICES=1 PYTORCH_ALLOC_CONF=backend:native \\"
echo "    python main.py --listen 0.0.0.0 --port 8288"
echo
echo "Then run orchestrator normally."
