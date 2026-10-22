#!/usr/bin/env bash
# Fig's Kit v0.1.2 — "Fig helps you figure it out."
# License: MIT | Pure bash, zero dependencies, no telemetry
set -euo pipefail

cmd_doctor() {
  echo "🦊 Ears up! Fig is sniffing out your machine specs..."
  echo "------------------------------------------------------------"
  local has_gpu=0 vram_gb=0 gpu_name="None" driver="None" cuda="None" vram_mb=0
  if command -v nvidia-smi >/dev/null 2>&1; then
    gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 || echo "Unknown GPU")
    vram_mb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo 0)
    driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 || echo "Unknown")
    # Parse CUDA version directly from nvidia-smi header or fallback to nvcc
    cuda=$(nvidia-smi 2>/dev/null | awk -F'CUDA Version: ' 'NF>1 {split($2,a," "); print a[1]}' | head -n1)
    if [ -z "$cuda" ]; then
      cuda=$(nvcc --version 2>/dev/null | awk -F'V' 'NF>1 {print $2}' || echo "N/A")
    fi
    # Round to nearest whole GB e.g. 24576 MB -> 24 GB, 8192 MB -> 8 GB
    vram_gb=$(( (vram_mb + 512) / 1024 ))
    has_gpu=1
  fi
  echo "GPU Model:       $gpu_name"
  echo "Total VRAM:      ${vram_gb} GB (${vram_mb} MB)"
  echo "NVIDIA Driver:   $driver"
  echo "CUDA Version:    $cuda"
  echo "Disk Free (/):   $(df -h / | awk 'NR==2 {print $4}')"
  echo "------------------------------------------------------------"
  if [ "$has_gpu" -eq 0 ]; then
    echo "⚠️  No NVIDIA GPU detected. AI recipes require an NVIDIA GPU."
  else
    echo "🦊 Yip! Compatible recipes ready to run:"
    [ "$vram_gb" -ge 8 ]  && echo "  • chat       (Ollama: <=16GB->8B, 48GB->32B, 80GB->70B)"
    [ "$vram_gb" -ge 8 ]  && echo "  • notebook   (Jupyter with PyTorch GPU check)"
    [ "$vram_gb" -ge 10 ] && echo "  • transcribe (Whisper speech-to-text Web UI)"
    [ "$vram_gb" -ge 16 ] && echo "  • images     (ComfyUI / Fooocus for image gen)" || echo "  ✕ images     (Needs >=16GB VRAM)"
    [ "$vram_gb" -ge 24 ] && echo "  • finetune   (LoRA fine-tuning demo)" || echo "  ✕ finetune   (Needs >=24GB VRAM)"
  fi
}

cmd_save() {
  local out_dir="$HOME/fig-out"
  local out_tar="$HOME/fig-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  mkdir -p "$out_dir"
  echo "🦊 Cache it before you go! Packing ~/fig-out..."
  tar -czf "$out_tar" -C "$HOME" fig-out
  local sz; sz=$(du -h "$out_tar" | cut -f1)
  echo "🦊 Yip! Archive created ($sz): $out_tar"
  echo ""
  echo "To copy this archive to your local computer, run this on YOUR laptop:"
  echo "  scp -P <ssh_port> <user>@<rental_ip_or_host>:$out_tar ./"
  echo "Example (using typical rental port, e.g. 22 or Vast/RunPod mapped port):"
  echo "  scp -P 22 root@<rental-host>:$out_tar ./"
}

cmd_timer() {
  local hours="${1:-1}"
  local mins
  mins=$(awk "BEGIN {print int($hours * 60)}")
  echo "🦊 Ears up! Timer set for $hours hr ($mins min). Fig will alert you at 15m & 5m remaining."
  (
    if [ "$mins" -gt 15 ]; then
      sleep $(( (mins - 15) * 60 ))
      echo -e "\n⏰ [Fig Warning] 15 MINUTES LEFT! Cache it before you go: run 'fig save'.\n"
    fi
    if [ "$mins" -gt 5 ]; then
      sleep $(( (mins > 15 ? 10 : mins - 5) * 60 ))
      echo -e "\n🚨 [Fig Warning] 5 MINUTES LEFT! Yip! Run 'fig save' before rental ends!\n"
    fi
  ) > /dev/tty 2>/dev/null &
}

cmd_help() {
  echo "Fig's Kit (v0.1.2) — Fox-guided GPU rental assistant"
  echo "Usage: fig <command> [args]"
  echo ""
  echo "Commands:"
  echo "  fig doctor         Sniff out GPU, VRAM, CUDA & compatible recipes (<10s)"
  echo "  fig timer <hours>  Start rental countdown timer with 15m/5m warnings"
  echo "  fig save           Pack ~/fig-out to tarball with scp command to grab it"
  echo "  fig help           Show this help summary"
}

case "${1:-help}" in
  doctor) cmd_doctor ;;
  save)   cmd_save ;;
  timer)  cmd_timer "${2:-1}" ;;
  help|--help|-h) cmd_help ;;
  *) echo "Unknown command: $1"; cmd_help; exit 1 ;;
esac
