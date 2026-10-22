#!/usr/bin/env bash
# Fig's Kit (v0.3.1) — "Fig helps you figure it out."
# Open-source GPU rental companion for $COMPUTE and Web4 token holders.
# MIT License
set -euo pipefail

FIG_VERSION="0.3.1"
FIG_DIR="${HOME}/fig-out"
LOG_DIR="${FIG_DIR}/logs"
FIG_STATE="${HOME}/.fig"   # private (700): Jupyter venv, token and config, installer temp; never in fig save backups
mkdir -p "$FIG_DIR" "$LOG_DIR"

get_vram_gb() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    local raw_mb
    raw_mb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' ')
    if [ -n "$raw_mb" ] && [ "$raw_mb" -eq "$raw_mb" ] 2>/dev/null; then
      echo $(( (raw_mb + 512) / 1024 ))
    else
      echo "0"
    fi
  else
    echo "0"
  fi
}

cmd_doctor() {
  echo "🦊 [Fig Doctor] Sniffing out your GPU & system hardware..."
  local start_time
  start_time=$(date +%s)

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "⚠️  No NVIDIA GPU detected or nvidia-smi is missing."
    echo "   Fig works best on GPU rentals with NVIDIA drivers pre-installed."
    return 1
  fi

  local gpu_name driver_ver cuda_ver vram_mb vram_gb disk_free
  gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 || echo "Unknown GPU")
  driver_ver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 || echo "Unknown")
  vram_mb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' ' || echo 0)
  vram_gb=$(( (vram_mb + 512) / 1024 ))
  cuda_ver=$(nvidia-smi 2>/dev/null | awk -F"CUDA Version: " 'NF>1 {split($2,a," "); print a[1]}' | head -n1)
  if [ -z "$cuda_ver" ]; then
    cuda_ver=$(nvcc --version 2>/dev/null | awk -F"V" 'NF>1 {print $2}' || echo "N/A")
  fi
  disk_free=$(df -h / | awk 'NR==2 {print $4}')

  echo "------------------------------------------------------------"
  echo "GPU Model:       $gpu_name"
  echo "Total VRAM:      ${vram_gb} GB (${vram_mb} MB)"
  echo "NVIDIA Driver:   $driver_ver"
  echo "CUDA Version:    $cuda_ver"
  echo "Disk Free (/):   $disk_free"
  echo "------------------------------------------------------------"

  echo "🦊 Recipe Readiness on this Machine:"
  if [ "$vram_gb" -ge 8 ]; then
    echo "  ✅ chat       [READY] Ollama API + CLI (16GB->8B, 48GB->32B, 80GB->70B)"
    echo "  ✅ notebook   [READY] Jupyter Lab loopback server + GPU check cell"
  else
    echo "  ⚠️ chat       (Needs >=8GB VRAM)"
    echo "  ⚠️ notebook   (Needs >=8GB VRAM)"
  fi
  echo "  ⏳ transcribe [ROADMAP] Whisper speech-to-text Web UI (planned)"
  echo "  ⏳ images     [ROADMAP] ComfyUI / Fooocus image generator (planned)"
  echo "  ⏳ finetune   [ROADMAP] Unsloth / LoRA fine-tuning demo (planned)"

  local elapsed=$(( $(date +%s) - start_time ))
  echo "------------------------------------------------------------"
  echo "⚡ Doctor check finished in ${elapsed}s (target: <10s)"
}

# fig_port_state PORT STOP_HINT: sets FIG_PORT=free (nothing listens) or FIG_PORT=loopback (only 127.0.0.1 listens).
# Anything else (0.0.0.0, *, [::], any other address, or no working ss to check with) prints why and returns 1.
fig_port_state() {
  local out addrs
  if ! command -v ss >/dev/null 2>&1 || ! out=$(ss -ltn 2>/dev/null); then
    echo "🦊 Fig checks what is already listening on port $1 with ss, which is missing or not working here."
    echo "   Install it, then try again:  apt-get install -y iproute2"
    return 1
  fi
  addrs=$(printf '%s\n' "$out" | awk -v p=":$1" 'NR > 1 && substr($4, length($4) - length(p) + 1) == p { print substr($4, 1, length($4) - length(p)) }' | sort -u)
  FIG_PORT=free
  if [ -z "$addrs" ]; then return 0; fi
  if [ "$addrs" = "127.0.0.1" ]; then FIG_PORT=loopback; return 0; fi
  echo "🦊 Port $1 is already in use on $(printf '%s\n' "$addrs" | tr '\n' ' ')and not only on 127.0.0.1, so Fig won't reuse it."
  echo "   Stop it first (for example:  $2), then try again."
  return 1
}

