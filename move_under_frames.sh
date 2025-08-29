
#!/usr/bin/env bash
# move_under_frames.sh
# Move MP4s with fewer than N frames into ./under_N_frames/
#
# Defaults:
#   FRAMES=102           # threshold: strictly less-than
#   RECURSE=0            # 0 = only current dir; 1 = include subfolders
#   DRYRUN=0             # 1 = show actions, don't move
#   OVERWRITE=0          # 1 = allow overwriting if same path exists in dest (rare)
#
# Usage:
#   bash move_under_frames.sh
#   FRAMES=150 bash move_under_frames.sh
#   RECURSE=1 DRYRUN=1 bash move_under_frames.sh
#
# Notes:
# - Frame count prefers an exact probe; falls back to duration * avg_frame_rate.
# - Keeps relative subfolder structure inside the destination when RECURSE=1.
# - Skips any files already inside the destination root.

set -euo pipefail

FRAMES="${FRAMES:-102}"
RECURSE="${RECURSE:-0}"
DRYRUN="${DRYRUN:-0}"
OVERWRITE="${OVERWRITE:-0}"
DEST_ROOT="under_${FRAMES}_frames"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need ffprobe
need mv

mkdir -p "$DEST_ROOT"

# Count frames with best-effort accuracy.
count_frames() {
  local f="$1" nb dur rate fps
  # Try exact read count
  nb="$(ffprobe -v error -select_streams v:0 -count_frames \
        -show_entries stream=nb_read_frames -of default=nk=1:nw=1 "$f" 2>/dev/null | tr -d '\r')"
  if [[ "$nb" =~ ^[0-9]+$ ]] && (( nb > 0 )); then
    echo "$nb"; return 0
  fi
  # Try container-declared nb_frames
  nb="$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=nb_frames -of default=nk=1:nw=1 "$f" 2>/dev/null | tr -d '\r')"
  if [[ "$nb" =~ ^[0-9]+$ ]] && (( nb > 0 )); then
    echo "$nb"; return 0
  fi
  # Fallback: duration * avg_frame_rate
  dur="$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$f" 2>/dev/null | tr -d '\r')"
  [[ -z "$dur" || "$dur" == "N/A" ]] && dur=0
  rate="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate \
          -of default=nk=1:nw=1 "$f" 2>/dev/null | tr -d '\r')"
  [[ -z "$rate" || "$rate" == "N/A" ]] && rate="0/1"
  fps="$(awk -v r="$rate" 'BEGIN{split(r,a,"/"); if(a[2]==0){print 0}else{printf "%.6f", a[1]/a[2]}}')"
  awk -v d="$dur" -v f="$fps" 'BEGIN{printf "%.0f", d*f}'
}

move_file() {
  local src="$1"
  # derive relative path (strip leading ./)
  local rel="${src#./}"
  # avoid re-moving files already under DEST_ROOT
  case "$rel" in
    "$DEST_ROOT"/*) echo "SKIP  $rel (already in $DEST_ROOT)"; return 0 ;;
  esac

  local frames
  frames="$(count_frames "$src" || echo 0)"

  if ! [[ "$frames" =~ ^[0-9]+$ ]]; then
    echo "WARN  Could not read frame count: $rel — skipping"
    return 0
  fi

  if (( frames < FRAMES )); then
    # Preserve substructure when RECURSE=1; otherwise rel dir will be "."
    local rel_dir dest_dir
    rel_dir="$(dirname "$rel")"
    [[ "$rel_dir" == "." ]] && rel_dir=""
    dest_dir="$DEST_ROOT/$rel_dir"
    mkdir -p "$dest_dir"
    echo "MOVE  $rel  ($frames < $FRAMES) -> $dest_dir/"
    if [[ "$DRYRUN" != "1" ]]; then
      if [[ "$OVERWRITE" == "1" ]]; then
        mv -f -- "$src" "$dest_dir/"
      else
        mv -n -- "$src" "$dest_dir/"
      fi
    fi
  else
    echo "KEEP  $rel  ($frames ≥ $FRAMES)"
  fi
}

processed=0; moved=0; kept=0; warned=0

if [[ "$RECURSE" == "1" ]]; then
  while IFS= read -r -d '' f; do
    ((processed++)) || true
    if out="$(move_file "$f" 2>&1)"; then
      echo "$out"
      [[ "$out" == MOVE* ]] && ((moved++)) || [[ "$out" == KEEP* ]] && ((kept++)) || true
    else
      echo "$out"
      ((warned++)) || true
    fi
  done < <(find . -type f -iname '*.mp4' -not -path "./$DEST_ROOT/*" -print0)
else
  while IFS= read -r -d '' f; do
    ((processed++)) || true
    if out="$(move_file "$f" 2>&1)"; then
      echo "$out"
      [[ "$out" == MOVE* ]] && ((moved++)) || [[ "$out" == KEEP* ]] && ((kept++)) || true
    else
      echo "$out"
      ((warned++)) || true
    fi
  done < <(find . -maxdepth 1 -type f -iname '*.mp4' -not -path "./$DEST_ROOT/*" -print0)
fi

echo "Done. processed=$processed  moved=$moved  kept=$kept  warnings=$warned  dest=$DEST_ROOT"
