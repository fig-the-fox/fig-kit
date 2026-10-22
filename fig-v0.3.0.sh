#!/usr/bin/env bash
# Fig's Kit (v0.3.0) — "Fig helps you figure it out."
# Open-source GPU rental companion for $COMPUTE and Web4 token holders.
# MIT License
set -euo pipefail

FIG_VERSION="0.3.0"
FIG_DIR="${HOME}/fig-out"
LOG_DIR="${FIG_DIR}/logs"
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

  if ! command -v ollama >/dev/null 2>&1; then
    echo "📦 Installing Ollama binary..."
    curl -fsSL https://ollama.com/install.sh | sh
  fi

  local ollama_log="${LOG_DIR}/ollama.log"
  if ! pgrep -x ollama >/dev/null 2>&1; then
    echo "🚀 Starting background Ollama daemon bound to 127.0.0.1:11434..."
    OLLAMA_HOST=127.0.0.1:11434 nohup ollama serve > "$ollama_log" 2>&1 &
    sleep 3
  fi

  echo "📥 Pulling ${model} (may take a few minutes)..."
  ollama pull "$model"

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

cmd_start_notebook() {
  echo "🦊 [Fig Start: notebook] Preparing Jupyter Lab on 127.0.0.1:8888..."
  if ! command -v jupyter >/dev/null 2>&1; then
    echo "📦 Installing jupyterlab via pip..."
    pip install --quiet jupyterlab || pip3 install --quiet jupyterlab
  fi

  local jup_log="${LOG_DIR}/jupyter.log"
  if ! curl -s -m 2 http://127.0.0.1:8888/api >/dev/null 2>&1; then
    echo "🚀 Starting Jupyter Lab server..."
    nohup jupyter lab --ip=127.0.0.1 --port=8888 --no-browser --allow-root > "$jup_log" 2>&1 &
    local ready=0
    for i in $(seq 1 20); do
      if curl -s -m 1 http://127.0.0.1:8888/api >/dev/null 2>&1; then
        ready=1
        break
      fi
      sleep 1
    done
    if [ "$ready" -ne 1 ]; then
      echo "⚠️  Jupyter did not start within 20s. Check logs: $jup_log"
      if [ -f "$jup_log" ]; then
        echo "--- Last 20 log lines ---"
        tail -n 20 "$jup_log"
        echo "-------------------------"
      fi
      return 1
    fi
  else
    echo "ℹ️  Jupyter server is already running on 127.0.0.1:8888"
  fi

  local token
  token=$( (jupyter server list 2>/dev/null || true) | grep '127.0.0.1:8888' | sed -n 's/.*token=\([a-zA-Z0-9]*\).*/\1/p' | head -n1 || true)
  if [ -z "$token" ] && [ -f "$jup_log" ]; then
    token=$(grep -oE 'token=[a-zA-Z0-9]+' "$jup_log" | tail -n1 | cut -d= -f2 || true)
  fi

  echo ""
  echo "============================================================"
  echo "🎉 Jupyter Lab is running securely on loopback!"
  if [ -n "$token" ]; then
    echo "🔑 Session Token: ${token}"
  fi
  echo ""
  echo "To open from your local laptop browser:"
  echo "1. Run this SSH tunnel in your local laptop terminal:"
  echo "   ssh -N -L 8888:127.0.0.1:8888 ${USER:-root}@<rental_ip_or_host>"
  echo "2. Open in your laptop browser:"
  if [ -n "$token" ]; then
    echo "   http://127.0.0.1:8888/lab?token=${token}"
  else
    echo "   http://127.0.0.1:8888/lab"
  fi
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