# fig_private_dir DIR: create DIR if needed and make it 700 (also when it already existed)
fig_private_dir() {
  mkdir -p -m 700 "$1" && chmod 700 "$1"
}

# fig_state_dir [PATH...]: refuse if FIG_STATE or any PATH inside it is a symlink, then make FIG_STATE private
fig_state_dir() {
  local p
  for p in "$FIG_STATE" "$@"; do
    if [ -L "$p" ]; then
      echo "🦊 ${p} is a symlink, so Fig won't write through it. Replace it with a plain file or directory, then try again."
      return 1
    fi
  done
  fig_private_dir "$FIG_STATE"
}

# fig_write_private FILE TEXT: write TEXT to a fresh mode-600 temp file next to FILE, then mv it over FILE
# (refused when FILE is a directory: mv would drop the temp file inside it instead)
fig_write_private() {
  local tmp
  if [ -d "$1" ]; then
    echo "🦊 $1 is a directory, so Fig won't write it. Move it aside, then try again."
    return 1
  fi
  tmp=$(mktemp "$1.XXXXXX") || return 1
  if chmod 600 "$tmp" && printf '%s\n' "$2" > "$tmp" && mv -f "$tmp" "$1"; then return 0; fi
  rm -f "$tmp"
  return 1
}

# Ollama's official installer sets up a system service and may use sudo, so it only runs on a yes or with
# --install-ollama. It is downloaded to a temp file and then run with sh, never piped into a shell.
fig_install_ollama() {
  if [ "$1" != 1 ]; then
    if [ ! -t 0 ]; then
      echo "🦊 Ollama is not installed and there is no terminal to ask on. To let Fig run its official installer:  fig start chat --install-ollama"
      return 1
    fi
    echo "🦊 The chat recipe needs Ollama, which is not installed yet. Its official installer sets up a system"
    echo "   service (and may use sudo), so Fig only runs it if you say yes."
    local answer=""
    printf 'Install Ollama with its official installer (https://ollama.com/install.sh)? [y/N] '
    read -r answer || answer=""
    case "$answer" in
      y|Y|yes|Yes|YES) ;;
      *) echo "🦊 Okay, nothing was installed. Install Ollama yourself, or run:  fig start chat --install-ollama"; return 1 ;;
    esac
  fi
  local installer traps ok=0
  fig_state_dir || return 1
  if ! installer=$(mktemp "${FIG_STATE}/ollama-install.XXXXXX"); then
    echo "⚠️  Could not create a temp file in ${FIG_STATE} for the installer, so nothing was installed."
    return 1
  fi
  # the temp file goes on every way out, Ctrl-C included; the caller's traps come back afterwards
  traps=$(trap -p HUP INT TERM)
  trap 'rm -f "$installer"; exit 130' HUP INT TERM
  echo "📦 Downloading Ollama's official installer to ${installer}..."
  if ! curl -q -fsSL --proto '=https' -o "$installer" https://ollama.com/install.sh; then
    echo "⚠️  Could not download https://ollama.com/install.sh, so nothing was installed."
  else
    echo "📦 Running the Ollama installer..."
    if sh "$installer"; then ok=1; else echo "⚠️  The Ollama installer did not finish."; fi
  fi
  rm -f "$installer"
  trap - HUP INT TERM
  eval "$traps"
  if [ "$ok" != 1 ]; then return 1; fi
  if ! command -v ollama >/dev/null 2>&1; then
    echo "⚠️  The installer finished, but ollama is still not on PATH."
    return 1
  fi
}

