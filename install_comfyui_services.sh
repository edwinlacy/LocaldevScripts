#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Systemd units for:
#   - comfyui-gpu0 (GPU 0, port 8188)
#   - comfyui-gpu1 (GPU 1, port 8288)
#   - comfyui-control (port 5005)
#
# **IMPORTANT:** These are MANUAL START ONLY.
# No auto-start on boot.
# =============================================================================

USER_NAME="${USER}"
STUDIO_DIR="/home/${USER_NAME}/studio"
COMFY_DIR="${STUDIO_DIR}/ComfyUI"
VENV="${STUDIO_DIR}/venv_comfy"

GPU0_PORT=8188
GPU1_PORT=8288
CONTROL_PORT=5005

PY_BIN="${VENV}/bin/python"
UVICORN_BIN="${VENV}/bin/uvicorn"

echo "==> Creating MANUAL-START systemd units..."

# -----------------------------------------------------------------------------
# comfyui-gpu0.service
# -----------------------------------------------------------------------------
sudo bash -c "cat > /etc/systemd/system/comfyui-gpu0.service" <<EOF
[Unit]
Description=ComfyUI (GPU 0) on port ${GPU0_PORT}
After=network.target

[Service]
User=${USER_NAME}
WorkingDirectory=${COMFY_DIR}
Environment=CUDA_VISIBLE_DEVICES=0
Environment=PYTHONUNBUFFERED=1
ExecStart=${PY_BIN} main.py --listen 0.0.0.0 --port ${GPU0_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# -----------------------------------------------------------------------------
# comfyui-gpu1.service
# -----------------------------------------------------------------------------
sudo bash -c "cat > /etc/systemd/system/comfyui-gpu1.service" <<EOF
[Unit]
Description=ComfyUI (GPU 1) on port ${GPU1_PORT}
After=network.target

[Service]
User=${USER_NAME}
WorkingDirectory=${COMFY_DIR}
Environment=CUDA_VISIBLE_DEVICES=1
Environment=PYTHONUNBUFFERED=1
ExecStart=${PY_BIN} main.py --listen 0.0.0.0 --port ${GPU1_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# -----------------------------------------------------------------------------
# comfyui-control.service
# -----------------------------------------------------------------------------
sudo bash -c "cat > /etc/systemd/system/comfyui-control.service" <<EOF
[Unit]
Description=ComfyUI Control Patch (No Auth) on port ${CONTROL_PORT}
After=network.target

[Service]
User=${USER_NAME}
WorkingDirectory=${COMFY_DIR}
Environment=PYTHONUNBUFFERED=1
ExecStart=${UVICORN_BIN} comfyui_control_patch:app --host 0.0.0.0 --port ${CONTROL_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "==> Reloading systemd..."
sudo systemctl daemon-reload

echo "==> Disabling ALL services so they NEVER auto-start..."
sudo systemctl disable comfyui-gpu0.service || true
sudo systemctl disable comfyui-gpu1.service || true
sudo systemctl disable comfyui-control.service || true

echo
echo "=================================================================="
echo "✔ Services are installed but WILL NOT auto-start."
echo
echo "🔥 To start them manually:"
echo "  systemctl start comfyui-gpu0"
echo "  systemctl start comfyui-gpu1"
echo "  systemctl start comfyui-control"
echo
echo "🛑 To stop:"
echo "  systemctl stop comfyui-gpu0"
echo "  systemctl stop comfyui-gpu1"
echo "  systemctl stop comfyui-control"
echo
echo "👀 To check status:"
echo "  systemctl status comfyui-gpu0"
echo "  systemctl status comfyui-gpu1"
echo "  systemctl status comfyui-control"
echo "=================================================================="
