#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# ComfyUI Multi-GPU Minimal Installer (NO AUTH / NO TOKENS)
# =============================================================================
# - Creates ~/studio/venv_comfy
# - Installs Python deps in that venv
# - Clones ComfyUI into ~/studio/ComfyUI
# - Adds unload + control patches (no auth)
# - Adds a simple WebUI FastAPI app (no auth)
# - Sets up comfyui-webui systemd service on port 8600
# =============================================================================

USER_NAME="${USER}"
HOME_DIR="/home/${USER_NAME}"
STUDIO_DIR="${HOME_DIR}/studio"
COMFY_DIR="${STUDIO_DIR}/ComfyUI"
TOOLS_DIR="${STUDIO_DIR}/tools"
VENV="${STUDIO_DIR}/venv_comfy"
WEBUI_DIR="${STUDIO_DIR}/webui"
MONITOR_DIR="${STUDIO_DIR}/monitor"

WEBUI_PORT=8600
CONTROL_PORT=5005   # this is where you'll run comfyui_control_patch via uvicorn later

REQUIRED_PY_PKGS=(fastapi uvicorn prometheus_client torch torchvision psutil pyyaml requests rich jinja2)

echo "==> Using user: ${USER_NAME}"
echo "==> Studio dir: ${STUDIO_DIR}"
echo

# -----------------------------------------------------------------------------
# 0. Sanity: make sure we're on apt-based system
# -----------------------------------------------------------------------------
if ! command -v apt >/dev/null 2>&1; then
  echo "ERROR: apt not found. This script assumes Ubuntu/Debian."
  exit 1
fi

# -----------------------------------------------------------------------------
# 1. Create base directories
# -----------------------------------------------------------------------------
echo "==> Creating base directories (if missing)..."
mkdir -p "${STUDIO_DIR}" "${TOOLS_DIR}" "${WEBUI_DIR}" "${MONITOR_DIR}"

# -----------------------------------------------------------------------------
# 2. System deps (idempotent)
# -----------------------------------------------------------------------------
echo "==> Installing system dependencies via apt (idempotent)..."
sudo apt update -y
sudo apt install -y python3-venv python3-pip git curl wget jq systemd

# -----------------------------------------------------------------------------
# 3. Python venv for ComfyUI env
# -----------------------------------------------------------------------------
echo "==> Setting up Python venv at ${VENV} ..."
SYS_PY="/usr/bin/python3"
if [ ! -x "${SYS_PY}" ]; then
  SYS_PY="$(command -v python3 || true)"
fi

if [ -z "${SYS_PY}" ]; then
  echo "ERROR: python3 not found."
  exit 1
fi

if [ ! -d "${VENV}" ]; then
  echo "   - venv_comfy missing, creating..."
  "${SYS_PY}" -m venv "${VENV}"
else
  echo "   - venv_comfy already exists, reusing."
fi

# shellcheck source=/dev/null
source "${VENV}/bin/activate"

echo "==> Upgrading pip in venv..."
pip install --upgrade pip

echo "==> Installing required Python packages in venv..."
pip install "${REQUIRED_PY_PKGS[@]}"

# -----------------------------------------------------------------------------
# 4. Clone ComfyUI if missing
# -----------------------------------------------------------------------------
if [ ! -d "${COMFY_DIR}" ]; then
  echo "==> Cloning ComfyUI into ${COMFY_DIR} ..."
  git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFY_DIR}"
else
  echo "==> ComfyUI already present at ${COMFY_DIR}, skipping clone."
fi

# -----------------------------------------------------------------------------
# 5. ComfyUI unload patch (no auth involved)
# -----------------------------------------------------------------------------
echo "==> Writing comfyui_unload_patch.py ..."
cat > "${COMFY_DIR}/comfyui_unload_patch.py" <<'EOF'
#!/usr/bin/env python3
import gc, torch, logging
from comfy.model_management import ModelManager

logger = logging.getLogger("comfyui_unload")

def unload_all_models(graceful: bool = True):
    try:
        logger.info("Starting %s model unload", "graceful" if graceful else "aggressive")
        mm = ModelManager()
        for mname in list(mm.models.keys()):
            try:
                model = mm.models[mname]
                if hasattr(model, "to"):
                    model.to("cpu")
                del mm.models[mname]
            except Exception as e:
                logger.warning("Model %s unload failed: %s", mname, e)

        mm.models.clear()
        mm.models_loaded.clear()

        torch.cuda.empty_cache()
        gc.collect()

        if not graceful:
            if hasattr(mm, "pipelines"):
                mm.pipelines.clear()
            if hasattr(mm, "cache"):
                mm.cache.clear()
            torch.cuda.ipc_collect()
            logger.info("Performed aggressive pipeline+cache purge")

        logger.info("Model unload complete")
        return True
    except Exception as e:
        logger.exception("Unload error: %s", e)
        return False