cmd_start_chat() {
  echo "🦊 [Fig Start: chat] Checking prerequisites for Ollama..."
  local vram
  vram=$(get_vram_gb)
  local model="llama3.2:3b"
  if [ "$vram" -ge 80 ]; then
    model="llama3.1:70b"
  elif [ "$vram" -ge 40 ]; then
    model="qwen2.5:32b"
  elif [ "$vram" -ge 12 ]; then
    model="llama3.1:8b"
  fi
  echo "🎯 Selected model based on ${vram} GB VRAM: ${model}"

  local install=0 arg
  for arg in "$@"; do
    if [ "$arg" = --install-ollama ]; then install=1; fi
  done
  if ! command -v ollama >/dev/null 2>&1; then
    fig_install_ollama "$install" || return 1
  fi

  local ollama_log="${LOG_DIR}/ollama.log"
  fig_port_state 11434 "systemctl stop ollama, or pkill -x ollama" || return 1
  if [ "$FIG_PORT" = free ]; then
    echo "🚀 Starting background Ollama daemon bound to 127.0.0.1:11434..."
    OLLAMA_HOST=127.0.0.1:11434 nohup ollama serve > "$ollama_log" 2>&1 &
    local ollama_pid=$!
    sleep 3
    if ! fig_port_state 11434 "pkill -x ollama"; then
      kill "$ollama_pid" 2>/dev/null || true
      return 1
    fi
    if [ "$FIG_PORT" != loopback ]; then
      kill "$ollama_pid" 2>/dev/null || true
      echo "⚠️  Ollama did not start listening on 127.0.0.1:11434, so Fig stopped it. Check logs: $ollama_log"
      return 1
    fi
  else
    echo "ℹ️  Ollama is already running on 127.0.0.1:11434 (loopback only), so Fig is reusing it"
  fi

  echo "📥 Pulling ${model} (may take a few minutes)..."
  OLLAMA_HOST=127.0.0.1:11434 ollama pull "$model"

  echo ""
  echo "============================================================"
  echo "🎉 Chat recipe ready!"
  echo "ℹ️  Note: Ollama runs as a local API service at http://127.0.0.1:11434"
  echo ""
  echo "To chat interactively in this terminal right now:"
  echo "   ollama run ${model}"
  echo ""
  echo "To connect your local browser/tools from your laptop:"
  echo "   ssh -N -L 11434:127.0.0.1:11434 ${USER:-root}@<rental_ip_or_host>"
  echo "   Then point your local browser/tools to http://127.0.0.1:11434"
  echo "============================================================"
}

