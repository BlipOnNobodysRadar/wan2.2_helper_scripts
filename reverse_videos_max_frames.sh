
#!/usr/bin/env bash
# reverse_videos_max_frames.sh
# Reverse MP4s up to N frames (default 101). Longer clips are skipped.
# - Scans current directory only (simple, no recursion)
# - Outputs to ./reversed/
# - Output filenames: <base>_reversed.mp4
#
# Env toggles:
#   MAX_FRAMES=101     # process only files with frame count <= MAX_FRAMES
#   CRF=18             # libx264 quality (lower = higher quality)
#   PRESET=slow        # x264 speed/size trade-off
#   CODEC=libx264      # or h264_nvenc, etc.
#   KEEP_AUDIO=0       # 1 to reverse audio too (uses 'areverse')
#   OVERWRITE=0        # 1 to overwrite outputs if they exist
#   DRYRUN=0           # 1 to show actions without writing files

set -euo pipefail
shopt -s nullglob nocaseglob

MAX_FRAMES="${MAX_FRAMES:-101}"
CRF="${CRF:-18}"
PRESET="${PRESET:-slow}"
CODEC="${CODEC:-libx264}"
KEEP_AUDIO="${KEEP_AUDIO:-0}"
OVERWRITE="${OVERWRITE:-0}"
DRYRUN="${DRYRUN:-0}"

OUTDIR="reversed"
mkdir -p "$OUTDIR"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need ffmpeg
need ffprobe

ffw="-n"; [[ "$OVERWRITE" == "1" ]] && ffw="-y"

# Best-effort frame count (exact when possible)
count_frames() {
  local f="$1" nb dur rate fps
  nb="$(ffprobe -v error -select_streams v:0 -count_frames \
        -show_entries stream=nb_read_frames -of default=nk=1:nw=1 "$f" 2>/dev/null | tr -d '\r')"
  if [[ "$nb" =~ ^[0-9]+$ ]] && (( nb > 0 )); then echo "$nb"; return 0; fi
  nb="$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=nb_frames -of default=nk=1:nw=1 "$f" 2>/dev/null | tr -d '\r')"
  if [[ "$nb" =~ ^[0-9]+$ ]] && (( nb > 0 )); then echo "$nb"; return 0; fi
  dur="$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$f" 2>/dev/null | tr -d '\r')"
  [[ -z "$dur" || "$dur" == "N/A" ]] && dur=0
  rate="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate \
          -of default=nk=1:nw=1 "$f" 2>/dev/null | tr -d '\r')"
  [[ -z "$rate" || "$rate" == "N/A" ]] && rate="0/1"
  fps="$(awk -v r="$rate" 'BEGIN{split(r,a,"/"); if(a[2]==0){print 0}else{printf "%.6f", a[1]/a[2]}}')"
  awk -v d="$dur" -v f="$fps" 'BEGIN{printf "%.0f", d*f}'
}

has_audio() {
  local f="$1"
  ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$f" 2>/dev/null | grep -q .
}

processed=0 made=0 skipped=0 warned=0

for f in *.mp4; do
  [[ -e "$f" ]] || continue
  ((processed++)) || true
  frames="$(count_frames "$f" || echo "")"

  if ! [[ "$frames" =~ ^[0-9]+$ ]]; then
    echo "WARN  $f: could not determine frame count — skipping"
    ((warned++)) || true
    continue
  fi

  if (( frames > MAX_FRAMES )); then
    echo "SKIP  $f  ($frames > $MAX_FRAMES frames)"
    ((skipped++)) || true
    continue
  fi

  base="${f%.*}"
  out="$OUTDIR/${base}_reversed.mp4"

  echo "MAKE  $f  ($frames ≤ $MAX_FRAMES) -> $out"
  [[ "$DRYRUN" == "1" ]] && { ((made++)) || true; continue; }

  if [[ "$KEEP_AUDIO" == "1" ]] && has_audio "$f"; then
    # Reverse both video and audio
    ffmpeg $ffw -hide_banner -loglevel error -i "$f" \
      -filter_complex "[0:v]reverse[v];[0:a]areverse[a]" \
      -map "[v]" -map "[a]" \
      -c:v "$CODEC" -preset "$PRESET" -crf "$CRF" -pix_fmt yuv420p \
      -c:a aac -b:a 128k \
      -movflags +faststart "$out"
  else
    # Reverse video only, drop audio
    ffmpeg $ffw -hide_banner -loglevel error -i "$f" \
      -an -vf "reverse" \
      -c:v "$CODEC" -preset "$PRESET" -crf "$CRF" -pix_fmt yuv420p \
      -movflags +faststart "$out"
  fi

  ((made++)) || true
done

echo "Done. processed=$processed  made=$made  skipped=$skipped  warnings=$warned  outdir=$OUTDIR"

# Notes:
# - The 'reverse' (and 'areverse') filters buffer the whole stream in memory.
#   With ≤101 frames this is fine even at 1080p/4K, but be mindful of 4K + high bit depth.
