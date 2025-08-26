#!/usr/bin/env bash
# Extract the first frame of every MP4 in the current directory and create
# a matching empty .txt file. Useful for preparing caption placeholders.
set -euo pipefail
shopt -s nullglob nocaseglob

# Change to "png" if you prefer PNGs
IMG_EXT="jpg"

found=false
for f in *.mp4; do
  found=true
  stem="${f%.*}"
  img="${stem}.${IMG_EXT}"
  txt="${stem}.txt"

  # Extract first frame
  if [[ -e "$img" ]]; then
    echo "SKIP  image exists: $img"
  else
    echo "→  $f  →  $img"
    ffmpeg -hide_banner -loglevel error -y -i "$f" \
           -vf "select=eq(n\,0)" -vframes 1 -map 0:v:0 \
           "$img"
  fi

  # Create matching .txt (empty) if not present
  if [[ -e "$txt" ]]; then
    echo "SKIP  text exists:  $txt"
  else
    : > "$txt"
    echo "made $txt"
  fi
done

if ! $found; then
  echo "No .mp4 files found in: $PWD"
fi