# fig_jup_ok TOKEN: 0 only when GET /api/status with the token in the Authorization header answers 200 with
# Jupyter's status JSON (a JSON object holding "started" and "last_activity"). Any other reply (401, an HTML
# page, JSON of another shape, no answer) means not ready. The header reaches curl on stdin, never in argv.
fig_jup_ok() {
  local out code
  out=$(printf 'Authorization: token %s\n' "$1" | curl -q -s -m 2 --noproxy '*' -H @- -w '\n%{http_code}' http://127.0.0.1:8888/api/status 2>/dev/null) || return 1
  code="${out##*$'\n'}"
  out="${out%$'\n'*}"
  if [ "$code" != 200 ]; then return 1; fi
  printf '%s' "$out" | "${FIG_STATE}/venv/bin/python" -I -c 'import json, sys
d = json.load(sys.stdin)
sys.exit(0 if isinstance(d, dict) and "started" in d and "last_activity" in d else 1)' 2>/dev/null
}

# fig_jup_locked TOKEN: fig_jup_ok, and the same request is refused (401 or 403) both without a token and with a
# wrong one. That refuses servers that allow anonymous requests or accept any token; it does not prove the server
# is Fig's (a local process that binds the port first could still pass; reviews 10-22, planned for v0.3.2).
fig_jup_locked() {
  local code bad
  code=$(curl -q -s -m 2 --noproxy '*' -o /dev/null -w '%{http_code}' http://127.0.0.1:8888/api/status 2>/dev/null) || return 1
  bad=$(printf 'Authorization: token %s\n' not-the-fig-token | curl -q -s -m 2 --noproxy '*' -H @- -o /dev/null -w '%{http_code}' http://127.0.0.1:8888/api/status 2>/dev/null) || return 1
  case "$code $bad" in
    40[13]" "40[13]) fig_jup_ok "$1" ;;
    *) return 1 ;;
  esac
}

cmd_start_notebook() {
  echo "🦊 [Fig Start: notebook] Preparing Jupyter Lab on 127.0.0.1:8888..."
  local venv="${FIG_STATE}/venv" token_file="${FIG_STATE}/jupyter.token" token=""
  local jup_cfg="${FIG_STATE}/jupyter" jup_log="${LOG_DIR}/jupyter.log"
  local stop="JUPYTER_RUNTIME_DIR=~/.fig/runtime ~/.fig/venv/bin/jupyter server stop 8888" d
  fig_state_dir "$venv" "$jup_cfg" "${FIG_STATE}/tmp" "${FIG_STATE}/runtime" "${FIG_STATE}/data" "$token_file" "$jup_cfg/jupyter_server_config.json" || return 1
  if [ -f "$token_file" ]; then chmod 600 "$token_file"; fi
  fig_port_state 8888 "$stop" || return 1
  if [ "$FIG_PORT" = free ]; then
    # pip, ensurepip and Jupyter keep their temp, runtime (token-bearing jpserver-*.json) and data files in ~/.fig
    for d in tmp jupyter runtime data; do
      fig_private_dir "${FIG_STATE}/$d" || return 1
    done
    if [ ! -x "$venv/bin/jupyter-lab" ]; then
      # system site-packages stay visible so notebooks see the machine's PyTorch; the venv's pip must exist,
      # or "-m pip" would fall through to the system's pip
      if [ ! -x "$venv/bin/pip" ]; then
        if ! command -v python3 >/dev/null 2>&1 || ! TMPDIR="${FIG_STATE}/tmp" python3 -I -m venv --system-site-packages "$venv" > "$jup_log" 2>&1 || [ ! -x "$venv/bin/pip" ]; then
          echo "🦊 Jupyter goes in its own Python environment (${venv}), and python3 can't create one here."
          echo "   Install Python's venv support, then try again:  apt-get install -y python3-venv"
          return 1
        fi
      fi
      echo "📦 Installing jupyterlab into ${venv} (from https://pypi.org/simple only)..."
      # --ignore-installed: the venv gets its own full jupyterlab stack (and $venv/bin/jupyter) even when the
      # system Python already has jupyterlab or older copies of its dependencies
      if ! TMPDIR="${FIG_STATE}/tmp" PIP_CONFIG_FILE=/dev/null "$venv/bin/python" -I -m pip install --isolated --quiet --ignore-installed --index-url https://pypi.org/simple jupyterlab; then
        echo "⚠️  pip could not install jupyterlab into ${venv}. To start clean:  rm -rf ${venv}   then run:  fig start notebook"
        return 1
      fi
    fi
    # the token lives only in mode-600 files (never in argv): Jupyter reads it from its own config dir, which
    # replaces ~/.jupyter and outranks /etc/jupyter. python -I keeps PYTHONPATH and user site-packages out.
    token=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
    fig_write_private "$token_file" "$token" || return 1
    fig_write_private "$jup_cfg/jupyter_server_config.json" "{\"IdentityProvider\": {\"token\": \"${token}\"}, \"ServerApp\": {\"ip\": \"127.0.0.1\", \"port\": 8888, \"port_retries\": 0, \"open_browser\": false}}" || return 1
    echo "🚀 Starting Jupyter Lab server..."
    nohup env -u JUPYTER_CONFIG_PATH -u JUPYTER_NO_CONFIG JUPYTER_CONFIG_DIR="$jup_cfg" JUPYTER_RUNTIME_DIR="${FIG_STATE}/runtime" \
      JUPYTER_DATA_DIR="${FIG_STATE}/data" TMPDIR="${FIG_STATE}/tmp" "$venv/bin/python" -I "$venv/bin/jupyter-lab" \
      --ip=127.0.0.1 --port=8888 --no-browser --allow-root --ServerApp.port_retries=0 > "$jup_log" 2>&1 &
    local jup_pid=$!
    local ready=0 started
    started=$(date +%s)
    for i in $(seq 1 20); do
      # the process Fig started must still be running: a listener that answers after it died is not Fig's
      if ! kill -0 "$jup_pid" 2>/dev/null; then break; fi
      if fig_jup_ok "$token"; then
        ready=1
        break
      fi
      sleep 1
    done
    if [ "$ready" -ne 1 ]; then
      kill "$jup_pid" 2>/dev/null || true
      echo "⚠️  Jupyter did not become ready in $(( $(date +%s) - started ))s (20 checks), so Fig stopped it. Check logs: $jup_log"
      if [ -f "$jup_log" ]; then
        echo "--- Last 20 log lines ---"
        tail -n 20 "$jup_log"
        echo "-------------------------"
      fi
      echo "   If this keeps happening, start clean:  rm -rf ${venv}   then run:  fig start notebook"
      return 1
    fi
    if ! kill -0 "$jup_pid" 2>/dev/null || ! fig_port_state 8888 "$stop" || [ "$FIG_PORT" != loopback ] || ! fig_jup_locked "$token"; then
      kill "$jup_pid" 2>/dev/null || true
      echo "⚠️  Something answered, but Fig could not confirm it is its own running, loopback-only, token-protected Jupyter, so Fig stopped it."
      return 1
    fi
  else
    if [ -f "$token_file" ]; then token=$(cat "$token_file"); fi
    case "$token" in *[!0-9a-f]*) token="" ;; esac
    if [ -z "$token" ] || ! fig_jup_locked "$token"; then
      echo "🦊 Something already runs on 127.0.0.1:8888, but Fig can't confirm it needs a token Fig knows, so it won't reuse it."
      echo "   Stop it first (for example:  ${stop}), then run:  fig start notebook"
      return 1
    fi
    echo "ℹ️  Jupyter server is already running on 127.0.0.1:8888 (loopback only, token required)"
  fi

  echo ""
  echo "============================================================"
  echo "🎉 Jupyter Lab is running securely on loopback!"
  echo "🔑 Session Token: ${token}"
  echo ""
  echo "To open from your local laptop browser:"
  echo "1. Run this SSH tunnel in your local laptop terminal:"
  echo "   ssh -N -L 8888:127.0.0.1:8888 ${USER:-root}@<rental_ip_or_host>"
  echo "2. Open in your laptop browser:"
  echo "   http://127.0.0.1:8888/lab?token=${token}"
  echo "============================================================"
}

