#!/usr/bin/env bash
# Convert video files in the current directory to constant 16fps MP4s
# using ffmpeg. Tweak settings via environment variables; optional
# h264_nvenc GPU acceleration.
set -euo pipefail
# Match files case-insensitively and ignore non-matches
shopt -s nullglob nocaseglob

# Tunables (env vars): FPS=16 CRF=18 PRESET=slow OUTDIR=16fps EVEN=2 GPU=0
FPS="${FPS:-16}"           # target fps
CRF="${CRF:-18}"           # lower = higher quality
PRESET="${PRESET:-slow}"   # x264 speed/size trade-off
OUTDIR="${OUTDIR:-16fps}"  # output dir
EVEN="${EVEN:-2}"          # set 64 if you want WxH multiples of 64
GPU="${GPU:-0}"            # 1 = use h264_nvenc

mkdir -p "$OUTDIR"

# scale to even (or 64-multiple) dims; lanczos for quality
SCALE_FILTER="scale=trunc(iw/${EVEN})*${EVEN}:trunc(ih/${EVEN})*${EVEN}:flags=lanczos"
# resample to CFR using timestamps (better than plain -r)
VF="fps=${FPS}:round=near,${SCALE_FILTER}"

# Add/trim extensions here if you want more formats
for f in *.{mp4,webm,mkv,mov,avi}; do
  [[ -e "$f" ]] || continue

  # Lowercased basename (no extension) for output naming
  stem="${f%.*}"
  stem_lc="${stem,,}"  # bash lowercase

  out="${OUTDIR}/${stem_lc}_16fps.mp4"
  [[ -e "$out" ]] && { echo "SKIP  $out"; continue; }

  echo "→  $f  →  $out"
  if [[ "$GPU" -eq 1 ]]; then
    ffmpeg -hide_banner -loglevel error -y -i "$f" \
      -vf "$VF" -r "$FPS" -vsync cfr -an \
      -movflags +faststart -pix_fmt yuv420p \
      -c:v h264_nvenc -cq "$CRF" -preset p5 -tune hq -rc vbr -bf 3 -spatial_aq 1 -temporal_aq 1 \
      "$out"
  else
    ffmpeg -hide_banner -loglevel error -y -i "$f" \
      -vf "$VF" -r "$FPS" -vsync cfr -an \
      -movflags +faststart -pix_fmt yuv420p \
      -c:v libx264 -preset "$PRESET" -crf "$CRF" -profile:v high -level 4.1 \
      -x264opts keyint=$((FPS*2)):min-keyint=$FPS:no-scenecut \
      "$out"
  fi
done
