
#!/usr/bin/env bash
# make_palindromes.sh
# Create loopable palindromes for short MP4s (≤ MAX_FRAMES).
# Output is capped to TARGET_FRAMES frames at FPS via time-condense if needed.
#
# Env:
#   MAX_FRAMES=101       # process only if input frames <= this
#   TARGET_FRAMES=101    # final cap
#   FPS=16               # final CFR
#   CRF=18               # encoder quality (libx264)
#   PRESET=slow
#   CODEC=libx264        # or h264_nvenc, etc.
#   ENFORCE_TARGET=0     # 1 = always output exactly TARGET_FRAMES (slow/speed)
#   KEEP_AUDIO=0         # 1 = also palindrome audio (areverse); may click at seam
#   OVERWRITE=0          # 1 = overwrite outputs
#   DRYRUN=0

set -euo pipefail
shopt -s nullglob nocaseglob

MAX_FRAMES="${MAX_FRAMES:-101}"
TARGET="${TARGET_FRAMES:-101}"
FPS="${FPS:-16}"
CRF="${CRF:-18}"
PRESET="${PRESET:-slow}"
CODEC="${CODEC:-libx264}"
ENFORCE_TARGET="${ENFORCE_TARGET:-0}"
KEEP_AUDIO="${KEEP_AUDIO:-0}"
OVERWRITE="${OVERWRITE:-0}"
DRYRUN="${DRYRUN:-0}"

OUTDIR="palindromes"
mkdir -p "$OUTDIR"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
need ffprobe; need ffmpeg

ffw="-n"; [[ "$OVERWRITE" == "1" ]] && ffw="-y"

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

speed_for() { awk -v n="$1" -v t="$2" 'BEGIN{ if(t<=0){print 1}else{printf "%.9f", n/t} }'; }

made=0 skipped=0 warned=0 processed=0

for f in *.mp4; do
  [[ -e "$f" ]] || continue
  ((processed++)) || true
  frames_in="$(count_frames "$f" || echo "")"
  if ! [[ "$frames_in" =~ ^[0-9]+$ ]]; then
    echo "WARN  $f: could not read frame count — skipping"; ((warned++)) || true; continue
  fi
  if (( frames_in > MAX_FRAMES )); then
    echo "SKIP  $f  ($frames_in > $MAX_FRAMES)"
    ((skipped++)) || true; continue
  fi

  # Palindrome will have roughly (2*frames_in - 1) frames (we drop the hinge dup)
  pal_frames=$(( 2*frames_in - 1 ))
  base="${f%.*}"
  out="$OUTDIR/${base}_pal.mp4"

  # Decide timing scale: >TARGET => speed up; <TARGET => optionally slow down/pad
  speed=1
  if (( pal_frames > TARGET )); then
    speed="$(speed_for "$pal_frames" "$TARGET")"  # >1 == faster
  elif [[ "$ENFORCE_TARGET" == "1" ]] && (( pal_frames < TARGET )); then
    speed="$(speed_for "$pal_frames" "$TARGET")"  # <1 == slower
  fi

  echo "MAKE  $f  in=$frames_in  pal=$pal_frames  speed=${speed}x  -> $out"
  [[ "$DRYRUN" == "1" ]] && { ((made++)) || true; continue; }

  if [[ "$KEEP_AUDIO" == "1" ]]; then
    # Reverse both streams; drop the first frame/sample of reversed to avoid a hard duplicate.
    ffmpeg $ffw -hide_banner -loglevel error -i "$f" \
      -filter_complex \
"[0:v]split=2[fwd][r0];[r0]reverse,trim=start_frame=1[rev];[fwd][rev]concat=n=2:v=1:a=0, setpts=PTS/${speed}, fps=${FPS}[v];
 [0:a]areverse,atrim=start=0.00002[ar];[0:a][ar]concat=n=2:v=0:a=1, asetpts=N/SR/TB[a]" \
      -map "[v]" -map "[a]" -frames:v "$TARGET" \
      -c:v "$CODEC" -preset "$PRESET" -crf "$CRF" -pix_fmt yuv420p \
      -c:a aac -b:a 128k -movflags +faststart "$out"
  else
    ffmpeg $ffw -hide_banner -loglevel error -i "$f" \
      -filter_complex \
"[0:v]split=2[fwd][r0];[r0]reverse,trim=start_frame=1[rev];[fwd][rev]concat=n=2:v=1:a=0, setpts=PTS/${speed}, fps=${FPS}[v]" \
      -map "[v]" -an -frames:v "$TARGET" \
      -c:v "$CODEC" -preset "$PRESET" -crf "$CRF" -pix_fmt yuv420p \
      -movflags +faststart "$out"
  fi

  ((made++)) || true
done

echo "Done. processed=$processed made=$made skipped=$skipped warned=$warned outdir=$OUTDIR"

# Notes:
# - 'reverse/areverse' buffer the whole stream; the MAX_FRAMES guard prevents accidents.
# - If you want exactly 101f for *every* output, run with ENFORCE_TARGET=1.