fig_has_model() {
  local want="$1" first rest
  while read -r first rest; do
    if [ "$first" = "$want" ] || [ "$first" = "${want}:latest" ]; then
      return 0
    fi
  done <<< "$2"
  return 1
}

cmd_start_persona() {
  local name="${1:-fox}"
  echo "🦊 [Fig Start: persona] Ears up! Giving your chat model a fox personality..."
  local bad=0
  case "$name" in
    *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) bad=1 ;;
  esac
  if [ "$bad" -eq 1 ] || [ "${#name}" -gt 20 ]; then
    echo "🦊 Persona names use 1-20 lowercase letters, digits or dashes, like: fig start persona gray-fox"
    return 1
  fi

  local vram base="llama3.2:3b"
  vram=$(get_vram_gb)
  if [ "$vram" -ge 80 ]; then
    base="llama3.1:70b"
  elif [ "$vram" -ge 40 ]; then
    base="qwen2.5:32b"
  elif [ "$vram" -ge 12 ]; then
    base="llama3.1:8b"
  fi

  if ! command -v ollama >/dev/null 2>&1; then
    echo "🦊 Ollama is not installed yet, and persona never installs anything."
    echo "   Run this first, then try again:  fig start chat"
    return 1
  fi

  local host="127.0.0.1:11434"
  local dir="${FIG_DIR}/personas/${name}"
  local log="${LOG_DIR}/persona-${name}.log"
  local models
  : > "$log"
  if ! models=$(OLLAMA_HOST="$host" ollama list 2>>"$log"); then
    echo "🦊 Ollama is not answering on ${host}. Start it with:  fig start chat"
    echo "--- Last lines of $log ---"
    tail -n 20 "$log"
    return 1
  fi
  if ! fig_has_model "$base" "$models"; then
    echo "🦊 Your chat model (${base}) is not downloaded yet, and persona never downloads."
    echo "   Run this first, then try again:  fig start chat"
    return 1
  fi

  local sys="You are Fig, a friendly and honest fox who helps people through their first hour on a rented GPU."
  sys="${sys} You explain GPUs, VRAM, Ollama, Jupyter, SSH tunnels and saving work before the rental ends, in short simple steps."
  sys="${sys} You are a small AI model playing a fox character. You are not a human and never claim to be one."
  sys="${sys} You cannot see the screen or run commands. If you are not sure, say so instead of guessing."
  sys="${sys} No financial talk: no prices, tokens, coins, trading or investing. If asked, say that is outside your den."
  sys="${sys} Never ask for passwords, keys, seed phrases or wallet signatures, and remind people never to share them."
  sys="${sys} Keep the fox flavor light, like an occasional Ears up or Yip, and only share fox facts you are sure are true."

  mkdir -p "$dir"
  local mf="${dir}/Modelfile"
  {
    echo "FROM ${base}"
    echo "PARAMETER temperature 0.7"
    echo "PARAMETER top_p 0.9"
    echo "PARAMETER repeat_penalty 1.1"
    echo "PARAMETER num_ctx 4096"
    echo "SYSTEM ${sys}"
  } > "$mf"

  echo "🦊 Building fig-${name} from ${base} plus a fox system prompt (no downloads)..."
  if ! OLLAMA_HOST="$host" ollama create "fig-${name}" -f "$mf" >>"$log" 2>&1; then
    echo "🦊 ollama create did not finish. Last lines of $log:"
    tail -n 20 "$log"
    return 1
  fi
  if ! models=$(OLLAMA_HOST="$host" ollama list 2>>"$log") || ! fig_has_model "fig-${name}" "$models"; then
    echo "🦊 fig-${name} does not show up in ollama list, so it is not ready. Last lines of $log:"
    tail -n 20 "$log"
    return 1
  fi

  echo ""
  echo "============================================================"
  echo "🎉 Yip! fig-${name} is ready (ollama list shows it)."
  echo "   Base model ${base} plus a fox system prompt. No training, no downloads."
  echo "   Modelfile: ${mf}"
  echo ""
  echo "To chat with it in this terminal:"
  echo "   ollama run fig-${name}"
  echo ""
  echo "API model name on http://127.0.0.1:11434: fig-${name}"
  echo "From your laptop, open a tunnel first:"
  echo "   ssh -N -L 11434:127.0.0.1:11434 ${USER:-root}@YOUR_RENTAL_IP"
  echo "To remove it later:  ollama rm fig-${name}"
  echo "============================================================"
}

