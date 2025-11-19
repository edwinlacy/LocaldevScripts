#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# ComfyUI Multi-GPU Environment Inspector
# =============================================================================
# This script *does not install* anything.
# It just inspects your system and prints:
#   - OS / package manager
#   - GPU / CUDA status
#   - Python / venv status
#   - Required Python packages (present/missing)
#   - Studio directory layout and key ports
# =============================================================================

USER_NAME="${USER}"
HOME_DIR="/home/${USER_NAME}"
STUDIO_DIR="${HOME_DIR}/studio"
COMFY_DIR="${STUDIO_DIR}/ComfyUI"
TOOLS_DIR="${STUDIO_DIR}/tools"
VENV="${STUDIO_DIR}/venv_comfy"
WEBUI_DIR="${STUDIO_DIR}/webui"
MONITOR_DIR="${STUDIO_DIR}/monitor"
AUTH_TOKEN_FILE="${STUDIO_DIR}/.webui_token"

REQUIRED_PY_PKGS=(fastapi uvicorn prometheus_client torch torchvision psutil pyyaml requests rich jinja2)
REQUIRED_SYSTEM_CMDS=(git curl wget jq python3)

PROM_PORT_BASE=8000
CONTROL_PORT_BASE=5005
COMFY_PORT_BASE=8188
WEBUI_PORT=8600

# Helpers
line() { printf '%*s\n' "$(tput cols 2>/dev/null || echo 80)" '' | tr ' ' '='; }

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

print_header() {
  line
  echo "$1"
  line
}

detect_pkg_mgr() {
  if have_cmd apt; then
    echo "apt"
  elif have_cmd dnf; then
    echo "dnf"
  elif have_cmd yum; then
    echo "yum"
  elif have_cmd pacman; then
    echo "pacman"
  elif have_cmd zypper; then
    echo "zypper"
  else
    echo "unknown"
  fi
}

check_port() {
  local port="$1"
  # ss preferred, fall back to netstat
  if have_cmd ss; then
    if ss -tulpn 2>/dev/null | grep -qE "[:.]${port}\s"; then
      echo "in use"
    else
      echo "free"
    fi
  elif have_cmd netstat; then
    if netstat -tulpn 2>/dev/null | grep -qE "[:.]${port}\s"; then
      echo "in use"
    else
      echo "free"
    fi
  else
    echo "unknown (ss/netstat missing)"
  fi
}

# =============================================================================
# 1. OS + Package manager
# =============================================================================
print_header "1. OS / Kernel / Package Manager"

if [ -f /etc/os-release ]; then
  . /etc/os-release
  echo "OS:       ${PRETTY_NAME:-Unknown}"
else
  echo "OS:       Unknown (/etc/os-release missing)"
fi

echo "Kernel:   $(uname -r)"
echo "Arch:     $(uname -m)"

PKG_MGR=$(detect_pkg_mgr)
echo "Pkg mgr:  ${PKG_MGR}"

# =============================================================================
# 2. System commands
# =============================================================================
print_header "2. Core System Commands"

MISSING_SYSTEM_CMDS=()
for cmd in "${REQUIRED_SYSTEM_CMDS[@]}"; do
  if have_cmd "${cmd}"; then
    printf "✔ %s found at %s\n" "${cmd}" "$(command -v "${cmd}")"
  else
    printf "✘ %s NOT found\n" "${cmd}"
    MISSING_SYSTEM_CMDS+=("${cmd}")
  fi
done

if have_cmd systemctl; then
  echo "✔ systemd/systemctl present"
else
  echo "✘ systemd/systemctl not detected (no systemd services)"
fi

# =============================================================================
# 3. Python / venv
# =============================================================================
print_header "3. Python / Virtual Environment"

if have_cmd python3; then
  PY_VER=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
  echo "Python3: ${PY_VER}"
else
  echo "Python3: NOT found"
fi

if python3 -m venv --help >/dev/null 2>&1; then
  echo "✔ python3-venv is available"
else
  echo "✘ python3-venv module appears missing"
fi

if [ -d "${VENV}" ]; then
  echo "✔ venv exists at: ${VENV}"
else
  echo "✘ venv not found at: ${VENV}"
fi

# =============================================================================
# 4. GPU / CUDA
# =============================================================================
print_header "4. GPU / CUDA"

if have_cmd nvidia-smi; then
  echo "✔ nvidia-smi detected at $(command -v nvidia-smi)"
  echo
  echo "GPU Summary:"
  nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader 2>/dev/null || {
    echo "  (Failed to query GPU list via nvidia-smi.)"
  }
else
  echo "✘ nvidia-smi not detected (NVIDIA drivers might be missing)"
fi

if have_cmd nvcc; then
  echo
  echo "CUDA toolkit: $(nvcc --version | sed -n '1,3p')"
else
  echo "CUDA toolkit (nvcc): not found in PATH"
fi

# =============================================================================
# 5. Studio layout
# =============================================================================
print_header "5. Studio Directory Layout"

for d in "${STUDIO_DIR}" "${COMFY_DIR}" "${TOOLS_DIR}" "${WEBUI_DIR}" "${MONITOR_DIR}"; do
  if [ -d "${d}" ]; then
    echo "✔ ${d} exists"
  else
    echo "✘ ${d} is missing"
  fi
done

if [ -f "${AUTH_TOKEN_FILE}" ]; then
  echo "✔ Auth token file exists at ${AUTH_TOKEN_FILE}"
else
  echo "✘ Auth token file missing at ${AUTH_TOKEN_FILE}"
fi

# =============================================================================
# 6. Web ports
# =============================================================================
print_header "6. Ports for WebUI / ComfyUI"

for port in "${WEBUI_PORT}" "${COMFY_PORT_BASE}" "$((COMFY_PORT_BASE + 100))" \
            "${PROM_PORT_BASE}" "${CONTROL_PORT_BASE}"; do
  status=$(check_port "${port}")
  printf "Port %-5s : %s\n" "${port}" "${status}"
done

# =============================================================================
# 7. Python packages in venv (if present)
# =============================================================================
print_header "7. Python Packages in venv_comfy"

MISSING_PY_PKGS=()

if [ -d "${VENV}" ]; then
  # shellcheck source=/dev/null
  source "${VENV}/bin/activate"

  # Use Python to check imports cleanly
  python3 - <<PY
import importlib

required = ${REQUIRED_PY_PKGS!r}
missing = []

print("Using Python:", end=" ")
import sys
print(".".join(map(str, sys.version_info[:3])))

for name in required:
    try:
        importlib.import_module(name)
        print(f"✔ {name} import OK")
    except Exception as e:
        print(f"✘ {name} MISSING ({e.__class__.__name__}: {e})")
        missing.append(name)

print("\nMISSING_PY_PKGS=" + ",".join(missing))
PY

else
  echo "venv not found, skipping Python package checks."
fi

# =============================================================================
# 8. Summary
# =============================================================================
print_header "8. Summary (What You Likely Need to Install)"

if [ "${#MISSING_SYSTEM_CMDS[@]}" -eq 0 ]; then
  echo "- Core system commands: OK"
else
  echo "- Missing system commands:"
  for c in "${MISSING_SYSTEM_CMDS[@]}"; do
    echo "    • ${c}"
  done
fi

echo
echo "Review the Python package section above for any 'MISSING_PY_PKGS=' line."
echo "Anything listed there should be installed inside ${VENV} with pip once the venv exists."
echo
echo "Done."
