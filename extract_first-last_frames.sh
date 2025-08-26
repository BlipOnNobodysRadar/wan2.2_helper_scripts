#!/usr/bin/env bash
# Extract both the first and last frames from every MP4 in the current
# directory, writing matching .txt files. Employs several strategies to
# reliably grab the final frame.
set -euo pipefail
shopt -s nullglob nocaseglob

IMG_EXT="${IMG_EXT:-jpg}"
DEBUG="${DEBUG:-0}"
(( DEBUG )) && set -x

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }
need ffmpeg
need ffprobe

grab_first() {
  local in="$1" out="$2"
  ffmpeg -nostdin -hide_banner -loglevel error -y -i "$in" \
         -vf "select=eq(n\,0)" -vframes 1 -map 0:v:0 "$out"
}

grab_last() {
  local in="$1" out="$2"

  # 1) Try multiple near-end seeks (fast)
  local offsets=(-0.001 -0.01 -0.05 -0.1 -0.5 -1)
  for o in "${offsets[@]}"; do
    rm -f "$out"
    if ffmpeg -nostdin -hide_banner -loglevel error -y -sseof "$o" -i "$in" \
              -map 0:v:0 -frames:v 1 "$out"; then
      [[ -s "$out" ]] && return 0
    fi
  done

  # 2) Exact: count frames, then select n = frames-1
  local frames
  frames="$(ffprobe -v error -count_frames -select_streams v:0 \
            -show_entries stream=nb_read_frames -of csv=p=0 "$in" || echo "")"
  if [[ "$frames" =~ ^[0-9]+$ ]] && (( frames > 0 )); then
    local idx=$((frames - 1))
    rm -f "$out"
    if ffmpeg -nostdin -hide_banner -loglevel error -y -i "$in" \
              -vf "select=eq(n\,${idx})" -vframes 1 -map 0:v:0 "$out"; then
      [[ -s "$out" ]] && return 0
    fi
  fi

  # 3) Duration-based fallback (slow but robust)
  local dur
  dur="$(ffprobe -v error -show_entries format=duration \
         -of default=nw=1:nk=1 "$in" || echo "")"
  if [[ "$dur" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    # back off by 0.1s (tweak via EPS env var)
    local EPS="${EPS:-0.1}"
    local ss
    ss="$(awk -v d="$dur" -v e="$EPS" 'BEGIN{ s=d-e; if(s<0)s=0; print s }')"
    rm -f "$out"
    if ffmpeg -nostdin -hide_banner -loglevel error -y -ss "$ss" -i "$in" \
              -map 0:v:0 -frames:v 1 "$out"; then
      [[ -s "$out" ]] && return 0
    fi
  fi

  return 1
}

found=false
for f in *.mp4; do
  found=true
  stem="${f%.*}"

  img_first="${stem}.${IMG_EXT}"
  txt_first="${stem}.txt"

  img_last="${stem}_lastFrame.${IMG_EXT}"
  txt_last="${stem}_lastFrame.txt"

  # First frame
  if [[ -e "$img_first" ]]; then
    echo "SKIP  image exists: $img_first"
  else
    echo "→  $f  →  first →  $img_first"
    grab_first "$f" "$img_first"
    [[ -s "$img_first" ]] || { echo "ERR  first-frame empty: $img_first"; exit 2; }
  fi
  [[ -e "$txt_first" ]] || { : > "$txt_first"; echo "made $txt_first"; }

  # Last frame (robust)
  if [[ -e "$img_last" ]]; then
    echo "SKIP  image exists: $img_last"
  else
    echo "→  $f  →  last  →  $img_last"
    if ! grab_last "$f" "$img_last"; then
      echo "ERR  could not extract last frame for: $f" >&2
    fi
  fi
  [[ -e "$txt_last" ]] || { : > "$txt_last"; echo "made $txt_last"; }
done

if ! $found; then
  echo "No .mp4 files found in: $PWD"
fi