cmd_save() {
  echo "🦊 [Fig Save] Packaging outputs in ~/fig-out..."
  local timestamp archive_path archive_name
  timestamp=$(date +%Y%m%d-%H%M%S)
  archive_name="fig-backup-${timestamp}.tar.gz"
  archive_path="${HOME}/${archive_name}"

  mkdir -p "$FIG_DIR"
  tar -czf "$archive_path" -C "$HOME" fig-out
  local size
  size=$(ls -lh "$archive_path" | awk '{print $5}')

  echo "✅ Archive created: ${archive_path} (${size})"
  echo ""
  echo "To download this backup to your laptop right now, run on your laptop:"
  echo "   scp -P <port> ${USER:-root}@<rental_ip_or_host>:${archive_path} ./"
  echo ""
  echo "(Replace <port> and <rental_ip_or_host> with your SSH credentials)"
}

cmd_timer() {
  local hours="${1:-}"
  if [ -z "$hours" ]; then
    echo "Usage: fig timer <hours> (e.g. fig timer 2)"
    return 1
  fi

  local total_secs
  total_secs=$(awk -v h="$hours" 'BEGIN { printf "%d", h * 3600 }')
  if [ -z "$total_secs" ] || [ "$total_secs" -le 0 ]; then
    echo "Error: invalid duration '$hours'"
    return 1
  fi

  echo "🦊 [Fig Timer] Rental timer set for ${hours}h (${total_secs}s)."
  echo "   Fig will notify you at 15m and 5m remaining so you can run 'fig save'!"

  local log_file="${LOG_DIR}/timer.log"
  mkdir -p "${LOG_DIR}"

  ( 
    _notify() {
      local msg="$1"
      local ts
      ts=$(date '+%Y-%m-%d %H:%M:%S')
      echo "[$ts] $msg" >> "$log_file"
      # terminal-output exception: Fig's one write outside $HOME (besides the opt-in Ollama installer), so alerts reach the SSH terminal
      if [ -w /dev/tty ]; then
        printf "\n%s\n" "$msg" > /dev/tty 2>/dev/null || true
      fi
    }

    if [ "$total_secs" -gt 900 ]; then
      sleep $(( total_secs - 900 ))
      _notify "⚠️  [Fig Timer Alert] 15 minutes left on your GPU rental! Run 'fig save' to preserve your work."
      sleep 600
      _notify "🚨 [Fig Timer Alert] Only 5 minutes left! Make sure to download your fig save archive now!"
      sleep 300
      _notify "⏰ [Fig Timer Alert] Your rental time of ${hours}h has expired!"
    elif [ "$total_secs" -gt 300 ]; then
      sleep $(( total_secs - 300 ))
      _notify "🚨 [Fig Timer Alert] Only 5 minutes left! Make sure to download your fig save archive now!"
      sleep 300
      _notify "⏰ [Fig Timer Alert] Your rental time of ${hours}h has expired!"
    else
      sleep "$total_secs"
      _notify "⏰ [Fig Timer Alert] Your rental timer for ${hours}h has ended!"
    fi
  ) >/dev/null 2>&1 &
  echo "⏱️  Background timer active (PID $!). Alerts will appear on your terminal & ${log_file}"
}

