
#!/usr/bin/env bash
# condense_to_101f.sh
# Condense 16fps mp4s longer than 101 frames into exactly 101-frame clips at 16 fps.
# - Default input: all *.mp4 in the current directory (case-insensitive)
# - Output dir: ./condensed
# - Output names: <base>_condensed.mp4 (set KEEP_NAMES=1 to use <base>.mp4)
#
# Tunables via env:
#   OUTDIR=condensed         # output directory
#   FPS=16                   # output fps
#   TARGET_FRAMES=101        # target frames
#   CRF=18                   # quality for libx264
#   PRESET=slow              # x264 speed/size trade-off
#   CODEC=libx264            # e.g. libx264 or h264_nvenc
#   KEEP_AUDIO=0             # 1 to keep audio (will speed up & pitch shift)
#   KEEP_NAMES=0             # 1 to drop "_condensed" suffix (names identical to source)
#   OVERWRITE=0              # 1 to overwrite outputs if present
#   DRYRUN=0                 # 1 to show what would happen without writing files
#
# Usage:   bash condense_to_101f.sh
# Example: KEEP_NAMES=1 OVERWRITE=1 bash condense_to_101f.sh
# Notes:
# - We first try exact frame counting; if unavailable, we fall back to duration*fps.

set -euo pipefail
shopt -s nullglob nocaseglob

OUTDIR="${OUTDIR:-condensed}"
FPS="${FPS:-16}"
TARGET="${TARGET_FRAMES:-101}"
CRF="${CRF:-18}"
PRESET="${PRESET:-slow}"
CODEC="${CODEC:-libx264}"
KEEP_AUDIO="${KEEP_AUDIO:-0}"
KEEP_NAMES="${KEEP_NAMES:-0}"
OVERWRITE="${OVERWRITE:-0}"
DRYRUN="${DRYRUN:-0}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need ffmpeg
need ffprobe

mkdir -p "$OUTDIR"

ffw="-n"; [[ "$OVERWRITE" == "1" ]] && ffw="-y"

# Return integer frame count for $1; prefer exact count, fallback to duration*fps
count_frames() {
  local f="$1"
  # Try exact frame count (slow but reliable when supported)
  local nb
  nb="$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames \
                 -of default=nw=1:nk=1 "$f" 2>/dev/null || true)"
  if [[ "$nb" =~ ^[0-9]+$ ]] && (( nb > 0 )); then
    echo "$nb"; return 0
  fi
  # Fallback: duration * nominal fps
  local dur rrate fps
  dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$f" 2>/dev/null || echo 0)"
  rrate="$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nw=1:nk=1 "$f" 2>/dev/null || echo 0/1)"
  fps="$(awk -v r="$rrate" 'BEGIN{split(r,a,"/"); if(a[2]==0){print 0}else{printf "%.6f", a[1]/a[2]}}')"
  awk -v d="$dur" -v f="$fps" 'BEGIN{printf "%.0f", d*f}'
}

# Compute speed-up so the entire timeline maps to exactly TARGET frames
# S = frames_in / TARGET; we then apply setpts=PTS/S and force fps=FPS and cap frames to TARGET
speed_for() {
  local frames_in="$1"
  awk -v n="$frames_in" -v t="$TARGET" 'BEGIN{if(t==0){print 1}else{printf "%.9f", n/t}}'
}

num_processed=0
num_skipped=0
num_made=0

for f in *.mp4; do
  [[ -e "$f" ]] || continue
  ((num_processed++)) || true

  frames_in="$(count_frames "$f")"
  if ! [[ "$frames_in" =~ ^[0-9]+$ ]]; then
    echo "WARN  Could not determine frame count for: $f — skipping."
    ((num_skipped++)) || true
    continue
  fi

  if (( frames_in <= TARGET )); then
    echo "SKIP  $f  ($frames_in ≤ $TARGET frames)"
    ((num_skipped++)) || true
    continue
  fi

  speed="$(speed_for "$frames_in")"
  base="${f%.*}"
  suffix="_condensed"; [[ "$KEEP_NAMES" == "1" ]] && suffix=""
  out="${OUTDIR}/${base}${suffix}.mp4"

  echo "MAKE  $f  frames_in=$frames_in  speedup=${speed}x  ->  $out"
  [[ "$DRYRUN" == "1" ]] && { ((num_made++)) || true; continue; }

  vf="setpts=PTS/${speed},fps=${FPS}"

  if [[ "$KEEP_AUDIO" == "1" ]]; then
    # Audio is sped up (pitch rises). Add atempo-chaining if you want pitch correction.
    ffmpeg $ffw -hide_banner -loglevel error -i "$f" \
      -filter_complex "[0:v]$vf[v]" -map "[v]" -map 0:a? \
      -frames:v "$TARGET" -c:v "$CODEC" -preset "$PRESET" -crf "$CRF" -pix_fmt yuv420p \
      -c:a aac -b:a 128k -movflags +faststart "$out"
  else
    ffmpeg $ffw -hide_banner -loglevel error -i "$f" \
      -an -vf "$vf" -frames:v "$TARGET" \
      -c:v "$CODEC" -preset "$PRESET" -crf "$CRF" -pix_fmt yuv420p \
      -movflags +faststart "$out"
  fi

  ((num_made++)) || true
done

echo "Done. processed=$num_processed  made=$num_made  skipped=$num_skipped  outdir=$OUTDIR"
