#!/usr/bin/env bash
# Fig's Kit (v0.1.0) - "Fig helps you figure it out."
# Open-source GPU rental assistant for $FIG / $COMPUTE (MIT License)
set -euo pipefail

FIG_DIR="$HOME/.fig"
mkdir -p "$FIG_DIR" "$HOME/fig-out"

cmd_doctor() {
  echo "🦊 Fig Doctor - Checking GPU machine..."
  echo "------------------------------------------------------------"
  HAS_GPU=0
  VRAM_GB=0
  if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    HAS_GPU=1
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 || echo "NVIDIA GPU")
    VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo "0")
    DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 || echo "Unknown")
    COMPUTE_CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n1 || echo "N/A")
    VRAM_GB=$(( (VRAM_MB + 1023) / 1024 ))
    echo "GPU:                $GPU_NAME"
    echo "VRAM:               ${VRAM_GB} GB (${VRAM_MB} MB)"
    echo "Driver:             $DRIVER (Compute Cap: $COMPUTE_CAP)"
  else
    echo "GPU:                No NVIDIA GPU detected or driver missing."
  fi
  echo "CUDA:               $(command -v nvcc &>/dev/null && nvcc --version | grep release | awk '{print $5}' | tr -d ',' || echo 'Driver CUDA available')"
  echo "Disk Free (/):      $(df -h / | awk 'NR==2 {print $4}')"
  echo "------------------------------------------------------------"
  if [ "$HAS_GPU" -eq 0 ]; then
    echo "⚠️  No NVIDIA GPU found. AI recipes require an NVIDIA GPU."
  else
    echo "Compatible Recipes for this machine:"
    [ "$VRAM_GB" -ge 8 ] && echo "  • chat       (Ollama: <=16GB->8B, 48GB->32B, 80GB->70B)"
    [ "$VRAM_GB" -ge 8 ] && echo "  • notebook   (Jupyter with PyTorch GPU check)"
    [ "$VRAM_GB" -ge 10 ] && echo "  • transcribe (Whisper speech-to-text Web UI)"
    [ "$VRAM_GB" -ge 16 ] && echo "  • images     (ComfyUI / Fooocus for image generation)" || echo "  ✕ images     (Needs >=16GB VRAM)"
    [ "$VRAM_GB" -ge 24 ] && echo "  • finetune   (LoRA fine-tune demo)" || echo "  ✕ finetune   (Needs >=24GB VRAM)"
  fi
}

cmd_save() {
  OUT_TAR="$HOME/fig-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  echo "🦊 Packing ~/fig-out into $OUT_TAR..."
  tar -czf "$OUT_TAR" -C "$HOME" fig-out
  SIZE=$(du -h "$OUT_TAR" | cut -f1)
  echo "✅ Archive created ($SIZE): $OUT_TAR"
  echo ""
  echo "To copy this archive to your local computer, run this on YOUR machine:"
  echo "  scp $(whoami)@$(hostname -I | awk '{print $1}'):$OUT_TAR ."
}

cmd_timer() {
  HOURS="${1:-1}"
  MINS=$(awk "BEGIN {print int($HOURS * 60)}")
  echo "🦊 Timer set for $HOURS hr ($MINS min). Warning at 15m and 5m remaining."
  (
    if [ "$MINS" -gt 15 ]; then sleep $(( (MINS - 15) * 60 )); echo -e "\n⏰ [Fig Warning] 15 MINUTES LEFT! Save your progress with 'fig save'.\n"; fi
    if [ "$MINS" -gt 5 ]; then sleep $(( 10 * 60 )); echo -e "\n🚨 [Fig Warning] 5 MINUTES LEFT! Run 'fig save' before rental ends!\n"; fi
  ) > /dev/tty 2>/dev/null &
}

cmd_help() {
  echo "Fig's Kit (v0.1.0) Commands:"
  echo "  fig doctor         Show GPU, VRAM, drivers & compatible recipes (<10s)"
  echo "  fig timer <hours>  Start rental countdown timer with 15m/5m warnings"
  echo "  fig save           Pack ~/fig-out into tarball and print download command"
  echo "  fig help           Show this command summary"
}

case "${1:-help}" in
  doctor) cmd_doctor ;;
  save)   cmd_save ;;
  timer)  cmd_timer "${2:-1}" ;;
  help|--help|-h) cmd_help ;;
  *)      echo "Unknown command: $1"; cmd_help; exit 1 ;;
esac