cmd_help() {
  echo "Fig's Kit (v${FIG_VERSION}) — 'Fig helps you figure it out.'"
  echo "Usage: fig <command> [arguments]"
  echo ""
  echo "Commands:"
  echo "  fig doctor          Check GPU, VRAM, CUDA, and recipe compatibility (<10s)"
  echo "  fig start chat      Launch Ollama local LLM service & pull model tailored to VRAM"
  echo "  fig start chat --install-ollama  Same, and run Ollama's official installer if Ollama is missing (no prompt)"
  echo "  fig start notebook  Launch Jupyter Lab server on loopback with token & SSH tunnel info"
  echo "  fig start persona [name]  Fox personality for your chat model (run fig start chat first)"
  echo "  fig timer <hours>   Set rental reminder alerts before expiration"
  echo "  fig save            Package ~/fig-out into a compressed archive for download"
  echo "  fig help            Show this help reference"
}

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    doctor)
      cmd_doctor "$@"
      ;;
    start)
      local recipe="${1:-}"
      shift || true
      case "$recipe" in
        chat)
          cmd_start_chat "$@"
          ;;
        notebook)
          cmd_start_notebook "$@"
          ;;
        persona)
          cmd_start_persona "$@"
          ;;
        *)
          echo "Unknown recipe: '$recipe'. Available recipes: chat, notebook, persona"
          exit 1
          ;;
      esac
      ;;
    save)
      cmd_save "$@"
      ;;
    timer)
      cmd_timer "$@"
      ;;
    help|--help|-h)
      cmd_help "$@"
      ;;
    version|--version|-v)
      echo "fig v${FIG_VERSION}"
      ;;
    *)
      echo "Unknown command: '$cmd'"
      cmd_help
      exit 1
      ;;
  esac
}

main "$@"