EOF

chmod +x "${COMFY_DIR}/comfyui_unload_patch.py"

# -----------------------------------------------------------------------------
# 6. ComfyUI control patch (FastAPI + Prometheus, NO AUTH)
# -----------------------------------------------------------------------------
echo "==> Writing comfyui_control_patch.py (no auth)..."
cat > "${COMFY_DIR}/comfyui_control_patch.py" <<'EOF'
#!/usr/bin/env python3
import torch, gc
from fastapi import FastAPI, Response
from prometheus_client import Gauge, generate_latest, REGISTRY
from comfyui_unload_patch import unload_all_models

app = FastAPI(title="ComfyUI Control Patch (No Auth)")

gpu_vram_used = Gauge("gpu_vram_used_bytes", "GPU VRAM Used", ["gpu"])
gpu_vram_free = Gauge("gpu_vram_free_bytes", "GPU VRAM Free", ["gpu"])
last_eviction = Gauge("last_eviction_timestamp", "Last eviction time")

@app.get("/control/evict_aggressive")
def evict_aggressive():
    ok = unload_all_models(graceful=False)
    last_eviction.set_to_current_time()
    return {"status": "ok" if ok else "error"}

@app.get("/control/metrics")
def metrics():
    for i in range(torch.cuda.device_count()):
        free, used = torch.cuda.mem_get_info(i)
        gpu_vram_free.labels(gpu=str(i)).set(free)
        gpu_vram_used.labels(gpu=str(i)).set(used)
    return Response(generate_latest(REGISTRY), media_type="text/plain")
EOF

chmod +x "${COMFY_DIR}/comfyui_control_patch.py"

# -----------------------------------------------------------------------------
# 7. Minimal WebUI FastAPI app (NO AUTH)
# -----------------------------------------------------------------------------
echo "==> Writing minimal WebUI FastAPI app at ${WEBUI_DIR}/app.py (no auth)..."
cat > "${WEBUI_DIR}/app.py" <<EOF
#!/usr/bin/env python3
import os
from fastapi import FastAPI
from fastapi.responses import HTMLResponse
import httpx

CONTROL_PORT = ${CONTROL_PORT}

app = FastAPI(title="ComfyUI MultiGPU WebUI (No Auth)")

@app.get("/", response_class=HTMLResponse)
async def root():
    return HTMLResponse(\"""\
    <html>
      <head><title>ComfyUI MultiGPU WebUI (No Auth)</title></head>
      <body>
        <h1>ComfyUI MultiGPU WebUI (No Auth)</h1>
        <p>This endpoint exposes simple controls without authentication.</p>
        <p>Example eviction call (no auth):</p>
        <pre>
curl http://localhost:${WEBUI_PORT}/evict
        </pre>
      </body>
    </html>
    \""")

@app.post("/evict")
async def evict():
    url = f"http://127.0.0.1:{CONTROL_PORT}/control/evict_aggressive"
    async with httpx.AsyncClient() as client:
        r = await client.get(url)
        r.raise_for_status()
        return r.json()
EOF

chmod +x "${WEBUI_DIR}/app.py"

# -----------------------------------------------------------------------------
# 8. Systemd service for WebUI
# -----------------------------------------------------------------------------
echo "==> Installing comfyui-webui systemd service (no auth)..."
sudo bash -c "cat > /etc/systemd/system/comfyui-webui.service" <<EOF
[Unit]
Description=ComfyUI MultiGPU WebUI (No Auth)
After=network.target

[Service]
User=${USER_NAME}
WorkingDirectory=${WEBUI_DIR}
Environment=PYTHONUNBUFFERED=1
ExecStart=${VENV}/bin/uvicorn app:app --host 0.0.0.0 --port ${WEBUI_PORT}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now comfyui-webui.service

echo
echo "=================================================================="
echo "✅ Base multi-GPU ComfyUI env installed (NO AUTH)."
echo
echo "WebUI (no auth):  http://localhost:${WEBUI_PORT}"
echo "Venv:             ${VENV}"
echo "ComfyUI:          ${COMFY_DIR}"
echo
echo "To run the control patch (separately), for example:"
echo "  cd ${COMFY_DIR}"
echo "  ${VENV}/bin/uvicorn comfyui_control_patch:app --host 0.0.0.0 --port ${CONTROL_PORT}"
echo "=================================================================="
